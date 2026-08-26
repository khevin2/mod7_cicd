output "bucket_name" {
  description = "Name of the protected S3 state bucket."
  value       = aws_s3_bucket.state.id
}
