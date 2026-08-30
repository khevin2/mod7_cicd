resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, { Name = format("%s-%s-vpc", var.tags["Project"], var.tags["Environment"]) })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = format("%s-%s-igw", var.tags["Project"], var.tags["Environment"]) })
}

# Direct public addressing is required for the lab's EC2 public endpoint.
# Review this exception if the deployment moves behind a load balancer.
#trivy:ignore:AVD-AWS-0164:exp:2027-08-22
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = merge(var.tags, { Name = format("%s-%s-public", var.tags["Project"], var.tags["Environment"]) })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  dynamic "route" {
    for_each = var.monitoring_vpc_cidr == null || var.app_monitoring_peering_connection_id == null ? [] : [var.monitoring_vpc_cidr]
    content {
      cidr_block                = route.value
      vpc_peering_connection_id = var.app_monitoring_peering_connection_id
    }
  }

  tags = merge(var.tags, { Name = format("%s-%s-public", var.tags["Project"], var.tags["Environment"]) })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

data "aws_region" "current" {}

data "aws_ec2_managed_prefix_list" "instance_connect" {
  count = var.enable_ec2_instance_connect ? 1 : 0
  name  = format("com.amazonaws.%s.ec2-instance-connect", data.aws_region.current.region)
}

# Egress is restricted by protocol and port, but public registries, package
# repositories, DNS, and NTP do not provide stable destination CIDRs.
# Review this exception if a controlled egress proxy or VPC endpoints are added.
#trivy:ignore:AVD-AWS-0104:exp:2027-08-22
resource "aws_security_group" "jenkins" {
  name_prefix = format("%s-%s-jenkins-", var.tags["Project"], var.tags["Environment"])
  description = "Restricted administrative access and controlled webhook ingress for Jenkins."
  vpc_id      = aws_vpc.this.id

  dynamic "ingress" {
    for_each = var.jenkins_admin_ingress_cidrs
    content {
      description = "SSH administration from approved administrator egress address"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  dynamic "ingress" {
    for_each = var.enable_ec2_instance_connect ? data.aws_ec2_managed_prefix_list.instance_connect : []
    content {
      description     = "Temporary SSH access from the regional EC2 Instance Connect service"
      from_port       = 22
      to_port         = 22
      protocol        = "tcp"
      prefix_list_ids = [ingress.value.id]
    }
  }

  dynamic "ingress" {
    for_each = var.jenkins_admin_ingress_cidrs
    content {
      description = "HTTPS Jenkins UI from approved administrator egress address"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  dynamic "ingress" {
    for_each = var.enable_jenkins_webhook_ingress ? toset(["0.0.0.0/0"]) : toset([])
    content {
      description = "Public HTTPS reaches only the Nginx-restricted GitHub webhook path"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  dynamic "ingress" {
    for_each = var.enable_jenkins_http_ingress ? toset(["0.0.0.0/0"]) : toset([])
    content {
      description = "Public HTTP for Lets Encrypt validation and HTTPS redirects"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    description = "SSH deployment traffic to private lab hosts"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "HTTPS for GitHub, registries, Jenkins plugins, and Trivy databases"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP for package repositories and certificate issuance"
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

  tags = merge(var.tags, { Name = format("%s-%s-jenkins", var.tags["Project"], var.tags["Environment"]) })
}

# Egress is restricted by protocol and port, but public registries, package
# repositories, DNS, and NTP do not provide stable destination CIDRs.
# Review this exception if a controlled egress proxy or VPC endpoints are added.
#trivy:ignore:AVD-AWS-0104:exp:2027-08-22
resource "aws_security_group" "deployment" {
  name_prefix = format("%s-%s-deployment-", var.tags["Project"], var.tags["Environment"])
  description = "Ingress restricted to approved SSH sources and public HTTP verification."
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "SSH deployment access from the Jenkins controller security group"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins.id]
  }

  dynamic "ingress" {
    for_each = var.monitoring_vpc_cidr == null ? [] : [
      { port = 9464, description = "Private application metrics from the dedicated monitoring VPC" },
      { port = 9100, description = "Private application Node Exporter scrape from the dedicated monitoring VPC" },
    ]
    content {
      description = ingress.value.description
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = [var.monitoring_vpc_cidr]
    }
  }

  dynamic "ingress" {
    for_each = var.enable_ec2_instance_connect ? data.aws_ec2_managed_prefix_list.instance_connect : []
    content {
      description     = "Temporary SSH access from the regional EC2 Instance Connect service"
      from_port       = 22
      to_port         = 22
      protocol        = "tcp"
      prefix_list_ids = [ingress.value.id]
    }
  }

  ingress {
    description = "Public HTTP application verification"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTPS for registry pulls and package repositories"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = format("%s-%s-deployment", var.tags["Project"], var.tags["Environment"]) })
}
