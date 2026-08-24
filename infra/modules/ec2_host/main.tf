locals {
  key_pair_name = coalesce(var.key_pair_name, format("%s-%s-ec2", var.project_name, var.environment))
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "deployment" {
  key_name   = local.key_pair_name
  public_key = var.ssh_public_key
  tags       = var.tags
}

resource "aws_instance" "deployment" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  key_name                    = aws_key_pair.deployment.key_name
  associate_public_ip_address = true

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = var.root_volume_size_gib
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(var.tags, { Name = format("%s-%s-%s", var.project_name, var.environment, var.host_name) })
}

resource "aws_eip" "this" {
  count = var.allocate_elastic_ip ? 1 : 0

  domain   = "vpc"
  instance = aws_instance.deployment.id
  tags     = merge(var.tags, { Name = format("%s-%s-%s-eip", var.project_name, var.environment, var.host_name) })
}
