output "state_bucket_name" {
  description = "Use this non-secret value in infra/live/backend.hcl."
  value       = module.state_backend.bucket_name
}

output "state_bucket_region" {
  description = "Region for the generated S3 backend configuration."
  value       = var.aws_region
}

output "state_locking_mode" {
  description = "The S3 backend setting required for native state locking."
  value       = "use_lockfile = true"
}
