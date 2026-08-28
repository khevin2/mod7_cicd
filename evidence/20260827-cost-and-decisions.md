# Project 6 cost and decisions

Evidence date: 2026-08-27. Region: `eu-north-1` (EU Stockholm). Prices are
pre-tax USD point-in-time inputs, not a billing quote. Usage-priced services must
be estimated again with the AWS Pricing Calculator before apply.

## Approved inputs

| Decision | Approved result |
| --- | --- |
| Source | GitHub `main` and local HEAD at `9662bf8835d19eed4e7f39ecc0a9b212c39db5c2` |
| Tags | `Project=jenkins-webapp`, `Environment=lab`, `Owner=Kheven`, `ManagedBy=Terraform` |
| Application/Jenkins network | Recreate `10.70.0.0/16` from a separately reviewed saved plan |
| Monitoring network | Dedicated `10.80.0.0/16`, public subnet `10.80.1.0/24` |
| Connectivity | Private intra-Region VPC peering; prefer the same AZ to avoid cross-AZ transfer charges |
| Monitoring host | One `t3.micro`; measure CPU, memory, and disk before any resize |
| Grafana | `grafana.kheven.me`, Cloudflare DNS-only, HTTPS restricted to a required changing public `/32` |
| Alerts | Slack incoming webhook to `#project6-observability-alerts`, stored outside Git/Terraform state |
| Retention | CloudWatch 14 days; CloudTrail S3 Standard-IA day 30, Glacier day 90, expire day 365 |
| Existing Control Tower trail | Reference only; never modify or destroy |
| GuardDuty | No detector exists in `eu-north-1`; any detector is a new cost-bearing lab resource |
| Backend | Do not reuse the unowned bucket candidate; plan a new tagged protected backend |

The Grafana administrator CIDR will become a required, validated input in the
monitoring Terraform root when that root creates the Grafana security-group
rule. It does not belong in the current application/Jenkins root before it is
used. Its real value must remain in an ignored `terraform.tfvars` file.

## Fixed baseline estimate

The AWS Pricing API returned these Stockholm rates on the evidence date:

- Linux on-demand `t3.micro`: **$0.0108/hour**.
- General Purpose SSD `gp3`: **$0.0836/GB-month**.
- Public IPv4: **$0.005/hour per address** according to AWS public IPv4 pricing.

At 730 hours/month, the planned three `t3.micro` hosts, three 20 GiB gp3 root
volumes, and three public IPv4 addresses produce this approximate floor:

| Component | Formula | Approx. monthly USD |
| --- | --- | ---: |
| EC2 compute | 3 x 730 x $0.0108 | $23.65 |
| gp3 root storage | 60 GiB x $0.0836 | $5.02 |
| Public IPv4 | 3 x 730 x $0.005 | $10.95 |
| **Fixed subtotal** | Before free-tier/credits/tax | **$39.62** |

Stopping an instance stops compute charges but retains EBS and public IPv4/EIP
charges while those resources remain allocated. The monitoring Elastic IP is
needed for the manually managed DNS record. Reassess whether the application and
Jenkins hosts both need public IPv4 before Phase 4; private deployment traffic
already uses the application private address.

## Variable and service costs

- CloudWatch Logs charges depend on ingestion, retained bytes, and Logs Insights
  scans. A 14-day retention limit bounds storage but not ingestion/query cost.
- The first copy of ongoing CloudTrail management events to S3 is free, but S3
  storage/requests apply. The Control Tower trail already records management
  events, so a second lab trail may incur duplicate delivery charges; review this
  explicitly before creating it.
- A customer-managed KMS key costs $1/month, prorated hourly, plus request usage
  after the applicable free tier. Rotation can add key-storage cost.
- GuardDuty is usage-based. A first enablement usually starts a 30-day trial for
  supported protection plans, after which analyzed-event/data volume is billed.
  Do not enable extra protection plans by default.
- VPC peering has no hourly connection charge. Same-AZ transfer is free;
  cross-AZ peering transfer is charged in both directions.
- S3 archive cost depends on stored volume, requests, lifecycle transitions,
  minimum storage duration, and retrieval. CloudWatch/S3 internet data transfer
  and DNS/certificate/external-service costs are additional if applicable.

## Official price sources

- EC2/VPC public IPv4: https://aws.amazon.com/vpc/pricing/
- Amazon EBS: https://aws.amazon.com/ebs/pricing/
- VPC peering: https://docs.aws.amazon.com/vpc/latest/peering/what-is-vpc-peering.html
- CloudWatch: https://aws.amazon.com/cloudwatch/pricing/
- CloudTrail: https://aws.amazon.com/cloudtrail/pricing/
- Amazon S3: https://aws.amazon.com/s3/pricing/
- AWS KMS: https://aws.amazon.com/kms/pricing/
- GuardDuty: https://aws.amazon.com/guardduty/pricing/

## Approval gate

This preflight authorizes no cloud mutation. Before any apply, refresh prices, prepare a
saved Terraform plan, map every address to this ownership table, show exact
create/change/destroy counts, and obtain approval for that exact plan.
