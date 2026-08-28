resource "aws_vpc_peering_connection" "this" {
  vpc_id      = var.application_vpc_id
  peer_vpc_id = var.monitoring_vpc_id
  auto_accept = true

  lifecycle {
    precondition {
      condition     = var.application_vpc_cidr != var.monitoring_vpc_cidr
      error_message = "Application and monitoring VPC CIDRs must not overlap."
    }
  }

  tags = merge(var.tags, { Name = format("%s-%s-app-monitoring-peering", var.tags["Project"], var.tags["Environment"]) })
}

resource "aws_vpc_peering_connection_options" "this" {
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id

  requester {
    allow_remote_vpc_dns_resolution = var.enable_cross_vpc_private_dns
  }

  accepter {
    allow_remote_vpc_dns_resolution = var.enable_cross_vpc_private_dns
  }
}

resource "aws_route" "application_to_monitoring" {
  route_table_id            = var.application_route_table_id
  destination_cidr_block    = var.monitoring_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}

resource "aws_route" "monitoring_to_application" {
  route_table_id            = var.monitoring_route_table_id
  destination_cidr_block    = var.application_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}

resource "aws_vpc_security_group_ingress_rule" "application_metrics" {
  security_group_id = var.application_security_group_id
  description       = "Private application metrics from the dedicated monitoring VPC"
  cidr_ipv4         = var.monitoring_vpc_cidr
  from_port         = 9464
  to_port           = 9464
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "application_node_exporter" {
  security_group_id = var.application_security_group_id
  description       = "Private application Node Exporter scrape from the dedicated monitoring VPC"
  cidr_ipv4         = var.monitoring_vpc_cidr
  from_port         = 9100
  to_port           = 9100
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "monitoring_metrics" {
  security_group_id = var.monitoring_security_group_id
  description       = "Prometheus application metrics over approved VPC peering"
  cidr_ipv4         = var.application_vpc_cidr
  from_port         = 9464
  to_port           = 9464
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "monitoring_node_exporter" {
  security_group_id = var.monitoring_security_group_id
  description       = "Prometheus application Node Exporter over approved VPC peering"
  cidr_ipv4         = var.application_vpc_cidr
  from_port         = 9100
  to_port           = 9100
  ip_protocol       = "tcp"
}
