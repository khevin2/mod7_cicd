# Project 6 resource ownership

Evidence date: 2026-08-27. This classification is based on executed read-only
discovery in `eu-north-1`; identifiers and addresses are intentionally omitted.

| Resource/category | Observed baseline | Classification | Allowed later action |
| --- | --- | --- | --- |
| Default VPC and three default subnets | Available, untagged | Pre-existing | Reference only if explicitly approved; never lab teardown |
| Two legacy security groups | Untagged and attached to no network interface | Pre-existing, currently unused | Do not import, change, or delete |
| Application/Jenkins VPC `10.70.0.0/16` | Absent | Approved target, lab-created | Create only from reviewed saved plan; eligible for owned teardown |
| Monitoring VPC `10.80.0.0/16` | Absent | Approved target, lab-created | Create only from reviewed saved plan; eligible for owned teardown |
| Application/Jenkins/monitoring EC2 and EBS | No active instances, EIPs, or volumes | Approved target, lab-created | Create only from reviewed saved plans; tag and record state ownership |
| VPC peering and routes | No active peering | Approved target, lab-created | Create after both VPCs exist and a separate saved plan is approved |
| Possible state S3 bucket | Untagged, no versioning, one state-like object outside the expected Project 6 prefix | Pre-existing/unowned | Do not reference, import, read as Project 6 state, empty, or delete without ownership proof |
| Project 6 Terraform backend | No live config/state found | Approved target, lab-created | Create a new uniquely named tagged backend after saved-plan approval |
| `CloudWatchAgent` IAM role/profile | Untagged and broadly permissioned | Pre-existing/rejected for reuse | Do not attach, change, or delete; create a scoped lab role later |
| Two existing CloudWatch log groups | Unrelated; no explicit retention or customer KMS key | Pre-existing | Do not change or delete |
| Project 6 log groups | Absent | Approved target, lab-created | Create tagged, encrypted, 14-day groups from reviewed plan |
| AWS Control Tower CloudTrail | Multi-Region, account-governed, inaccessible status | Pre-existing/referenced | Do not mutate or delete; it is not Project 6 runtime evidence |
| Project 6 trail/archive | Absent | Proposed lab-created resource | Create only if duplicate-event cost and exact plan are approved |
| Customer-managed KMS keys | No customer alias in `eu-north-1` | Approved target, lab-created | Create only the scoped key(s) required by approved plan |
| GuardDuty detector | Tagged detector enabled in `eu-north-1` on 2026-08-28; optional protection plans disabled | Lab-created/Terraform-managed | Retain for the lab; eligible for teardown only in a separately approved exact destroy plan |
| GitHub push webhook | Active; latest delivery failed | Pre-existing/referenced | Preserve; do not mutate until Jenkins endpoint is restored |
| Cloudflare record and Slack webhook | Not queried; values remain outside AWS/Terraform | User-managed external resources | User owns DNS record; inject Slack secret out of band |

## Cleanup rule

Only resources bearing the agreed `Project`, `Environment=lab`, `Owner=Kheven`,
and `ManagedBy=Terraform` tags *and* represented in the approved Project 6 state
may enter a later destroy plan. A tag alone is not sufficient ownership proof.
The default VPC, legacy groups, possible old state bucket, broad IAM role,
unrelated log groups, and Control Tower trail are explicitly excluded.
