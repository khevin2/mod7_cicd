#!/usr/bin/env bash
set -Eeuo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
inventory_file="$repository_root/ansible/inventory/hosts.yml"
terraform_file="$repository_root/infra/live/terraform.tfvars"
terraform_root="$repository_root/infra/live"

public_ip=
plan_name=

usage() {
  cat <<'EOF'
Usage: ./update_public_cidr.sh [options]

Refresh the approved administrator IPv4 /32 in the local Terraform and Ansible
configuration, then create (but never apply) a Terraform plan for review.

Options:
  --ip IPV4                      Use an explicit public IPv4 instead of ipify
  --plan-file NAME.tfplan        Override the default live.tfplan filename
  -h, --help                     Show this help

Examples:
  ./update_public_cidr.sh
  ./update_public_cidr.sh --ip 8.8.8.8
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

while (($#)); do
  case $1 in
    --ip)
      (($# >= 2)) || die "--ip requires a value."
      public_ip=$2
      shift 2
      ;;
    --plan-file)
      (($# >= 2)) || die "--plan-file requires a value."
      plan_name=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "Unknown option: $1 (use --help for usage)." ;;
  esac
done

for command_name in grep sed mktemp cp python3 terraform ansible-inventory; do
  command -v "$command_name" >/dev/null 2>&1 || die "Required command is unavailable: $command_name"
done

for required_file in "$inventory_file" "$terraform_file"; do
  [[ -f $required_file ]] || die "Required local configuration is missing: $required_file"
done

if [[ -z $public_ip ]]; then
  command -v curl >/dev/null 2>&1 || die "Required command is unavailable: curl"
  public_ip=$(curl --fail --silent --show-error --location \
    --proto '=https' --tlsv1.2 --retry 2 --connect-timeout 5 --max-time 15 \
    https://api.ipify.org)
fi

is_public_ipv4() {
  python3 -c '
import ipaddress
import sys

try:
    address = ipaddress.IPv4Address(sys.argv[1])
except ipaddress.AddressValueError:
    raise SystemExit(1)
raise SystemExit(0 if address.is_global and not address.is_multicast else 1)
' "$1" 2>/dev/null
}

is_public_ipv4 "$public_ip" || die "The supplied service/address is not a public IPv4 address: $public_ip"
new_cidr="${public_ip}/32"

require_one_match() {
  local pattern=$1 file=$2 description=$3 count
  count=$(grep -Ec "$pattern" "$file" || true)
  [[ $count == 1 ]] || die "Expected exactly one $description in $file; found $count."
}

require_one_match '^[[:space:]]*administrator_ssh_cidr[[:space:]]*=' \
  "$terraform_file" "administrator_ssh_cidr assignment"
require_one_match '^[[:space:]]*jenkins_admin_cidrs:' \
  "$inventory_file" "jenkins_admin_cidrs list"
require_one_match '^[[:space:]]*grafana_admin_cidr[[:space:]]*=' \
  "$terraform_file" "grafana_admin_cidr assignment"
require_one_match '^[[:space:]]*monitoring_admin_cidr:' \
  "$inventory_file" "monitoring_admin_cidr assignment"

jenkins_list_item=$(sed -n \
  '/^[[:space:]]*jenkins_admin_cidrs:[[:space:]]*$/ { n; p; }' \
  "$inventory_file")
jenkins_list_pattern='^[[:space:]]*-[[:space:]]*"[^"]+"[[:space:]]*$'
[[ $jenkins_list_item =~ $jenkins_list_pattern ]] || \
  die "jenkins_admin_cidrs must have its primary quoted CIDR on the following line."

[[ -n $plan_name ]] || plan_name=live.tfplan
[[ $plan_name != */* && $plan_name == *.tfplan ]] || \
  die "--plan-file must be a .tfplan filename without a directory."
plan_file="$terraform_root/$plan_name"
[[ ! -e $plan_file || -f $plan_file ]] || die "Plan path exists but is not a regular file: $plan_file"

backup_dir=$(mktemp -d "${TMPDIR:-/tmp}/update-public-cidr.XXXXXX")
cp -p "$inventory_file" "$backup_dir/hosts.yml"
cp -p "$terraform_file" "$backup_dir/terraform.tfvars"
had_existing_plan=false
if [[ -f $plan_file ]]; then
  cp -p "$plan_file" "$backup_dir/previous.tfplan"
  had_existing_plan=true
fi
configuration_changed=false

restore_on_failure() {
  local status=$?
  if ((status != 0)) && [[ $configuration_changed == true ]]; then
    cp -p "$backup_dir/hosts.yml" "$inventory_file"
    cp -p "$backup_dir/terraform.tfvars" "$terraform_file"
    if [[ $had_existing_plan == true ]]; then
      cp -p "$backup_dir/previous.tfplan" "$plan_file"
    else
      rm -f "$plan_file"
    fi
    printf 'Restored both configuration files after failure.\n' >&2
  fi
  rm -f "$backup_dir/hosts.yml" "$backup_dir/terraform.tfvars" "$backup_dir/previous.tfplan"
  rmdir "$backup_dir"
  exit "$status"
}
trap restore_on_failure EXIT

configuration_changed=true

sed -E -i \
  "s|^([[:space:]]*administrator_ssh_cidr[[:space:]]*=[[:space:]]*)\"[^\"]+\"|\1\"$new_cidr\"|" \
  "$terraform_file"
sed -E -i \
  "/^[[:space:]]*jenkins_admin_cidrs:[[:space:]]*$/ { n; s|^([[:space:]]*-[[:space:]]*)\"[^\"]+\"|\1\"$new_cidr\"|; }" \
  "$inventory_file"
sed -E -i \
  "s|^([[:space:]]*grafana_admin_cidr[[:space:]]*=[[:space:]]*)\"[^\"]+\"|\1\"$new_cidr\"|" \
  "$terraform_file"
sed -E -i \
  "s|^([[:space:]]*monitoring_admin_cidr:[[:space:]]*)\"[^\"]+\"|\1\"$new_cidr\"|" \
  "$inventory_file"

ansible-inventory -i "$inventory_file" --list >/dev/null
terraform -chdir="$terraform_root" fmt -check -recursive
terraform -chdir="$terraform_root" validate
terraform -chdir="$terraform_root" plan -out="$plan_file"

configuration_changed=false
rm -f "$backup_dir/hosts.yml" "$backup_dir/terraform.tfvars" "$backup_dir/previous.tfplan"
rmdir "$backup_dir"
trap - EXIT

printf '\nUpdated all administrator CIDR configuration to %s.\n' "$new_cidr"
printf 'Saved Terraform plan: %s\n\n' "$plan_file"
printf 'Review every change before applying this unified-state plan:\n'
printf '  terraform -chdir=%q show -no-color %q\n' "$terraform_root" "$plan_file"
printf '  terraform -chdir=%q apply %q\n\n' "$terraform_root" "$plan_file"
printf 'After the approved apply, deploy the matching Nginx allowlist:\n'
printf '  ansible-playbook -i %q %q\n' \
  "$inventory_file" "$repository_root/ansible/playbooks/install_jenkins_controller.yml"
printf '  ansible-playbook -i %q %q\n' \
  "$inventory_file" "$repository_root/ansible/playbooks/install_monitoring_stack.yml"
