output "instance_id" {
  description = "Deployment host instance ID."
  value       = aws_instance.deployment.id
}

output "public_dns" {
  description = "Deployment host public DNS name."
  value       = aws_instance.deployment.public_dns
}

output "public_ip" {
  description = "Deployment host public IP address."
  value       = aws_instance.deployment.public_ip
}
