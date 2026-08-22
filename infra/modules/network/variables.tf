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

variable "enable_ec2_instance_connect" {
  description = "Temporarily allow SSH from the regional EC2 Instance Connect service for trusted host-key verification."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to network resources."
  type        = map(string)
}
