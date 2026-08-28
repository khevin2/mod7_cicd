variable "project_name" { type = string }
variable "environment" { type = string }
variable "role_suffix" { type = string }
variable "log_group_arns" {
  description = "Only the CloudWatch log groups this host may write."
  type        = list(string)
}
variable "tags" { type = map(string) }
