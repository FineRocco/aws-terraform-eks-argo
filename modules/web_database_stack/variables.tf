variable "environment" {
  description = "The deployment environment (dev, prod)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance size for EKS Node Group (Minimum t3.small required)"
  type        = string
  default     = "t3.small"
}

variable "eks_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.30"
} 