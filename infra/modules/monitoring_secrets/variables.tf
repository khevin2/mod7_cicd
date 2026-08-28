variable "aws_region" {
  description = "AWS Region containing the monitoring secrets and KMS key."
  type        = string
}

variable "project_name" {
  description = "Project identifier used in secret names."
  type        = string
}

variable "environment" {
  description = "Environment identifier used in secret names."
  type        = string
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key ARN used only for the monitoring secret containers."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:kms:[^:]+:[0-9]{12}:key/[0-9a-f-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a customer-managed KMS key ARN."
  }
}

variable "tags" {
  description = "Ownership tags applied to both secret containers."
  type        = map(string)

  validation {
    condition = alltrue([
      for key in ["Project", "Environment", "Owner", "ManagedBy"] :
      contains(keys(var.tags), key) && trimspace(var.tags[key]) != ""
    ])
    error_message = "tags must include non-empty Project, Environment, Owner, and ManagedBy values."
  }
}
