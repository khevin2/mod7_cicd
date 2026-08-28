variable "project_name" { type = string }
variable "environment" { type = string }
variable "public_subnet_id" { type = string }
variable "security_group_id" { type = string }
variable "instance_profile_name" { type = string }
variable "instance_type" { type = string }
variable "root_volume_size_gib" { type = number }
variable "enable_ssh" { type = bool }
variable "ssh_public_key" {
  description = "Optional Ed25519 public key content, required only when SSH is enabled."
  type        = string
  default     = null
  nullable    = true
}
variable "tags" { type = map(string) }
