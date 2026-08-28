output "public_subnet_id" {
  description = "ID of the subnet assigned to the deployment host."
  value       = aws_subnet.public.id
}

output "deployment_security_group_id" {
  description = "ID of the security group assigned to the deployment host."
  value       = aws_security_group.deployment.id
}

output "jenkins_security_group_id" {
  description = "ID of the security group assigned to the Jenkins controller."
  value       = aws_security_group.jenkins.id
}

output "vpc_id" {
  description = "Application and Jenkins VPC ID."
  value       = aws_vpc.this.id
}

output "public_route_table_id" {
  description = "Application route table ID for the separately managed monitoring peering route."
  value       = aws_route_table.public.id
}
