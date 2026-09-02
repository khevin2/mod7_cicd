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

variable "jenkins_ssh_public_key_path" {
  description = "Optional Ed25519 public key for Jenkins administration. Null reuses ssh_public_key_path; never provide a private key."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.jenkins_ssh_public_key_path == null || can(regex("^ssh-ed25519 [A-Za-z0-9+/]+={0,3}( .*)?$", trimspace(file(var.jenkins_ssh_public_key_path))))
    error_message = "jenkins_ssh_public_key_path must be null or reference a valid Ed25519 OpenSSH public-key file."
  }
}

variable "jenkins_instance_type" {
  description = "EC2 instance type for the cost-constrained Jenkins controller-runner."
  type        = string
  default     = "t3.micro"
}

variable "jenkins_root_volume_size_gib" {
  description = "Encrypted gp3 root-volume size in GiB for the Jenkins controller-runner."
  type        = number
  default     = 20

  validation {
    condition     = var.jenkins_root_volume_size_gib >= 20
    error_message = "jenkins_root_volume_size_gib must be at least 20 GiB."
  }
}

variable "jenkins_allocate_elastic_ip" {
  description = "Allocate an Elastic IP for a stable Jenkins HTTPS endpoint only after DNS ownership and cost are approved."
  type        = bool
  default     = false
}

variable "enable_jenkins_webhook_ingress" {
  description = "Open TCP 443 to Nginx for GitHub webhooks only after TLS, Nginx allow rules, and a stable Jenkins URL are verified."
  type        = bool
  default     = false
}

variable "enable_jenkins_http_ingress" {
  description = "Open TCP 80 for Let's Encrypt HTTP-01 validation and HTTPS redirects."
  type        = bool
  default     = false
}

variable "monitoring_vpc_cidr" {
  description = "Approved dedicated monitoring VPC CIDR."
  type        = string
  default     = "10.80.0.0/16"

  validation {
    condition     = var.monitoring_vpc_cidr == "10.80.0.0/16"
    error_message = "The approved monitoring VPC CIDR is 10.80.0.0/16."
  }
}

variable "monitoring_public_subnet_cidr" {
  description = "Approved public subnet CIDR in the monitoring VPC."
  type        = string
  default     = "10.80.1.0/24"

  validation {
    condition     = var.monitoring_public_subnet_cidr == "10.80.1.0/24"
    error_message = "The approved monitoring public subnet CIDR is 10.80.1.0/24."
  }
}

variable "monitoring_availability_zone" {
  description = "Optional monitoring host Availability Zone; align with the application host when approved."
  type        = string
  default     = null
  nullable    = true
}

variable "grafana_admin_cidr" {
  description = "Approved non-private public IPv4 /32 for monitoring HTTPS."
  type        = string
}

variable "monitoring_instance_type" {
  description = "Approved monitoring instance type."
  type        = string
  default     = "t3.small"

  validation {
    condition     = var.monitoring_instance_type == "t3.small"
    error_message = "t3.small is the approved monitoring size."
  }
}

variable "monitoring_root_volume_size_gib" {
  description = "Encrypted gp3 root volume size in GiB for the monitoring host."
  type        = number
  default     = 20

  validation {
    condition     = var.monitoring_root_volume_size_gib >= 20
    error_message = "monitoring_root_volume_size_gib must be at least 20 GiB."
  }
}

variable "monitoring_enable_ssh" {
  description = "Enable emergency monitoring SSH from the monitoring administrator CIDR. SSM is preferred."
  type        = bool
  default     = false
}

variable "monitoring_ssh_public_key_path" {
  description = "Existing Ed25519 public key path, required only when monitoring_enable_ssh is true."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.monitoring_ssh_public_key_path == null || can(regex("^ssh-ed25519 [A-Za-z0-9+/]+={0,3}( .*)?$", trimspace(file(var.monitoring_ssh_public_key_path))))
    error_message = "monitoring_ssh_public_key_path must be null or reference a valid Ed25519 OpenSSH public-key file."
  }
}

variable "enable_cross_vpc_private_dns" {
  description = "Keep false unless private cross-VPC DNS has been validated and is required."
  type        = bool
  default     = false
}

variable "enable_cloudtrail_archive" {
  description = "Create the dedicated lab CloudTrail archive only after refreshed discovery and exact saved-plan approval."
  type        = bool
  default     = false
}

variable "cloudtrail_archive_bucket_name" {
  description = "Globally unique approved S3 bucket name for the dedicated lab CloudTrail archive; required only when enable_cloudtrail_archive is true."
  type        = string
  default     = null
  nullable    = true
}

variable "enable_guardduty_detector" {
  description = "Create a new lab GuardDuty detector only if regional discovery confirms none exists and the exact saved plan is approved."
  type        = bool
  default     = false
}
