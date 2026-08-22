variable "aws_region" {
  description = "AWS Region that will contain the Terraform state bucket."
  type        = string
  default     = "eu-north-1"
}

variable "state_bucket_name" {
  description = "Globally unique, non-secret name for the Terraform state bucket."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket_name)) && !can(regex("\\.\\.", var.state_bucket_name)) && !can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$", var.state_bucket_name))
    error_message = "state_bucket_name must be a 3-63 character lowercase S3-compatible name and must not resemble an IPv4 address."
  }
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
