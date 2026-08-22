variable "bucket_name" {
  description = "Globally unique name of the Terraform state bucket."
  type        = string
}

variable "tags" {
  description = "Tags applied to the state bucket."
  type        = map(string)
}
