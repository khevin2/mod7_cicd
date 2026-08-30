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


# These resources were originally managed separately from the route tables and
# security groups that also used inline rules. That mixed ownership makes a
# refresh plan try to revoke the private monitoring paths. They are now owned
# inline with their parent resources. The removed blocks forget only Terraform
# state; they never destroy the already-applied remote routes/rules.
removed {
  from = aws_route.application_to_monitoring
  lifecycle { destroy = false }
}

removed {
  from = aws_route.monitoring_to_application
  lifecycle { destroy = false }
}

removed {
  from = aws_vpc_security_group_ingress_rule.application_metrics
  lifecycle { destroy = false }
}

removed {
  from = aws_vpc_security_group_ingress_rule.application_node_exporter
  lifecycle { destroy = false }
}

removed {
  from = aws_vpc_security_group_egress_rule.monitoring_metrics
  lifecycle { destroy = false }
}

removed {
  from = aws_vpc_security_group_egress_rule.monitoring_node_exporter
  lifecycle { destroy = false }
}
