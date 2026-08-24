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

  vpc_cidr                       = var.vpc_cidr
  public_subnet_cidr             = var.public_subnet_cidr
  availability_zone              = var.availability_zone
  ssh_ingress_cidrs              = [var.jenkins_ssh_cidr, var.administrator_ssh_cidr]
  jenkins_admin_ingress_cidrs    = [var.administrator_ssh_cidr]
  enable_jenkins_http_ingress    = var.enable_jenkins_http_ingress
  enable_jenkins_webhook_ingress = var.enable_jenkins_webhook_ingress
  enable_ec2_instance_connect    = var.enable_ec2_instance_connect
  tags                           = local.common_tags
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

module "jenkins_host" {
  source = "../modules/ec2_host"

  project_name         = var.project_name
  environment          = var.environment
  host_name            = "jenkins-controller"
  key_pair_name        = format("%s-%s-jenkins-controller", var.project_name, var.environment)
  public_subnet_id     = module.network.public_subnet_id
  security_group_id    = module.network.jenkins_security_group_id
  ssh_public_key       = trimspace(file(coalesce(var.jenkins_ssh_public_key_path, var.ssh_public_key_path)))
  instance_type        = var.jenkins_instance_type
  root_volume_size_gib = var.jenkins_root_volume_size_gib
  allocate_elastic_ip  = var.jenkins_allocate_elastic_ip
  tags                 = merge(local.common_tags, { Role = "jenkins-controller-runner" })
}
