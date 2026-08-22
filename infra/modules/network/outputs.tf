output "public_subnet_id" {
  description = "ID of the subnet assigned to the deployment host."
  value       = aws_subnet.public.id
}

output "deployment_security_group_id" {
  description = "ID of the security group assigned to the deployment host."
  value       = aws_security_group.deployment.id
}
