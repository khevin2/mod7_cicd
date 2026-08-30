# CloudTrail encrypted archive

Phase 6 defines a dedicated, opt-in lab trail in the shared `infra/live` Terraform
root. It is disabled by default; no existing trail, bucket, KMS key, or
account-wide service is imported, modified, or destroyed. Refresh discovery and
review the exact saved plan before enabling it.

## Defined controls

When explicitly enabled, the `cloudtrail_archive` module creates a tagged
customer-managed KMS key and a new dedicated S3 bucket. The bucket enforces
bucket-owner object ownership, blocks all public access, enables versioning,
denies insecure transport, and cannot be force-destroyed by Terraform. Its policy
allows only CloudTrail to read the bucket ACL and write this account's log and
digest objects under `cloudtrail/`, constrained with the trail source ARN and
source account.

The trail records multi-Region, global management read and write events, encrypts
with the dedicated KMS key, and enables log-file validation. Archive objects move
to Standard-IA after 30 days, Glacier after 90 days, and expire after 365 days.
Noncurrent versions follow the same transition/expiry schedule; incomplete
multipart uploads are removed after seven days.

## Discovery and approved creation

Perform this read-only discovery immediately before any plan. Do not record the
account ID in reviewer evidence.

```bash
aws cloudtrail describe-trails --include-shadow-trails
aws s3api list-buckets
aws kms list-aliases
aws cloudtrail get-trail-status --name <EXISTING_TRAIL_ARN_OR_NAME>
```

If a suitable, owned lab trail does not already exist, choose a new globally
unique bucket name and set only these ignored local inputs:

```hcl
enable_cloudtrail_archive      = true
cloudtrail_archive_bucket_name = "<APPROVED-UNIQUE-LAB-BUCKET>"
```

Then create, inspect, and seek approval for an exact saved plan. Applying it is a
separate, explicit authorization.

```bash
cd infra/live
terraform init -reconfigure -backend-config=backend.hcl
terraform validate
terraform plan -out=cloudtrail-archive.tfplan
terraform show -no-color cloudtrail-archive.tfplan
# Apply only after the exact plan is approved:
# terraform apply cloudtrail-archive.tfplan
```

## Post-apply verification

Use the trail ARN and bucket name from Terraform outputs locally. Sanitize IDs,
ARNs, account numbers, and endpoint data before saving evidence.

```bash
aws cloudtrail get-trail-status --name <TRAIL_ARN>
aws cloudtrail get-trail --name <TRAIL_ARN>
aws s3api get-public-access-block --bucket <ARCHIVE_BUCKET>
aws s3api get-bucket-encryption --bucket <ARCHIVE_BUCKET>
aws s3api get-bucket-versioning --bucket <ARCHIVE_BUCKET>
aws s3api get-bucket-policy --bucket <ARCHIVE_BUCKET>
aws s3api get-bucket-lifecycle-configuration --bucket <ARCHIVE_BUCKET>
aws kms describe-key --key-id <ARCHIVE_KMS_KEY_ARN>
```

Generate a harmless, authorized management API call after the trail is active,
then wait for normal CloudTrail delivery and verify that both a fresh log object
and its digest are present under `cloudtrail/AWSLogs/`. Record delivery status,
validation, encryption, public-access block, policy, and lifecycle in sanitized
Phase 6 evidence. Do not use a production or pre-existing shared trail as a
teardown target.
