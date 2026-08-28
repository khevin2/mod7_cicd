locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "Terraform"
  }

  application_log_group_names = [
    format("/%s/%s/application/containers", var.project_name, var.environment),
  ]

  monitoring_log_group_names = [
    format("/%s/%s/monitoring/containers", var.project_name, var.environment),
    format("/%s/%s/monitoring/system", var.project_name, var.environment),
  ]
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_iam_policy_document" "monitoring_secrets_key" {
  statement {
    sid       = "EnableAccountRootAdministration"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [format("arn:aws:iam::%s:root", data.aws_caller_identity.current.account_id)]
    }
  }
}

resource "aws_kms_key" "monitoring_secrets" {
  description             = "Encrypts only Project 6 monitoring secret containers."
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.monitoring_secrets_key.json
  tags                    = merge(local.common_tags, { Role = "monitoring-secrets" })
}

resource "aws_kms_alias" "monitoring_secrets" {
  name          = format("alias/%s-%s-monitoring-secrets", var.project_name, var.environment)
  target_key_id = aws_kms_key.monitoring_secrets.key_id
}

data "aws_iam_policy_document" "cloudwatch_logs_key" {
  statement {
    sid       = "EnableAccountRootAdministration"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [format("arn:aws:iam::%s:root", data.aws_caller_identity.current.account_id)]
    }
  }

  statement {
    sid    = "AllowCloudWatchLogsForNamedGroups"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = [format("logs.%s.amazonaws.com", var.aws_region)]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        format("arn:%s:logs:%s:%s:log-group:/%s/%s/*", data.aws_partition.current.partition, var.aws_region, data.aws_caller_identity.current.account_id, var.project_name, var.environment),
      ]
    }
  }
}

resource "aws_kms_key" "cloudwatch_logs" {
  description             = "Encrypts only Project 6 application and monitoring CloudWatch log groups."
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.cloudwatch_logs_key.json
  tags                    = merge(local.common_tags, { Role = "cloudwatch-logs" })
}

resource "aws_kms_alias" "cloudwatch_logs" {
  name          = format("alias/%s-%s-cloudwatch-logs", var.project_name, var.environment)
  target_key_id = aws_kms_key.cloudwatch_logs.key_id
}

resource "aws_cloudwatch_log_group" "application_containers" {
  name              = local.application_log_group_names[0]
  retention_in_days = 14
  kms_key_id        = aws_kms_key.cloudwatch_logs.arn
  tags              = merge(local.common_tags, { Role = "application-containers" })
}

resource "aws_cloudwatch_log_group" "monitoring_containers" {
  name              = local.monitoring_log_group_names[0]
  retention_in_days = 14
  kms_key_id        = aws_kms_key.cloudwatch_logs.arn
  tags              = merge(local.common_tags, { Role = "monitoring-containers" })
}

resource "aws_cloudwatch_log_group" "monitoring_system" {
  name              = local.monitoring_log_group_names[1]
  retention_in_days = 14
  kms_key_id        = aws_kms_key.cloudwatch_logs.arn
  tags              = merge(local.common_tags, { Role = "monitoring-system" })
}

module "network" {
  source = "../modules/network"

  vpc_cidr                       = var.vpc_cidr
  public_subnet_cidr             = var.public_subnet_cidr
  availability_zone              = var.availability_zone
  jenkins_admin_ingress_cidrs    = [var.administrator_ssh_cidr]
  enable_jenkins_http_ingress    = var.enable_jenkins_http_ingress
  enable_jenkins_webhook_ingress = var.enable_jenkins_webhook_ingress
  enable_ec2_instance_connect    = var.enable_ec2_instance_connect
  tags                           = local.common_tags
}

module "ec2_host" {
  source = "../modules/ec2_host"

  project_name          = var.project_name
  environment           = var.environment
  public_subnet_id      = module.network.public_subnet_id
  security_group_id     = module.network.deployment_security_group_id
  ssh_public_key        = trimspace(file(var.ssh_public_key_path))
  instance_type         = var.instance_type
  root_volume_size_gib  = var.root_volume_size_gib
  instance_profile_name = module.application_logging_identity.instance_profile_name
  tags                  = local.common_tags
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

module "monitoring_network" {
  source = "../modules/monitoring_network"

  vpc_cidr           = var.monitoring_vpc_cidr
  public_subnet_cidr = var.monitoring_public_subnet_cidr
  availability_zone  = var.monitoring_availability_zone
  grafana_admin_cidr = var.grafana_admin_cidr
  enable_ssh         = var.monitoring_enable_ssh
  tags               = local.common_tags
}

module "monitoring_secrets" {
  source = "../modules/monitoring_secrets"

  aws_region   = var.aws_region
  project_name = var.project_name
  environment  = var.environment
  kms_key_arn  = aws_kms_key.monitoring_secrets.arn
  tags         = local.common_tags
}

module "monitoring_identity" {
  source = "../modules/monitoring_identity"

  project_name            = var.project_name
  environment             = var.environment
  secret_read_policy_json = module.monitoring_secrets.runtime_read_policy_json
  log_group_arns = [
    for name in local.monitoring_log_group_names :
    format("arn:%s:logs:%s:%s:log-group:%s", data.aws_partition.current.partition, var.aws_region, data.aws_caller_identity.current.account_id, name)
  ]
  tags = local.common_tags
}

module "application_logging_identity" {
  source = "../modules/logging_identity"

  project_name = var.project_name
  environment  = var.environment
  role_suffix  = "application-host"
  log_group_arns = [
    for name in local.application_log_group_names :
    format("arn:%s:logs:%s:%s:log-group:%s", data.aws_partition.current.partition, var.aws_region, data.aws_caller_identity.current.account_id, name)
  ]
  tags = local.common_tags
}

module "monitoring_host" {
  source = "../modules/monitoring_host"

  project_name          = var.project_name
  environment           = var.environment
  public_subnet_id      = module.monitoring_network.public_subnet_id
  security_group_id     = module.monitoring_network.security_group_id
  instance_profile_name = module.monitoring_identity.instance_profile_name
  instance_type         = var.monitoring_instance_type
  root_volume_size_gib  = var.monitoring_root_volume_size_gib
  enable_ssh            = var.monitoring_enable_ssh
  ssh_public_key        = var.monitoring_ssh_public_key_path == null ? null : trimspace(file(var.monitoring_ssh_public_key_path))
  tags                  = merge(local.common_tags, { Role = "monitoring" })
}

module "app_monitoring_peering" {
  source = "../modules/vpc_peering"

  application_vpc_id            = module.network.vpc_id
  application_vpc_cidr          = var.vpc_cidr
  application_route_table_id    = module.network.public_route_table_id
  application_security_group_id = module.network.deployment_security_group_id
  monitoring_vpc_id             = module.monitoring_network.vpc_id
  monitoring_vpc_cidr           = var.monitoring_vpc_cidr
  monitoring_route_table_id     = module.monitoring_network.public_route_table_id
  monitoring_security_group_id  = module.monitoring_network.security_group_id
  enable_cross_vpc_private_dns  = var.enable_cross_vpc_private_dns
  tags                          = local.common_tags
}
