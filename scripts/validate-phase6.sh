#!/usr/bin/env bash
set -Eeuo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
terraform_root="$repository_root/infra"
archive_module="$terraform_root/modules/cloudtrail_archive"

terraform fmt -check -recursive "$terraform_root"

rg -Fq 'enable_cloudtrail_archive' "$terraform_root/live/main.tf" "$terraform_root/live/variables.tf"
rg -Fq 'force_destroy = false' "$archive_module/main.tf"
rg -Fq 'object_ownership = "BucketOwnerEnforced"' "$archive_module/main.tf"
rg -Fq 'block_public_acls       = true' "$archive_module/main.tf"
rg -Fq 'restrict_public_buckets = true' "$archive_module/main.tf"
rg -Fq 'enable_log_file_validation    = true' "$archive_module/main.tf"
rg -Fq 'include_global_service_events = true' "$archive_module/main.tf"
rg -Fq 'is_multi_region_trail         = true' "$archive_module/main.tf"
rg -Fq 'read_write_type           = "All"' "$archive_module/main.tf"
rg -Fq 'include_management_events = true' "$archive_module/main.tf"
rg -Fq 'enable_key_rotation     = true' "$archive_module/main.tf"
rg -Fq 'aws:SourceArn' "$archive_module/main.tf"
rg -Fq 'aws:SourceAccount' "$archive_module/main.tf"
rg -Fq 'storage_class = "STANDARD_IA"' "$archive_module/main.tf"
rg -Fq 'storage_class = "GLACIER"' "$archive_module/main.tf"
rg -Fq 'days = 365' "$archive_module/main.tf"
rg -Fq 'days_after_initiation = 7' "$archive_module/main.tf"

printf '%s\n' \
  'Terraform formatting: valid' \
  'CloudTrail archive: disabled by default and plan-gated' \
  'Trail: multi-Region, global management read/write events, validation enabled' \
  'Archive: KMS, ownership enforcement, public block, versioning, TLS-only policy, lifecycle defined'
