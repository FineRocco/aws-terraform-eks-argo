output "db_endpoint" {
  description = "The connection string for the RDS PostgreSQL database"
  value       = aws_db_instance.postgres.address
}

output "ecr_repository_url" {
  description = "The URL of the ECR repository to push Docker images to"
  value       = aws_ecr_repository.app_repo.repository_url
}

output "eks_cluster_name" {
  description = "The name of the EKS cluster"
  value       = aws_eks_cluster.eks_cluster.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.eks_cluster.endpoint
}