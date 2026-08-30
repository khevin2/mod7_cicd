#!/usr/bin/env bash
set -Eeuo pipefail

inventory_file="ansible/inventory/hosts.yml"
terraform_file="infra/live/terraform.tfvars"

get_public_ip() {
  curl -fsS --max-time 10 https://api.ipify.org
}

public_ip=$(get_public_ip)
new_cidr="${public_ip}/32"

cidr_32_pattern='([0-9]{1,3}\.){3}[0-9]{1,3}/32'

sed -E -i "s|$cidr_32_pattern|$new_cidr|g" "$inventory_file"
sed -E -i "s|$cidr_32_pattern|$new_cidr|g" "$terraform_file"

cd infra/live
terraform plan -out=tfplan
terraform apply -auto-approve tfplan
cd ../..