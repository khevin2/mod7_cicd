#!/usr/bin/env bash
set -Eeuo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
inventory_file="$repository_root/ansible/inventory/hosts.yml"
terraform_file="$repository_root/infra/live/terraform.tfvars"
terraform_root="$repository_root/infra/live"

get_public_ip() {
  curl -fsS --max-time 10 https://api.ipify.org
}

public_ip=$(get_public_ip)
new_cidr="${public_ip}/32"

if [[ ! $public_ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "The public-IP service returned an invalid IPv4 address." >&2
  exit 1
fi

for required_file in "$inventory_file" "$terraform_file"; do
  if [[ ! -f $required_file ]]; then
    echo "Required local configuration is missing: $required_file" >&2
    exit 1
  fi
done

if ! grep -Eq '^[[:space:]]*monitoring_admin_cidr:' "$inventory_file"; then
  echo "monitoring_admin_cidr is missing from the Ansible inventory." >&2
  exit 1
fi

if ! grep -Eq '^[[:space:]]*grafana_admin_cidr[[:space:]]*=' "$terraform_file"; then
  echo "grafana_admin_cidr is missing from the Terraform variables." >&2
  exit 1
fi

sed -E -i \
  "s|^([[:space:]]*monitoring_admin_cidr:[[:space:]]*)\"[^\"]+\"|\1\"$new_cidr\"|" \
  "$inventory_file"
sed -E -i \
  "s|^([[:space:]]*grafana_admin_cidr[[:space:]]*=[[:space:]]*)\"[^\"]+\"|\1\"$new_cidr\"|" \
  "$terraform_file"

terraform -chdir="$terraform_root" plan -out=tfplan
terraform -chdir="$terraform_root" apply -auto-approve tfplan
