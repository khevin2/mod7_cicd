variable "project_name" {
  description = "Project identifier used in key-pair and host names."
  type        = string
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

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
}

variable "root_volume_size_gib" {
  description = "Encrypted gp3 root-volume size in GiB."
  type        = number
}

variable "tags" {
  description = "Tags applied to host resources."
  type        = map(string)
}
