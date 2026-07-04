output "ecr_repository_url" {
  description = "The ECR URL for the GitHub Actions pipeline"
  value       = module.dev_stack.ecr_repository_url
}

output "dev_db_endpoint" {
  description = "The RDS connection string"
  value       = module.dev_stack.db_endpoint
}

output "eks_cluster_name" {
  description = "The name of the EKS cluster for local kubectl auth"
  value       = module.dev_stack.eks_cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.dev_stack.eks_cluster_endpoint
}