terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.72.0"
    }
  }
}

provider "aws" {
  region              = "eu-north-1"
  allowed_account_ids = ["447558491229"]
  default_tags {
    tags = local.tags
  }
}

variable "owner" {
  type = string
  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "Specify a nonempty owner tag."
  }
}

variable "admin_cidr" {
  type = string
  validation {
    condition     = can(cidrnetmask(var.admin_cidr)) && endswith(var.admin_cidr, "/32")
    error_message = "Provide your public IPv4 address followed by /32."
  }
}

variable "ssh_public_key_path" {
  type        = string
  description = "Public key path relative to this Terraform root; never a private key."
  default     = "../../keys/mod9-ci.pub"
  validation {
    condition     = can(regex("^ssh-ed25519 ", trimspace(file(var.ssh_public_key_path))))
    error_message = "Provide an existing Ed25519 OpenSSH public key."
  }
}

locals {
  tags = {
    Project     = "mod9-ci"
    Environment = "lab"
    Owner       = var.owner
    ManagedBy   = "Terraform"
  }
}

resource "aws_vpc" "ci" {
  cidr_block           = "10.80.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "ci" {
  vpc_id = aws_vpc.ci.id
}

resource "aws_subnet" "ci" {
  vpc_id                  = aws_vpc.ci.id
  cidr_block              = "10.80.1.0/24"
  map_public_ip_on_launch = true
}

resource "aws_route_table" "ci" {
  vpc_id = aws_vpc.ci.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ci.id
  }
}

resource "aws_route_table_association" "ci" {
  subnet_id      = aws_subnet.ci.id
  route_table_id = aws_route_table.ci.id
}

resource "aws_security_group" "ci" {
  name_prefix = "mod9-ci-"
  description = "CI administration through SSH tunnels"
  vpc_id      = aws_vpc.ci.id
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.ci.id
  description       = "SSH from administrator"
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "web" {
  for_each          = toset(["80", "443"])
  security_group_id = aws_security_group.ci.id
  description       = "Package repositories and external services"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
}

module "ci_host" {
  source               = "../modules/ec2_host"
  project_name         = "mod9-ci"
  environment          = "lab"
  host_name            = "jenkins-sonarqube"
  public_subnet_id     = aws_subnet.ci.id
  security_group_id    = aws_security_group.ci.id
  ssh_public_key       = trimspace(file(var.ssh_public_key_path))
  instance_type        = "t3.small"
  ami_id               = "ami-0c0427b4be074f058"
  cpu_credit_mode      = "standard"
  root_volume_size_gib = 40
  allocate_elastic_ip  = false
  tags                 = local.tags
  depends_on = [
    aws_route_table_association.ci,
    aws_vpc_security_group_egress_rule.web,
  ]
}

output "instance_id" {
  value = module.ci_host.instance_id
}

output "public_ip" {
  value = module.ci_host.public_ip
}
