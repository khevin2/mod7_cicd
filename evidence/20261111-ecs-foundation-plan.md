# ECS foundation plan prepared locally

Prepared on 2026-11-11 using AWS profile `training`, verified account `447558491229`, region `eu-north-1`. No cloud mutation was executed by the assistant.

- Saved ignored plan: `infra/ecs-ec2/foundation.tfplan`.
- Actions: 36 resources to create; zero managed updates or deletions.
- Includes isolated VPC `10.90.0.0/16`, two subnets, restricted security groups, public demo ALB, ECR `mod9-ecs`, ECS cluster `mod9-ecs-cluster`, empty ASG/capacity provider, IAM host/execution roles, log group, dashboard and four alarms.
- Existing account VPC CIDR `10.80.0.0/16` does not overlap the new VPC.
- ASG desired/minimum capacity 0, maximum 2. The plan creates no EC2 instance, ECS task definition or ECS service because `release_image=null`.
- Selected launch template AMI: `ami-012738a21351b1b62`, resolved from the configured AWS ECS-optimized AMI parameter. This saved plan captures that selection; the current source parameter lookup remains a moving input on future plans.
- Ignored local inputs use owner `kheven`, administrator IPv4 `/32`, and the CI host's public IPv4 `/32` for subsequent deployment health verification. Revisit the allowed CIDRs if either address changes.
- The planned ALB drops invalid header fields. Demo HTTP and public-registry egress use the documented resource-local policy exceptions.

The operator must inspect and apply the exact saved plan. AWS foundation existence, image-pull connectivity and ECS registration are not yet verified. An empty ASG is expected until the later service requests capacity. The plan includes an ALB and other billable resources despite starting with no application hosts.
