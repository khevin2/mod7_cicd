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

variable "ssh_ingress_cidrs" {
  description = "Approved public /32 CIDRs allowed to SSH to the deployment host."
  type        = set(string)
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

variable "tags" {
  description = "Tags applied to network resources."
  type        = map(string)
}
