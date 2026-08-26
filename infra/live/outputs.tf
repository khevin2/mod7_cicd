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

output "application_private_ip" {
  description = "Private application-host address for Jenkins-to-application deployment traffic."
  value       = module.ec2_host.private_ip
}

output "application_url" {
  description = "Expected public application URL after the Phase 6 deployment."
  value       = format("http://%s", module.ec2_host.public_dns)
}

output "jenkins_instance_id" {
  description = "Jenkins controller-runner EC2 instance ID."
  value       = module.jenkins_host.instance_id
}

output "jenkins_public_dns" {
  description = "Jenkins controller-runner public DNS name. Configure the final stable DNS name separately."
  value       = module.jenkins_host.public_dns
}

output "jenkins_public_ip" {
  description = "Jenkins controller-runner public IP address."
  value       = module.jenkins_host.public_ip
}

output "jenkins_elastic_ip" {
  description = "Optional stable Jenkins Elastic IP address when allocation is enabled."
  value       = module.jenkins_host.elastic_ip
}

output "jenkins_security_group_id" {
  description = "Jenkins controller security group ID."
  value       = module.network.jenkins_security_group_id
}
