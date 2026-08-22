locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "Terraform"
  }
}

module "state_backend" {
  source = "../modules/state_backend"

  bucket_name = var.state_bucket_name
  tags        = local.common_tags
}
