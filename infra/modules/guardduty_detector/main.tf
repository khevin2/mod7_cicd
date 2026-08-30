resource "aws_guardduty_detector" "lab" {
  count = var.enabled ? 1 : 0

  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
  tags                         = merge(var.tags, { Role = "guardduty-detector" })

}

# AWS enables these protection plans by default when a detector is created
# without an explicit feature configuration. Keep the lab at the foundational
# GuardDuty baseline unless the owner separately approves a feature and cost.
resource "aws_guardduty_detector_feature" "optional_protection_disabled" {
  for_each = var.enabled ? toset([
    "S3_DATA_EVENTS",
    "EKS_AUDIT_LOGS",
    "EBS_MALWARE_PROTECTION",
    "RDS_LOGIN_EVENTS",
    "LAMBDA_NETWORK_LOGS",
  ]) : toset([])

  detector_id = aws_guardduty_detector.lab[0].id
  name        = each.value
  status      = "DISABLED"
}
