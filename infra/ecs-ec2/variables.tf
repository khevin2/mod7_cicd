variable "aws_region" {
  type    = string
  default = "eu-north-1"
}

variable "project_name" {
  description = "Short, unique resource prefix for this lab."
  type        = string
  default     = "mod9-ecs"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,17}[a-z0-9]$", var.project_name))
    error_message = "Use 3–19 lowercase letters, numbers or hyphens, starting with a letter and ending with a letter or number."
  }
}

variable "owner" {
  description = "Owner tag for identifying lab resources."
  type        = string
  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "Specify a non-empty owner."
  }
}

variable "allowed_http_cidrs" {
  description = "Explicit client IPv4 CIDRs allowed to reach the lab ALB; use a narrow trusted range."
  type        = set(string)
  validation {
    condition     = length(var.allowed_http_cidrs) > 0 && alltrue([for cidr in var.allowed_http_cidrs : can(cidrhost(cidr, 0)) && cidr != "0.0.0.0/0" && !strcontains(cidr, ":")])
    error_message = "Provide at least one valid, non-world-open IPv4 CIDR."
  }
}

variable "vpc_cidr" {
  type    = string
  default = "10.90.0.0/16"
}

variable "subnet_cidrs" {
  type    = list(string)
  default = ["10.90.1.0/24", "10.90.2.0/24"]
  validation {
    condition     = length(var.subnet_cidrs) == 2 && alltrue([for cidr in var.subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Provide two subnet CIDRs in separate availability zones."
  }
}

variable "instance_type" {
  description = "x86_64 EC2 instance type; must support two task ENIs alongside the primary ENI."
  type        = string
  default     = "t3.small"
}

variable "release_image" {
  description = "Optional security-approved image from this stack's ECR repository, referenced by sha256 digest. Null provisions foundations only."
  type        = string
  default     = null
  nullable    = true
  validation {
    condition     = var.release_image == null ? true : can(regex("^[^@]+@sha256:[0-9a-f]{64}$", var.release_image))
    error_message = "release_image must be null or an image URI pinned to a sha256 digest."
  }
}

variable "log_retention_days" {
  type    = number
  default = 14
}
