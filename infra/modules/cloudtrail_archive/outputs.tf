output "trail_arn" {
  description = "Dedicated lab CloudTrail ARN, null until the archive is explicitly enabled."
  value       = try(aws_cloudtrail.lab[0].arn, null)
}

output "bucket_name" {
  description = "Dedicated archive bucket name, null until explicitly enabled."
  value       = try(aws_s3_bucket.archive[0].id, null)
}

output "kms_key_arn" {
  description = "CloudTrail archive KMS key ARN, null until explicitly enabled."
  value       = try(aws_kms_key.archive[0].arn, null)
}
