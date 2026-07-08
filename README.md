# Cloud-Native Web & Database Stack

An immutable, fully automated GitOps cloud infrastructure project. This repository provisions a secure, multi-AZ AWS network topology, deploys a containerized Python/Flask application onto an Amazon EKS (Kubernetes) cluster, attaches a zero-trust encrypted PostgreSQL database, and orchestrates zero-touch, pull-based deployments via Argo CD—all authenticated seamlessly via OpenID Connect (OIDC).

---

## The Tech Stack

This project integrates five distinct technology layers to create an automated pipeline:

* **Infrastructure as Code (IaC):** Terraform (State managed via AWS S3 Backend)
* **Cloud Provider (AWS):** VPC, EKS (Elastic Kubernetes Service), RDS PostgreSQL, ECR, S3, Secrets Manager, IAM (OIDC), Network Load Balancer (NLB)
* **CI/CD:** GitHub Actions (CI / Image Builds) & Argo CD (Continuous Delivery)
* **Container Orchestration:** Kubernetes
* **Containerization:** Docker
* **Application Layer:** Python 3.11, Flask, psycopg2-binary, Bash (Init Containers)

---

## System Architecture

This architecture relies on a highly secure "Pull-based" deployment lifecycle using Argo CD. Rather than pushing commands directly into servers, GitHub Actions simply builds the Docker image and updates the Kubernetes manifests in Git. Argo CD, sitting securely inside the EKS cluster, detects this change and automatically synchronizes the cluster state.

Secrets are never stored in Git or environment variables during build time. Instead, a Kubernetes initContainer dynamically fetches credentials from AWS Secrets Manager at runtime and mounts them into shared memory.

```text
                              [ Public Internet ]
                                     │ (HTTP :80)
                                     ▼
                     ┌───────────────────────────────┐
                     │  AWS Network Load Balancer    │
                     └───────────────┬───────────────┘
                                     │
        ┌────────────────────────────┴────────────────────────────┐
        │                          AWS VPC                        │
        │                                                         │
        │  ┌───────────────────────────────────────────────────┐  │
        │  │ Private Subnets (Multi-AZ Isolated)               │  │
        │  │                                                   │  │
        │  │  ┌─────────────────────────────────────────────┐  │  │
        │  │  │               Amazon EKS Cluster            │  │  │
        │  │  │                                             │  │  │
        │  │  │  ┌──────────────┐         ┌──────────────┐  │  │  │ (4) Init Container
        │  │  │  │   Argo CD    │         │  Flask App   │──┼──┼──┼──► fetches DB password
        │  │  │  │ (GitOps Ctrl)│         │ (Deployment) │  │  │  │    from Secrets Manager
        │  │  │  └──────┬───────┘         └──────┬───────┘  │  │  │    into shared memory
        │  │  └─────────┼────────────────────────┼──────────┘  │  │
        │  │            │ (Watches Git)          │ (TCP :5432) │  │
        │  │  ┌─────────▼───────┐      ┌─────────▼──────────┐  │  │
        │  │  │   GitHub Repo   │      │ AWS RDS PostgreSQL │  │  │
        │  │  │   (Manifests)   │      │   (Zero-Trust DB)  │  │  │
        │  │  └─────────────────┘      └────────────────────┘  │  │
        │  └───────────────────────────────────────────────────┘  │
        └─────────────────────────────────────────────────────────┘
                                     │ (HTTPS)
                            ┌────────▼──────────┐
                            │AWS Secrets Manager│
                            └───────────────────┘

=========================== CI/CD CONTROL PLANE ===========================
        
      ┌────────────────┐ (1) OIDC Auth  ┌───────────────┐
      │ GitHub Actions ├───────────────►│ AWS IAM Role  │
      └──────┬─────────┘                └───────────────┘
             │
             ├─────────────────► [ AWS ECR ] (2) Build & Push Docker Image
             │
             └─────────────────► [ Git Repo ] (3) Update Image Tag in Manifests
                                        ▲
                                        │ (5) Argo CD automatically detects
                                        │     commit and triggers Pod rollout

```

