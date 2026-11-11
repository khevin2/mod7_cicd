variable "project_name" {
  description = "Project identifier used in key-pair and instance names."
  type        = string
}

variable "host_name" {
  description = "Role-specific suffix used in the EC2 instance name."
  type        = string
  default     = "deployment-host"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.host_name))
    error_message = "host_name must contain only lowercase letters, digits, and hyphens."
  }
}

variable "environment" {
  description = "Environment identifier used in key-pair and host names."
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID for the deployment host."
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for the deployment host."
  type        = string
}

variable "ssh_public_key" {
  description = "Existing Ed25519 public key content."
  type        = string
}

variable "key_pair_name" {
  description = "Optional explicit EC2 key-pair name. Null preserves the existing name convention."
  type        = string
  default     = null
  nullable    = true
}

variable "allocate_elastic_ip" {
  description = "Whether this host receives an Elastic IP for a stable public endpoint."
  type        = bool
  default     = false
}

variable "iam_instance_profile" {
  description = "Optional EC2 instance profile name for role-based AWS access."
  type        = string
  default     = null
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
}

variable "ami_id" {
  description = "Optional immutable AMI ID. Null retains automatic AL2023 selection for existing callers."
  type        = string
  default     = null
  validation {
    condition     = var.ami_id == null ? true : can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "Provide a valid AMI ID or null."
  }
}

variable "cpu_credit_mode" {
  description = "Optional burstable CPU credit policy. Null preserves the existing instance default."
  type        = string
  default     = null
  validation {
    condition     = var.cpu_credit_mode == null ? true : contains(["standard", "unlimited"], var.cpu_credit_mode)
    error_message = "CPU credit mode must be null, standard, or unlimited."
  }
}

variable "root_volume_size_gib" {
  description = "Encrypted gp3 root-volume size in GiB."
  type        = number
}

variable "tags" {
  description = "Tags applied to host resources."
  type        = map(string)
}
