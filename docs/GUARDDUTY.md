# GuardDuty detector and synthetic sample procedure

Phase 7 keeps GuardDuty opt-in and regional. The Terraform configuration creates
one tagged lab detector only when `enable_guardduty_detector = true`; it is false
by default. AWS enables several optional protection plans by default during
detector creation, so the module immediately manages S3 data events, EKS audit
logs, EBS malware protection, RDS login events, and Lambda network logs as
`DISABLED`. Those plans can create separate cost and privacy obligations.

## Discover before a plan

Immediately before planning, inspect the configured Region without changing any
detector. Do not save account identifiers, finding IDs, resource IDs, IP
addresses, or endpoints in reviewer evidence.

```bash
aws guardduty list-detectors
aws guardduty get-detector --detector-id <DETECTOR_ID>
aws guardduty list-detector-features --detector-id <DETECTOR_ID>
aws guardduty get-usage-statistics --detector-id <DETECTOR_ID> \
  --usage-statistic-type SUM_BY_ACCOUNT --usage-criteria-data-sets ALL \
  --usage-statistic-time-range MONTH_TO_DATE
```

If a detector already exists, classify its ownership before any action. Do not
import, retag, change, disable, or destroy an unowned/shared detector. A suitable
owned detector may be used only for the sample-finding verification below. If no
detector exists, record that result, review costs and enabled features, and use
the dedicated lab module only after approval.

## Create a new lab detector

Set the ignored local input only after discovery and approval:

```hcl
enable_guardduty_detector = true
```

Create and inspect a saved plan. Applying is a separate explicit authorization.

```bash
cd infra/live
terraform init -reconfigure -backend-config=backend.hcl
terraform validate
terraform plan -out=guardduty-detector.tfplan
terraform show -no-color guardduty-detector.tfplan
# Apply only after approval of this exact plan:
# terraform apply guardduty-detector.tfplan
```

The approved plan must create the tagged detector and explicitly set the five
optional protection plans to `DISABLED`. It must not alter a pre-existing
detector or activate optional protections. After apply, verify the detector is
enabled and preserve only a sanitized summary of its status and features:

```bash
aws guardduty get-detector --detector-id <LAB_DETECTOR_ID>
aws guardduty list-detector-features --detector-id <LAB_DETECTOR_ID>
```

## Synthetic sample and authorized triage

With an enabled detector, create one AWS-supported sample. This is a synthetic
test finding, not evidence of a real incident. Generate it only in the approved
lab detector and label every capture `SYNTHETIC GUARDDUTY SAMPLE`.

```bash
aws guardduty create-sample-findings \
  --detector-id <LAB_DETECTOR_ID> \
  --finding-types Backdoor:EC2/DenialOfService.Tcp

aws guardduty list-findings --detector-id <LAB_DETECTOR_ID>
aws guardduty get-findings --detector-id <LAB_DETECTOR_ID> \
  --finding-ids <SAMPLE_FINDING_ID>
```

Sanitize the returned finding before recording only its status, type, severity,
title, and timestamp in `phase7-sample-finding.txt` or a screenshot. Redact the
detector and finding IDs, account IDs, IP addresses, instance/resource IDs,
hostnames, and any endpoint data.

For a real finding, do not treat the sample workflow as incident response:
preserve the finding, restrict access to the evidence, validate the affected
resource and CloudTrail context, notify the authorized owner/security contact,
and follow the organization’s approved containment process. Do not archive,
delete, suppress, or disable a real finding/detector as part of this lab.

## Teardown boundary

Only a detector created by the approved lab Terraform state and bearing the
agreed ownership tags may appear in a separately reviewed destroy plan. Existing
or shared detectors are never teardown targets.
