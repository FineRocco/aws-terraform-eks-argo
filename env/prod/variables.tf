variable "environment" {
  description = "The deployment environment (dev, prod)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance size"
  type        = string
}