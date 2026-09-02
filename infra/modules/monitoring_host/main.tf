data "aws_ssm_parameter" "amazon_linux_2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_key_pair" "monitoring" {
  count = var.enable_ssh ? 1 : 0

  key_name   = format("%s-%s-monitoring", var.project_name, var.environment)
  public_key = var.ssh_public_key
  tags       = var.tags
}

resource "aws_instance" "this" {
  ami                    = data.aws_ssm_parameter.amazon_linux_2023.value
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = var.instance_profile_name
  key_name               = try(aws_key_pair.monitoring[0].key_name, null)

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

  lifecycle {
    # The public SSM parameter rolls forward as Amazon publishes AL2023 AMIs.
    # Prometheus and Grafana data live on this host, so AMI upgrades are an
    # explicit rebuild operation rather than an incidental Terraform apply.
    ignore_changes = [ami]

    precondition {
      condition     = !var.enable_ssh || var.ssh_public_key != null
      error_message = "ssh_public_key must be set when enable_ssh is true."
    }
  }

  tags = merge(var.tags, { Name = format("%s-%s-monitoring-host", var.project_name, var.environment) })
}

resource "aws_eip" "this" {
  domain   = "vpc"
  instance = aws_instance.this.id
  tags     = merge(var.tags, { Name = format("%s-%s-monitoring-eip", var.project_name, var.environment) })
}
