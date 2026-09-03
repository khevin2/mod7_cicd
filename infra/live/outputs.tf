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

output "application_public_route_table_id" {
  description = "Application route table ID used by the managed monitoring peering route."
  value       = module.network.public_route_table_id
}

output "monitoring_vpc_id" {
  description = "Dedicated monitoring VPC ID."
  value       = module.monitoring_network.vpc_id
}

output "monitoring_elastic_ip" {
  description = "Create and verify DNS-only grafana.kheven.me and metrics.kheven.me A records before certificate issuance."
  value       = module.monitoring_host.elastic_ip
}

output "monitoring_instance_id" {
  description = "Monitoring EC2 instance ID."
  value       = module.monitoring_host.instance_id
}

output "monitoring_security_group_id" {
  description = "Monitoring host security group ID."
  value       = module.monitoring_network.security_group_id
}

output "monitoring_slack_webhook_secret_arn" {
  description = "Empty secret container ARN; set its value out of band only."
  value       = module.monitoring_secrets.slack_webhook_secret_arn
}

output "monitoring_cloudflare_dns_token_secret_arn" {
  description = "Empty secret container ARN; set its value out of band only."
  value       = module.monitoring_secrets.cloudflare_dns_token_secret_arn
}

output "monitoring_prometheus_basic_auth_htpasswd_secret_arn" {
  description = "Empty bcrypt htpasswd secret container ARN; set its value out of band only."
  value       = module.monitoring_secrets.prometheus_basic_auth_htpasswd_secret_arn
}

output "app_monitoring_vpc_peering_connection_id" {
  description = "Private application-to-monitoring VPC peering connection ID."
  value       = module.app_monitoring_peering.connection_id
}

output "application_container_log_group_name" {
  description = "Pre-created encrypted 14-day CloudWatch log group for the application Docker awslogs driver."
  value       = aws_cloudwatch_log_group.application_containers.name
}

output "monitoring_container_log_group_name" {
  description = "Pre-created encrypted 14-day CloudWatch log group for monitoring Docker containers."
  value       = aws_cloudwatch_log_group.monitoring_containers.name
}

output "monitoring_system_log_group_name" {
  description = "Pre-created encrypted 14-day CloudWatch log group for selected monitoring-host system logs."
  value       = aws_cloudwatch_log_group.monitoring_system.name
}

output "cloudtrail_archive_trail_arn" {
  description = "Dedicated lab trail ARN; null until the archive is explicitly enabled and applied."
  value       = module.cloudtrail_archive.trail_arn
}

output "cloudtrail_archive_bucket_name" {
  description = "Dedicated lab archive bucket; null until the archive is explicitly enabled and applied."
  value       = module.cloudtrail_archive.bucket_name
}

output "cloudtrail_archive_kms_key_arn" {
  description = "Dedicated lab archive KMS key; null until the archive is explicitly enabled and applied."
  value       = module.cloudtrail_archive.kms_key_arn
}

output "guardduty_detector_id" {
  description = "New lab GuardDuty detector ID; null until explicitly enabled and applied."
  value       = module.guardduty_detector.detector_id
}

output "guardduty_detector_arn" {
  description = "New lab GuardDuty detector ARN; null until explicitly enabled and applied."
  value       = module.guardduty_detector.detector_arn
}

output "jaeger_otlp_bind_address" {
  description = "New lab Jaeger OTLP bind address; null until explicitly enabled and applied."
  value       = module.monitoring_host.jaeger_otlp_bind_address
}