---

## Network Topology & Routing

This architecture employs a symmetric, two-tier Virtual Private Cloud (VPC) design across two Availability Zones (`eu-west-1a`, `eu-west-1b`), enforcing a strict separation between public ingress components and highly sensitive backend compute and data stores.
* **Internet Gateway (IGW):** The foundational ingress/egress anchor attached to the edge of the VPC. It translates internal private IP addresses to public routable addresses, acting as the sole bridge between the AWS network and the public internet.
* **Public Subnets (DMZ):** Houses the AWS Network Load Balancer (NLB) and NAT Gateway.
  * **Routing:** Governed by a Public Route Table that directs all outbound intern traffic (et`0.0.0.0/0`) directly to the Internet Gateway.
  * **Access:** Provides the public-facing entry point for user HTTP traffic, while shielding the actual compute instances.
* **Private Subnets:** Houses the EKS Worker Nodes and the AWS RDS PostgreSQL instance.
  * **Routing:** Governed by a Private Route Table that directs all outbound internet traffic to the NAT Gateway.
  * **NAT Gateway Architecture:** Unlike simpler topologies, this production-grade architecture utilizes a NAT Gateway. Because the EKS worker nodes are locked securely in private subnets without public IPs, they rely on the NAT Gateway to securely pull container images from ECR and fetch credentials from AWS Secrets Manager.

**This architecture intentionally omits a NAT Gateway.** Because AWS fully manages the underlying operating system and patching of the RDS PostgreSQL instance, the database never needs to initiate outbound internet requests. Furthermore, the EC2 instance pulling Docker images resides in the Public Subnet. Omitting the NAT Gateway eliminates a baseline cost.

### The Dual-Layer Firewall (Zero-Trust)

AWS network security is enforced at two distinct layers: the subnet boundary (stateless) and the instance boundary (stateful).

#### 1. Subnet-Level: Network Access Control Lists (NACLs)
NACLs act as the outermost perimeter fence. In this architecture, they operate in their default state (Allow All Inbound/Outbound), relying on the more granular Security Groups for filtering. However, they remain available as an incident response mechanism to instantly blacklist malicious CIDR blocks at the network edge during a DDoS attack.

#### 2. Instance-Level: Security Groups (SGs)
Security groups act as stateful, micro-segmented firewalls attached directly to the network interfaces of the resources. 
* **EKS Node Security Group:** Managed dynamically by EKS. Automatically permits necessary intra-cluster communication (Pod-to-Pod and Node-to-Control-Plane) while rejecting direct external internet access. Direct SSH is entirely disabled.
* **`db_sg` (The Vault Door):** Attached to the RDS instance. Employs a zero-trust ingress rule that allows `TCP 5432` (PostgreSQL) *only* if the traffic originates from within the VPC (EKS Worker Nodes). It rejects all other internal VPC traffic by default.

### Advanced IMDSv2 Security

To defend against SSRF (Server-Side Request Forgery) attacks, the EKS Worker Nodes enforce IMDSv2 (Instance Metadata Service v2) via a custom AWS Launch Template. The template explicitly sets the network hop limit to 2, securely bridging the gap between the virtual Kubernetes Pod network and the underlying EC2 host network, ensuring the Init Containers can successfully retrieve IAM Role credentials without exposing the metadata service.

---

## Terraform State Management & Concurrency Control

In a production-grade CI/CD environment, infrastructure state cannot reside locally or ephemerally on a GitHub runner. It must be centralized, encrypted, and strictly protected against concurrent execution. 

### The Remote Backend Bootstrap
* **AWS S3 (State Storage):** The `terraform.tfstate` file is stored in a heavily restricted, versioned, and encrypted S3 bucket. This acts as the absolute single source of truth for the environment's configuration.
* **Native S3 State Locking** To prevent race conditions—where two developers push to main simultaneously and trigger parallel GitHub Actions runners—this architecture utilizes Terraform's native S3 state locking (use_lockfile = true). When a pipeline initiates terraform plan or apply, it requests a lock directly in the S3 bucket. Any concurrent pipeline runs will be queued or rejected until the lock is released, completely eliminating the risk of state corruption without requiring a legacy DynamoDB table.

