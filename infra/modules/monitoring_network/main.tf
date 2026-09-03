resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, { Name = format("%s-%s-monitoring-vpc", var.tags["Project"], var.tags["Environment"]) })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = format("%s-%s-monitoring-igw", var.tags["Project"], var.tags["Environment"]) })
}

# The monitoring host has an Elastic IP for the manually managed DNS-only A
# record. It has no public metrics or exporter listener.
#trivy:ignore:AVD-AWS-0164:exp:2027-08-28
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = merge(var.tags, { Name = format("%s-%s-monitoring-public", var.tags["Project"], var.tags["Environment"]) })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  dynamic "route" {
    for_each = var.application_vpc_cidr == null || var.app_monitoring_peering_connection_id == null ? [] : [var.application_vpc_cidr]
    content {
      cidr_block                = route.value
      vpc_peering_connection_id = var.app_monitoring_peering_connection_id
    }
  }

  tags = merge(var.tags, { Name = format("%s-%s-monitoring-public", var.tags["Project"], var.tags["Environment"]) })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Internet egress is limited by protocol. Package repositories, image
# registries, AWS APIs, public DNS, and NTP do not publish stable CIDRs.
#trivy:ignore:AVD-AWS-0104:exp:2027-08-28
resource "aws_security_group" "monitoring" {
  name_prefix = format("%s-%s-monitoring-", var.tags["Project"], var.tags["Environment"])
  description = "Grafana administration and required monitoring-host egress."
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Grafana HTTPS from the approved administrator address"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.grafana_admin_cidr]
  }

  dynamic "ingress" {
    for_each = var.enable_ssh ? toset([var.grafana_admin_cidr]) : toset([])
    content {
      description = "Emergency SSH from the approved administrator address"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  dynamic "ingress" {
    for_each = var.application_vpc_cidr == null ? [] : [var.application_vpc_cidr]
    content {
      description = "Private OTLP/HTTP trace ingestion from the application VPC"
      from_port   = 4318
      to_port     = 4318
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    description = "HTTPS for AWS APIs, package repositories, registries, and certificate services"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "egress" {
    for_each = var.application_vpc_cidr == null ? [] : [
      { port = 9464, description = "Prometheus application metrics over approved VPC peering" },
      { port = 9100, description = "Prometheus application Node Exporter over approved VPC peering" },
    ]
    content {
      description = egress.value.description
      from_port   = egress.value.port
      to_port     = egress.value.port
      protocol    = "tcp"
      cidr_blocks = [var.application_vpc_cidr]
    }
  }

  egress {
    description = "HTTP for approved package repositories and certificate redirects"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS resolution"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS resolution over TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Network time synchronization"
    from_port   = 123
    to_port     = 123
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = format("%s-%s-monitoring", var.tags["Project"], var.tags["Environment"]) })
}
