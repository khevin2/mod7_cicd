variable "aws_region" {
  description = "AWS Region for the dedicated lab host."
  type        = string
  default     = "eu-north-1"
}

variable "project_name" {
  description = "Project tag value."
  type        = string
  default     = "jenkins-webapp"
}

variable "environment" {
  description = "Environment tag value."
  type        = string
  default     = "lab"
}

variable "owner" {
  description = "Owner tag value for the lab resources."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the dedicated lab VPC."
  type        = string
  default     = "10.70.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public lab subnet."
  type        = string
  default     = "10.70.1.0/24"

  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "public_subnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "availability_zone" {
  description = "Optional Availability Zone for the public subnet; leave null for AWS selection."
  type        = string
  default     = null
  nullable    = true
}

variable "jenkins_ssh_cidr" {
  description = "Public /32 CIDR of the approved Jenkins egress address."
  type        = string

  validation {
    condition     = can(cidrhost(var.jenkins_ssh_cidr, 0)) && endswith(var.jenkins_ssh_cidr, "/32") && !can(regex("^(10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[0-1])\\.)", split("/", var.jenkins_ssh_cidr)[0]))
    error_message = "jenkins_ssh_cidr must be a non-private public IPv4 /32; 0.0.0.0/0 and private ranges are not allowed."
  }
}

variable "administrator_ssh_cidr" {
  description = "Public /32 CIDR of the approved administrator egress address."
  type        = string

  validation {
    condition     = can(cidrhost(var.administrator_ssh_cidr, 0)) && endswith(var.administrator_ssh_cidr, "/32") && !can(regex("^(10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[0-1])\\.)", split("/", var.administrator_ssh_cidr)[0]))
    error_message = "administrator_ssh_cidr must be a non-private public IPv4 /32; 0.0.0.0/0 and private ranges are not allowed."
  }
}

variable "enable_ec2_instance_connect" {
  description = "Temporarily allow the regional EC2 Instance Connect service to SSH for trusted host-key verification. Disable after verification."
  type        = bool
  default     = false
}

variable "ssh_public_key_path" {
  description = "Path to the existing Ed25519 public key for ec2-user access. Never provide a private key path."
  type        = string

  validation {
    condition     = can(regex("^ssh-ed25519 [A-Za-z0-9+/]+={0,3}( .*)?$", trimspace(file(var.ssh_public_key_path))))
    error_message = "ssh_public_key_path must reference a valid Ed25519 OpenSSH public-key file."
  }
}

variable "instance_type" {
  description = "EC2 instance type for the deployment host."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size_gib" {
  description = "Size of the encrypted gp3 root volume in GiB."
  type        = number
  default     = 20

  validation {
    condition     = var.root_volume_size_gib >= 20
    error_message = "root_volume_size_gib must be at least 20 GiB to leave space for deployment images and logs."
  }
}
