variable "application_vpc_id" { type = string }
variable "application_vpc_cidr" { type = string }
variable "monitoring_vpc_id" { type = string }
variable "monitoring_vpc_cidr" { type = string }
variable "enable_cross_vpc_private_dns" {
  description = "Enable only after a validated requirement for private cross-VPC DNS resolution exists."
  type        = bool
  default     = false
}
variable "tags" { type = map(string) }
