resource "aws_secretsmanager_secret" "slack_webhook" {
  name                    = format("%s-%s-grafana-slack-webhook", var.project_name, var.environment)
  description             = "Runtime-only Grafana Slack incoming webhook for Project 6 alerts."
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 7

  tags = merge(var.tags, { Role = "grafana-alerting" })
}

resource "aws_secretsmanager_secret" "cloudflare_dns_token" {
  name                    = format("%s-%s-cloudflare-dns-token", var.project_name, var.environment)
  description             = "Runtime-only Cloudflare DNS token scoped to kheven.me certificate challenges."
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 7

  tags = merge(var.tags, { Role = "grafana-tls" })
}

data "aws_iam_policy_document" "runtime_read" {
  statement {
    sid     = "ReadOnlyNamedMonitoringSecrets"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.slack_webhook.arn,
      aws_secretsmanager_secret.cloudflare_dns_token.arn,
    ]
  }

  statement {
    sid       = "DecryptOnlyMonitoringSecretsKey"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = [format("secretsmanager.%s.amazonaws.com", var.aws_region)]
    }
  }
}
