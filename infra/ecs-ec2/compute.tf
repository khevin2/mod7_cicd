data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

resource "aws_ecs_cluster" "app" {
  name = "${var.project_name}-cluster"
}

resource "aws_launch_template" "ecs" {
  name_prefix   = "${var.project_name}-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs.name
  }

  network_interfaces {
    device_index                = 0
    associate_public_ip_address = true
    delete_on_termination       = true
    security_groups             = [aws_security_group.host.id]
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      encrypted             = true
      volume_size           = 30
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  user_data = base64encode(<<-EOT
    #!/bin/bash
    cat >> /etc/ecs/ecs.config <<'CONFIG'
    ECS_CLUSTER=${aws_ecs_cluster.app.name}
    ECS_AWSVPC_BLOCK_IMDS=true
    ECS_ENABLE_AWSLOGS_EXECUTIONROLE_OVERRIDE=true
    CONFIG
  EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project_name}-ecs-host" }
  }
}

resource "aws_autoscaling_group" "ecs" {
  name_prefix = "${var.project_name}-"
  # ECS must attach the capacity provider before any hosts register.
  min_size            = 0
  desired_capacity    = 0
  max_size            = 2
  vpc_zone_identifier = [for subnet in aws_subnet.public : subnet.id]
  health_check_type   = "EC2"

  launch_template {
    id      = aws_launch_template.ecs.id
    version = aws_launch_template.ecs.latest_version
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-ecs-host"
    propagate_at_launch = true
  }

  # The ECS capacity provider controls desired capacity after creation.
  lifecycle {
    ignore_changes = [desired_capacity]
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_instance,
    aws_iam_role_policy_attachment.instance_ssm,
    aws_route_table_association.public,
    aws_vpc_security_group_egress_rule.host_https,
  ]
}

resource "aws_ecs_capacity_provider" "ec2" {
  name = "${var.project_name}-ec2"
  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_draining               = "ENABLED"
    managed_termination_protection = "DISABLED"
    managed_scaling {
      status          = "ENABLED"
      target_capacity = 100
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "app" {
  cluster_name       = aws_ecs_cluster.app.name
  capacity_providers = [aws_ecs_capacity_provider.ec2.name]
  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
  }
}