---

## Key DevSecOps & OPSEC Principles

1. **Zero-Knowledge Secret Injection:** The PostgreSQL master password is dynamically generated at high entropy via Terraform (`random_password`) and injected directly into **AWS Secrets Manager**. GitHub Actions never reads, caches, or echoes this password. During cluster deployment, a Kubernetes `initContainer` leverages the EKS Node's IAM profile to cryptographically pull the secret from the vault and parse it directly into an ephemeral shared volume, bypassing environment variable logging completely.
2. **Keyless CI/CD Authentication:** GitHub Actions authenticates against AWS utilizing **OpenID Connect (OIDC)**. Long-lived, static `AWS_ACCESS_KEY_ID` secrets do not exist anywhere in this project's repositories or environments.
3. **Bastionless Remote Access:** Because SSH Port 22 is explicitly disabled, all cluster debugging and administrative access is tunneled securely through the Kubernetes API (authenticated via EKS IAM Access Entries) and the encrypted Argo CD management portal.
---

## Automated CI/CD Lifecycle

When a developer merges code into the `main` branch, `.github/workflows/main-apply.yml` triggers a deterministic, zero-touch deployment pipeline. The lifecycle is strictly divided between GitHub Actions (Continuous Integration) and Argo CD (Continuous Deployment).

### Phase 1: Continuous Integration & Infrastructure (GitHub Actions)
1. **OIDC Authentication:** The runner securely assumes the `GitHubActionsRole` in AWS via OpenID Connect.
2. **Infrastructure IaC Gate:** Terraform initializes the remote backend (utilizing native S3 state locking) and applies infrastructure changes (`-auto-approve`).
3. **Variable Extraction:** The pipeline uses `terraform output -raw` to dynamically scrape the newly generated EKS Name, RDS Endpoint, and ECR Repository URL directly from the active state file.
4. **Artifact Compilation:** The lightweight Python/Flask Docker image is built, tagged, and pushed to Amazon ECR.
5. **GitOps Sync:** Instead of pushing the image directly to the cluster, GitHub Actions executes an automated commit back to the main branch, updating the k8s/deployment.yaml file with the newly generated image tag.

### Phase 2: Continuous Deployment & Rollout (Argo CD & Kubernetes)
Once the Git commit is registered, the Argo CD controller running securely inside the EKS DMZ initiates the rollout:

1. **Drift Detection:** Argo CD detects that the desired state in GitHub no longer matches the live cluster state.
2. **Rolling Update Trigger:** Kubernetes initiates a zero-downtime rolling update, booting new replica pods in the background.
3. **Zero-Knowledge Extraction:** The `fetch-secrets` Init Container starts first. It utilizes the IMDSv2 hop-limit bypass to authenticate with AWS, downloads the database password via `aws secretsmanager`, and writes it to a `.env` file on an isolated `emptyDir` volume.
4. **Container Boot:** Spins up the new Docker container bound to port `80:80`, injecting the database credentials and endpoints securely via runtime environment variables (`-e`).
5. **Database Seeding:** Pauses for container socket binding, then natively executes `seed_db.py` inside the live container to initialize the PostgreSQL schema and seed the application data.
6. **Traffic Shift** Once Kubernetes health-checks confirm the new pods are stable and serving traffic, it gracefully terminates the legacy pods, finalizing the deployment.
  
---
  
## Repository Structure

This repository strictly separates Application Code, Deployment Lifecycle Scripts, and Infrastructure as Code (IaC) to ensure a clean separation of concerns.

