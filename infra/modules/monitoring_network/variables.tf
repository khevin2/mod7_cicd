variable "vpc_cidr" {
  description = "Non-overlapping CIDR block for the dedicated monitoring VPC."
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR block for the monitoring host public subnet."
  type        = string
}

variable "availability_zone" {
  description = "Optional Availability Zone for the public subnet."
  type        = string
  default     = null
  nullable    = true
}

variable "grafana_admin_cidr" {
  description = "Approved non-private public IPv4 /32 permitted to reach Grafana HTTPS."
  type        = string

  validation {
    condition     = can(cidrhost(var.grafana_admin_cidr, 0)) && endswith(var.grafana_admin_cidr, "/32") && !can(regex("^(10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[0-1])\\.)", split("/", var.grafana_admin_cidr)[0]))
    error_message = "grafana_admin_cidr must be a non-private public IPv4 /32."
  }
}

variable "enable_ssh" {
  description = "Whether to allow emergency SSH from grafana_admin_cidr. SSM is preferred."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Ownership tags applied to monitoring network resources."
  type        = map(string)
}
