output "detector_id" {
  description = "New lab GuardDuty detector ID, null until explicitly enabled."
  value       = try(aws_guardduty_detector.lab[0].id, null)
}

output "detector_arn" {
  description = "New lab GuardDuty detector ARN, null until explicitly enabled."
  value       = try(aws_guardduty_detector.lab[0].arn, null)
}
