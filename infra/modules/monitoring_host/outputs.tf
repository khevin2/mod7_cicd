output "instance_id" { value = aws_instance.this.id }
output "private_ip" { value = aws_instance.this.private_ip }
output "elastic_ip" { value = aws_eip.this.public_ip }
