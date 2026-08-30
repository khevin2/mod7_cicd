#!/usr/bin/env bash
set -Eeuo pipefail

# Phase 10 is deliberately split into a repository preflight (this script) and
# an approved live change.  It must not create an inventory, contact AWS, or
# run Terraform/Ansible against an environment.
repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

for script in validate-phase3.sh validate-phase4.sh validate-phase5.sh \
  validate-phase8.sh validate-phase9.sh; do
  # The region is a public, approved configuration value. Supplying it here
  # lets Compose validate its required awslogs interpolation without reading an
  # inventory or attempting an AWS operation.
  AWS_REGION=eu-north-1 bash "$repository_root/scripts/$script" >/dev/null
done

playbook="$repository_root/ansible/playbooks/install_monitoring_stack.yml"
inventory_example="$repository_root/ansible/inventory/hosts.yml.example"
compose="$repository_root/monitoring/compose.yml"

# Ansible must require environment-specific values from the ignored inventory,
# rather than silently using placeholders or a public application endpoint.
for input in \
  monitoring_certbot_email \
  monitoring_aws_region \
  monitoring_slack_secret_arn \
  monitoring_cloudflare_secret_arn \
  monitoring_application_metrics_target \
  monitoring_application_node_exporter_target; do
  rg -Fq "$input" "$playbook" "$inventory_example"
done

rg -Fq 'StrictHostKeyChecking=yes' "$inventory_example"
rg -Fq 'monitoring_server_name == "grafana.kheven.me"' "$playbook"
rg -Fq 'docker, compose, --file, compose.yml, up, --detach, --remove-orphans, --wait' "$playbook"
! rg -Fq -- '--force-recreate' "$playbook"
rg -Fq 'awslogs-create-group: "false"' "$compose"
rg -Fq 'read_only: true' "$compose"
rg -Fq 'no-new-privileges:true' "$compose"

# TLS and dashboard runtime proof may only be gathered after the user reviews
# the exact saved plan and the user-managed DNS-only record resolves correctly.
rg -Fq 'monitoring_elastic_ip' "$repository_root/infra/live/outputs.tf"
rg -Fq 'Create and verify the DNS-only grafana.kheven.me A record manually before certificate issuance.' "$repository_root/infra/live/outputs.tf"

printf '%s\n' \
  'Phase 10 repository preflight: passed' \
  'Prior static gates (Phases 3, 4, 5, 8, and 9): passed' \
  'Monitoring playbook: requires ignored live inventory values and strict host-key checking' \
  'Runtime model: hardened Compose waits for healthy containers; Grafana remains the only public monitoring endpoint' \
  'Scope: repository preflight only; current live status requires separate, sanitized Phase 10 evidence'
