output "instance_id" {
  description = "EC2 instance ID for sanitized operational evidence."
  value       = module.ec2_host.instance_id
}

output "public_dns" {
  description = "Public DNS name used for SSH host-key verification and HTTP checks."
  value       = module.ec2_host.public_dns
}

output "public_ip" {
  description = "Public IP used only for approved SSH and HTTP verification."
  value       = module.ec2_host.public_ip
}

output "ssh_username" {
  description = "SSH user supplied by the Amazon Linux 2023 AMI."
  value       = "ec2-user"
}

output "security_group_id" {
  description = "Deployment security group ID."
  value       = module.network.deployment_security_group_id
}

output "application_url" {
  description = "Expected public application URL after the Phase 6 deployment."
  value       = format("http://%s", module.ec2_host.public_dns)
}
