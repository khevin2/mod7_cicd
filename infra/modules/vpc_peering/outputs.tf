output "connection_id" { value = aws_vpc_peering_connection.this.id }
output "connection_status" { value = aws_vpc_peering_connection.this.accept_status }
