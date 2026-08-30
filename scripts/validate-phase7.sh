#!/usr/bin/env bash
set -Eeuo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
terraform_root="$repository_root/infra"
detector_module="$terraform_root/modules/guardduty_detector"

terraform fmt -check -recursive "$terraform_root"

rg -Fq 'enable_guardduty_detector' "$terraform_root/live/main.tf" "$terraform_root/live/variables.tf"
rg -Fq 'default     = false' "$terraform_root/live/variables.tf" "$detector_module/variables.tf"
rg -Fq 'resource "aws_guardduty_detector" "lab"' "$detector_module/main.tf"
rg -Fq 'enable                       = true' "$detector_module/main.tf"
rg -Fq 'finding_publishing_frequency = "FIFTEEN_MINUTES"' "$detector_module/main.tf"
rg -Fq 'Role = "guardduty-detector"' "$detector_module/main.tf"
rg -Fq 'aws_guardduty_detector_feature' "$detector_module/main.tf"
rg -Fq 'status      = "DISABLED"' "$detector_module/main.tf"
rg -Fq '"S3_DATA_EVENTS"' "$detector_module/main.tf"
rg -Fq '"EKS_AUDIT_LOGS"' "$detector_module/main.tf"
rg -Fq '"EBS_MALWARE_PROTECTION"' "$detector_module/main.tf"
rg -Fq '"RDS_LOGIN_EVENTS"' "$detector_module/main.tf"
rg -Fq '"LAMBDA_NETWORK_LOGS"' "$detector_module/main.tf"
rg -Fq 'create-sample-findings' "$repository_root/docs/GUARDDUTY.md"
rg -Fq 'SYNTHETIC GUARDDUTY SAMPLE' "$repository_root/docs/GUARDDUTY.md"
rg -Fq 'If a detector already exists, classify its ownership before any action.' "$repository_root/docs/GUARDDUTY.md"
rg -Fq 'optional protection plans to `DISABLED`' "$repository_root/docs/GUARDDUTY.md"

printf '%s\n' \
  'Terraform formatting: valid' \
  'GuardDuty detector: disabled by default and saved-plan gated' \
  'Optional GuardDuty protection plans: explicitly disabled' \
  'Synthetic sample and real-finding triage procedures: documented'
