#!/usr/bin/env bash
set -Eeuo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
terraform_root="$repository_root/infra"

command -v rg >/dev/null
terraform fmt -check -recursive "$terraform_root"

if rg -n --glob '*.tf' 'aws_secretsmanager_secret_version|secret_string\s*=|user_data\s*=' \
  "$terraform_root/live" "$terraform_root/modules/monitoring_"*; then
  echo "Monitoring infrastructure must not manage secret values or user-data secrets." >&2
  exit 1
fi

if rg -n --glob '*.tf' 'provider[[:space:]]+"cloudflare"' "$terraform_root"; then
  echo "The permanent DNS record is user-managed; a Cloudflare Terraform provider is not allowed." >&2
  exit 1
fi

if rg -n 'from_port[[:space:]]*=[[:space:]]*(9464|9100)|to_port[[:space:]]*=[[:space:]]*(9464|9100)' \
  "$terraform_root/modules/monitoring_network"; then
  echo "Monitoring metrics and Node Exporter must not be exposed by the public monitoring security group." >&2
  exit 1
fi

for expected_rule in \
  'Private application metrics from the dedicated monitoring VPC' \
  'Private application Node Exporter scrape from the dedicated monitoring VPC' \
  'Prometheus application metrics over approved VPC peering' \
  'Prometheus application Node Exporter over approved VPC peering'; do
  rg -Fq "$expected_rule" "$terraform_root/modules/network/main.tf" "$terraform_root/modules/monitoring_network/main.tf"
done

printf '%s\n' \
  "Terraform formatting: valid" \
  "Monitoring secret values and user data: absent" \
  "Cloudflare Terraform provider: absent" \
  "Public monitoring security-group metrics/exporter rules: absent" \
  "Peering routes and security-group rules: owned with their parent route tables and groups"