```text
.
├── .github/
│   └── workflows/
│       ├── main-apply.yml          # Continuous Deployment pipeline
│       ├── pr-plan.yml             # CI/CD security gate: Terraform plan & PR validation
│       └── teardown.yaml           # Automated cleanup and infrastructure destruction
├── app/
│   ├── app.py                      # Flask web application & RDS Read route
│   ├── seed_db.py                  # Auto-seeder with cryptographic password generation
│   ├── Dockerfile                  # Python 3.11 slim container build instructions
│   └── requirements.txt            # Python dependencies (Flask, psycopg2-binary)
├── env/
│   ├── dev/
│   │   ├── main.tf                 # Root module instantiation for the Development environment
│   │   ├── provider.tf             # AWS provider declaration and region config
│   │   ├── outputs.tf              # Catches module outputs for GitHub Actions extraction
│   │   ├── backend.tf              # S3 remote state with native locking configuration
│   │   ├── terraform.tfvars        # Environment-specific values
│   │   └── variables.tf            # Input variable definitions and expected data types
│   └── prod/
│       ├── main.tf                 # Root module instantiation for the Production environment
│       ├── provider.tf             # AWS provider declaration and region config
│       ├── outputs.tf              # Catches module outputs for GitHub Actions extraction
│       ├── backend.tf              # S3 remote state with native locking configuration
│       ├── terraform.tfvars        # Production-grade values
│       └── variables.tf            # Input variable definitions and expected data types
├── k8s/
│   ├── argocd-app.yaml             # Argo CD Application manifest for GitOps tracking
│   ├── deployment.yaml             # Kubernetes Deployment (Pods, InitContainers, Secrets mapping)
│   └── services.yaml               # Kubernetes Service (AWS Network Load Balancer)
├── modules/
│   └── web_database_stack/
│       ├── main.tf                 # Core infra (EKS, Node Groups, RDS, ECR, Secrets Manager)
│       ├── network.tf              # VPC, DMZ Subnets, Private Subnets, Route Tables, NAT Gateway
│       ├── outputs.tf              # Module attribute pitchers to pass data upstream
│       ├── security.tf             # IAM Roles, Policies, Security Groups
│       └── variables.tf            # Dynamic module input variables
├── tf-boostrap-backend/
│   └── main.tf                     # OIDC Identity Provider & GitHub Actions IAM Role setup
├── .gitignore                      # Ignores local .terraform directories and .env files
└── README.md                       # Master architecture document and efficiency assessment

```

---

## Challenges & Architectural Pivots

Building a fully automated DevSecOps pipeline from scratch presented several real-world cloud engineering challenges. Documenting these roadblocks highlights the resilience and adaptability of the final architecture.

### 1. IMDSv2 Hop Limits & Pod Secret Extraction
* **The Blocker:** EKS worker nodes utilize IMDSv2 for robust security. However, the Flask `initContainers` repeatedly crashed when attempting to retrieve the DB password from Secrets Manager, returning `NoCredentialsError`.
* **The Cause:** IMDSv2 defaults to a network hop limit of `1`. Because Kubernetes pods run on a virtual network bridge inside the EC2 node, reaching the metadata service required 2 network hops, causing AWS to drop the security packets.
* **The Pivot:** Instead of downgrading to IMDSv1, a custom `aws_launch_template` was deployed for the EKS Node Group to permanently encode the `http_put_response_hop_limit` to `2`. This safely bridged the gap between the container network and the AWS API without compromising host security.
### 2. Argo CD Finalizers & Teardown Deadlocks
* **The Blocker:** Running `terraform destroy` frequently failed with `DependencyViolation` errors on the VPC subnets, causing the teardown pipeline to hang indefinitely.
* **The Cause:** Argo CD dynamically provisions an AWS Network Load Balancer (NLB) via Kubernetes Service manifests. Terraform is blind to this NLB. Furthermore, Argo CD apps utilize Kubernetes finalizers (`resources-finalizer.argocd.argoproj.io`), causing standard deletion commands to deadlock if the NLB cleanup stalls in AWS.
* **The Pivot:** Engineered an automated `teardown.yaml` workflow. Before Terraform runs, the script forcefully deletes the NLB service, patches out the Argo CD finalizers (`{"metadata": {"finalizers": null}}`), and intentionally pauses for 120 seconds. This allows AWS time to release all Elastic Network Interfaces (ENIs), guaranteeing a clean, error-free VPC destruction.
---

