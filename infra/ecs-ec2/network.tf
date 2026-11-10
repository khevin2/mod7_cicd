data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "app" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "app" {
  vpc_id = aws_vpc.app.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.app.id
  cidr_block        = var.subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  # Public addressing is explicitly selected only by the host launch template.
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.project_name}-public-${count.index + 1}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.app.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb-"
  description = "Lab HTTP ingress from explicitly allowed clients"
  vpc_id      = aws_vpc.app.id

}

resource "aws_security_group" "host" {
  name_prefix = "${var.project_name}-host-"
  description = "ECS host with HTTPS egress and no inbound management ports"
  vpc_id      = aws_vpc.app.id

}

resource "aws_security_group" "task" {
  name_prefix = "${var.project_name}-task-"
  description = "App receives traffic only from the ALB"
  vpc_id      = aws_vpc.app.id
  # No task-originated egress is required by this application.
}

resource "aws_vpc_security_group_egress_rule" "alb_to_task" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.task.id
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
  description                  = "Application tasks"
}

resource "aws_vpc_security_group_ingress_rule" "task_from_alb" {
  security_group_id            = aws_security_group.task.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
  description                  = "HTTP from load balancer"
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_client" {
  for_each          = var.allowed_http_cidrs
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  description       = "HTTP from an approved client"
}

# Demo exception: ECS/ECR/CloudWatch and image registries use dynamic endpoints.
# Hosts have no inbound management rules; tasks have no outbound rules.
# HTTPS-only egress avoids the additional cost of NAT/proxy infrastructure.
#trivy:ignore:AVD-AWS-0104:exp:2026-12-10
resource "aws_vpc_security_group_egress_rule" "host_https" {
  security_group_id = aws_security_group.host.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "AWS APIs and image registries over HTTPS"
}
