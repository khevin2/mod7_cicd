variable "project_name" { type = string }
variable "environment" { type = string }
variable "secret_read_policy_json" { type = string }
variable "log_group_arns" {
  description = "ARNs of the Phase 5 monitoring log groups to which the instance may write."
  type        = list(string)
}
variable "tags" { type = map(string) }