## Deployment & Operations Guide

Because this architecture relies on OpenID Connect (OIDC) and remote state locking, it requires a one-time manual bootstrap to establish trust between GitHub and AWS before the automated CI/CD pipeline can take over.

### Prerequisites
* An AWS Account with administrative access.
* A GitHub Repository containing this code.
* AWS CLI and Terraform installed on your local machine.
* Run `aws configure` locally with a temporary Access Key to authorize your terminal for the initial bootstrap.

### Phase 1: The Cloud Bootstrap (Local Execution)
Before GitHub Actions can deploy your infrastructure, it needs a legal identity (IAM Role) and a place to store its memory (Terraform State).

1. **Configure the OIDC Trust Policy:**
   Before applying the bootstrap, you must update the OIDC Trust Policy to point to your specific GitHub repository so AWS knows who to trust. 
   > Open `tf-boostrap-backend/main.tf`, locate the `Condition` block inside the IAM Role, and change the placeholder to your exact GitHub username and repository name:
   > `"token.actions.githubusercontent.com:sub" = "repo:<YOUR_GITHUB_USERNAME>/<YOUR_REPOSITORY_NAME>:*"`

2. **Establish the OIDC Trust Bridge:**
   Navigate to the bootstrap directory and apply the configuration to create the GitHub Actions IAM Role and the S3 Bucket:
   ```bash
   cd tf-boostrap-backend
   terraform init
   terraform apply -auto-approve
   ```
   Take note of the `github_actions_role_arn` output.

### Phase 2: Pipeline Alignment
Because OIDC relies on AWS-side trust policies rather than hidden keys, no GitHub Secrets are needed. You simply need to align your configuration files:

1. **GitHub Actions YAML:** Open `.github/workflows/main-apply.yml`, `.github/workflows/pr-plan.yml`, and `.github/workflows/teardown.yaml`. Update the `role-to-assume` parameter with the IAM Role ARN generated in Phase 1.

2. **Backend Configuration:** Update `env/dev/backend.tf` and `env/prod/backend.tf` to point to the exact S3 bucket you created in Phase 1.

3. **EKS Access Entry:** In `.github/workflows/main-apply.yml`, locate the final deployment step and replace `<YOUR_ARN>` with your personal AWS IAM User ARN. This ensures you are granted admin rights to the newly created EKS cluster and can run `kubectl` commands locally.

### Phase 3: Verify the Application:

Once the GitHub Actions pipeline finishes provisioning the infrastructure and pushing the GitOps commit, Argo CD will automatically detect the drift and initiate the Pod rollout.

1. Fetch your local Kubernetes config to connect to the cluster:

   ```bash
   aws eks update-kubeconfig --region eu-west-1 --name dev-cluster
   ```

2. Extract the Network Load Balancer (NLB) hostname by running:

   ```bash
   kubectl get svc flask-app-service
   ```

3. Visit the `EXTERNAL-IP` address in your browser (e.g., `http://<NLB_HOSTNAME>`) to see your zero-knowledge database secret retrieved live!

---

## Teardown Protocol

Because Argo CD dynamically provisions AWS Load Balancers that Terraform is blind to, tearing down the environment locally using standard Terraform commands can cause severe dependency deadlocks and `DependencyViolation` errors.

1. **Automated Infrastructure Teardown:**

* Navigate to your repository on GitHub.com.

* Click the **Actions** tab.

* Select the **Destroy Infrastructure** workflow on the left.

* Click the **Run workflow** dropdown and execute it.
  
This pipeline will automatically remove Kubernetes finalizers, purge the ECR registry, delete the NLB, and cleanly execute terraform destroy.

2. **Destroy the Cloud Bootstrap (Local Execution):**

Once the GitHub Actions pipeline successfully destroys the main environment, you can safely remove the OIDC IAM roles and the S3 state bucket from your local machine:

  ```bash
  cd tf-bootstrap-backend
  terraform destroy -auto-approve
  ```
   
  
