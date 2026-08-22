locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "Terraform"
  }
}

module "network" {
  source = "../modules/network"

  vpc_cidr                    = var.vpc_cidr
  public_subnet_cidr          = var.public_subnet_cidr
  availability_zone           = var.availability_zone
  ssh_ingress_cidrs           = [var.jenkins_ssh_cidr, var.administrator_ssh_cidr]
  enable_ec2_instance_connect = var.enable_ec2_instance_connect
  tags                        = local.common_tags
}

module "ec2_host" {
  source = "../modules/ec2_host"

  project_name         = var.project_name
  environment          = var.environment
  public_subnet_id     = module.network.public_subnet_id
  security_group_id    = module.network.deployment_security_group_id
  ssh_public_key       = trimspace(file(var.ssh_public_key_path))
  instance_type        = var.instance_type
  root_volume_size_gib = var.root_volume_size_gib
  tags                 = local.common_tags
}
