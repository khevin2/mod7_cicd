#!/usr/bin/env bash
set -Eeuo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
terraform_root="$repository_root/infra"

command -v rg >/dev/null
terraform fmt -check -recursive "$terraform_root"

for group in \
  '/jenkins-webapp/lab/application/containers' \
  '/jenkins-webapp/lab/monitoring/containers' \
  '/jenkins-webapp/lab/monitoring/system'; do
  rg -Fq "$group" "$repository_root/infra/live/main.tf" "$repository_root/monitoring" "$repository_root/ansible" "$repository_root/Jenkinsfile"
done

rg -q 'retention_in_days = 14' "$terraform_root/live/main.tf"
rg -q 'kms_key_id.*aws_kms_key.cloudwatch_logs' "$terraform_root/live/main.tf"
rg -q 'awslogs-create-group: "false"' "$repository_root/monitoring/compose.yml"
rg -q -- '--log-opt awslogs-create-group=false' "$repository_root/Jenkinsfile"
rg -q 'install_cloudwatch_logging.yml' "$repository_root/docs/CLOUDWATCH_LOGGING.md"

if rg -n --glob '*.js' 'request\.(headers|body|cookies|query)|error\.message' "$repository_root/src"; then
  echo "Application log implementation must not source headers, bodies, cookies, query strings, or error messages." >&2
  exit 1
fi

printf '%s\n' \
  'Terraform formatting: valid' \
  'Pre-created encrypted 14-day log groups: defined' \
  'Docker awslogs drivers: create-group disabled' \
  'Application structured-log sensitive sources: absent'
