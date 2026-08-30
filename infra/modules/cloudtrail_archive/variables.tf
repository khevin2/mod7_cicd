variable "enabled" {
  description = "Create the dedicated lab archive only after discovery and exact saved-plan approval."
  type        = bool
  default     = false
}

variable "aws_region" { type = string }
variable "partition" { type = string }
variable "account_id" { type = string }
variable "project_name" { type = string }
variable "environment" { type = string }
variable "tags" { type = map(string) }

variable "trail_name" {
  description = "Name for the dedicated lab management-event trail."
  type        = string
}

variable "bucket_name" {
  description = "Globally unique, approved archive bucket name. Required only when enabled."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = !var.enabled || (
      var.bucket_name != null &&
      can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name)) &&
      !can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.bucket_name))
    )
    error_message = "When enabled, bucket_name must be a valid non-IP-address S3 bucket name."
  }
}

variable "key_prefix" {
  description = "Fixed archive prefix used by the bucket policy and lifecycle rule."
  type        = string
  default     = "cloudtrail"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,62}$", var.key_prefix))
    error_message = "key_prefix must contain only lowercase letters, digits, and hyphens."
  }
}
