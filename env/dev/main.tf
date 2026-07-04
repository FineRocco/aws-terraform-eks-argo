module "dev_stack" {
  source = "../../modules/web_database_stack"
  
  environment    = var.environment
  instance_type  = var.instance_type
  eks_version   = var.eks_version
}