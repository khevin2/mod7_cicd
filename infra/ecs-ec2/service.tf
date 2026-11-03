resource "aws_lb" "app" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]
}

resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.app.id
  health_check {
    enabled             = true
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

locals {
  task_definition = var.release_image == null ? null : jsondecode(templatefile("${path.module}/../../ecs/task-definition.json.tftpl", {
    family             = "${var.project_name}-app"
    image              = var.release_image
    execution_role_arn = aws_iam_role.execution.arn
    log_group          = aws_cloudwatch_log_group.app.name
    region             = var.aws_region
  }))
}

resource "aws_ecs_task_definition" "bootstrap" {
  count                    = var.release_image == null ? 0 : 1
  family                   = local.task_definition.family
  network_mode             = local.task_definition.networkMode
  requires_compatibilities = local.task_definition.requiresCompatibilities
  execution_role_arn       = local.task_definition.executionRoleArn
  container_definitions    = jsonencode(local.task_definition.containerDefinitions)
  # Preserve revisions when Terraform replaces this resource; clean them up
  # only after verifying that neither the service nor rollback needs them.
  skip_destroy = true

  lifecycle {
    precondition {
      condition     = startswith(var.release_image, "${aws_ecr_repository.app.repository_url}@sha256:")
      error_message = "The initial release must use a digest in this stack's ECR repository."
    }
  }
}

resource "aws_ecs_service" "app" {
  count                              = var.release_image == null ? 0 : 1
  name                               = "${var.project_name}-service"
  cluster                            = aws_ecs_cluster.app.id
  task_definition                    = aws_ecs_task_definition.bootstrap[0].arn
  desired_count                      = 1
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 60
  wait_for_steady_state              = true

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
  }
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = [for subnet in aws_subnet.public : subnet.id]
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = 3000
  }

  # Terraform creates the initial service; the release pipeline owns subsequent
  # revisions. Keep release_image configured when applying infrastructure again.
  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [aws_lb_listener.http, aws_ecs_cluster_capacity_providers.app, aws_iam_role_policy_attachment.execution, aws_vpc_security_group_ingress_rule.task_from_alb, aws_vpc_security_group_egress_rule.alb_to_task]
}
