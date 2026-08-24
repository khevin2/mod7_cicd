output "instance_id" {
  description = "Deployment host instance ID."
  value       = aws_instance.deployment.id
}

output "public_dns" {
  description = "Deployment host public DNS name."
  value       = aws_instance.deployment.public_dns
}

output "private_ip" {
  description = "Deployment host private IP address."
  value       = aws_instance.deployment.private_ip
}

output "public_ip" {
  description = "Deployment host public IP address."
  value       = try(aws_eip.this[0].public_ip, aws_instance.deployment.public_ip)
}

output "elastic_ip" {
  description = "Optional allocated Elastic IP address."
  value       = try(aws_eip.this[0].public_ip, null)
}
