output "slack_webhook_secret_arn" {
  description = "ARN of the empty Slack webhook secret container. Set its value out of band."
  value       = aws_secretsmanager_secret.slack_webhook.arn
}

output "cloudflare_dns_token_secret_arn" {
  description = "ARN of the empty Cloudflare DNS token container. Set its value out of band."
  value       = aws_secretsmanager_secret.cloudflare_dns_token.arn
}

output "runtime_read_policy_json" {
  description = "Least-privilege policy JSON for the monitoring instance role."
  value       = data.aws_iam_policy_document.runtime_read.json
}
