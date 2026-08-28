output "vpc_id" {
  value       = aws_vpc.this.id
  description = "Dedicated monitoring VPC ID."
}

output "vpc_cidr" {
  value       = aws_vpc.this.cidr_block
  description = "Dedicated monitoring VPC CIDR."
}

output "public_subnet_id" {
  value       = aws_subnet.public.id
  description = "Monitoring host subnet ID."
}

output "public_route_table_id" {
  value       = aws_route_table.public.id
  description = "Route table that later receives the application-VPC peering route."
}

output "security_group_id" {
  value       = aws_security_group.monitoring.id
  description = "Monitoring host security group ID."
}
