variable "vpc_cidr" {
  description = "CIDR block for the dedicated VPC."
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string
}

variable "availability_zone" {
  description = "Optional Availability Zone for the public subnet."
  type        = string
  default     = null
  nullable    = true
}

variable "jenkins_admin_ingress_cidrs" {
  description = "Approved public /32 CIDRs allowed to administer the Jenkins controller over SSH and HTTPS."
  type        = set(string)
}

variable "enable_jenkins_webhook_ingress" {
  description = "Whether to allow public HTTPS to Nginx for the GitHub webhook path. Nginx must enforce path and GitHub source restrictions first."
  type        = bool
  default     = false
}

variable "enable_jenkins_http_ingress" {
  description = "Whether to allow public HTTP for Let's Encrypt HTTP-01 validation and HTTPS redirects."
  type        = bool
  default     = false
}

variable "enable_ec2_instance_connect" {
  description = "Temporarily allow SSH from the regional EC2 Instance Connect service for trusted host-key verification."
  type        = bool
  default     = false
}

variable "monitoring_vpc_cidr" {
  description = "Optional approved peered monitoring VPC CIDR. It may scrape private app metrics and receive private OTLP/HTTP trace export on TCP 4318; never use a public CIDR."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.monitoring_vpc_cidr == null || can(cidrhost(var.monitoring_vpc_cidr, 0)) && !contains(["0.0.0.0/0"], var.monitoring_vpc_cidr)
    error_message = "monitoring_vpc_cidr must be a valid non-public CIDR for the private OTLP path."
  }
}

variable "app_monitoring_peering_connection_id" {
  description = "Optional approved application-to-monitoring VPC peering connection used for the private route."
  type        = string
  default     = null
  nullable    = true
}

variable "tags" {
  description = "Tags applied to network resources."
  type        = map(string)
}
