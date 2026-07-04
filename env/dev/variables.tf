variable "environment" {
  description = "The deployment environment (dev, prod)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance size"
  type        = string
}

variable "eks_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
}