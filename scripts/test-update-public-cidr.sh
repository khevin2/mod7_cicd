#!/usr/bin/env bash
set -Eeuo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/test-update-public-cidr.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

fixture="$work_dir/fixture"
mkdir -p "$fixture/ansible/inventory" "$fixture/infra/live" "$fixture/bin"
cp "$repository_root/update_public_cidr.sh" "$fixture/update_public_cidr.sh"
cp "$repository_root/ansible/inventory/hosts.yml.example" "$fixture/ansible/inventory/hosts.yml"
cp "$repository_root/infra/live/terraform.tfvars.example" "$fixture/infra/live/terraform.tfvars"

cat >"$fixture/bin/ansible-inventory" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$fixture/bin/terraform" <<'EOF'
#!/usr/bin/env bash
set -eu
for argument in "$@"; do
  case $argument in
    -out=*) : >"${argument#-out=}" ;;
  esac
done
exit "${FAKE_TERRAFORM_STATUS:-0}"
EOF
chmod +x "$fixture/bin/ansible-inventory" "$fixture/bin/terraform"

PATH="$fixture/bin:$PATH" "$fixture/update_public_cidr.sh" \
  --ip 8.8.8.8 >/dev/null

grep -Eq 'administrator_ssh_cidr[[:space:]]*=[[:space:]]*"8\.8\.8\.8/32"' "$fixture/infra/live/terraform.tfvars"
grep -Eq 'grafana_admin_cidr[[:space:]]*=[[:space:]]*"8\.8\.8\.8/32"' "$fixture/infra/live/terraform.tfvars"
grep -Fq -- '- "8.8.8.8/32"' "$fixture/ansible/inventory/hosts.yml"
grep -Fq 'monitoring_admin_cidr: "8.8.8.8/32"' "$fixture/ansible/inventory/hosts.yml"
[[ -f $fixture/infra/live/live.tfplan ]]

cp "$repository_root/ansible/inventory/hosts.yml.example" "$fixture/ansible/inventory/hosts.yml"
cp "$repository_root/infra/live/terraform.tfvars.example" "$fixture/infra/live/terraform.tfvars"
rm "$fixture/infra/live/live.tfplan"
printf 'previous plan\n' >"$fixture/infra/live/live.tfplan"

if PATH="$fixture/bin:$PATH" FAKE_TERRAFORM_STATUS=1 \
  "$fixture/update_public_cidr.sh" --ip 1.1.1.1 >/dev/null 2>&1; then
  echo "Expected the fake Terraform failure." >&2
  exit 1
fi

cmp -s "$repository_root/ansible/inventory/hosts.yml.example" "$fixture/ansible/inventory/hosts.yml"
cmp -s "$repository_root/infra/live/terraform.tfvars.example" "$fixture/infra/live/terraform.tfvars"
grep -Fxq 'previous plan' "$fixture/infra/live/live.tfplan"

for invalid_ip in 999.1.1.1 10.0.0.1 127.0.0.1 169.254.1.1 192.0.2.1 224.0.0.1; do
  if PATH="$fixture/bin:$PATH" "$fixture/update_public_cidr.sh" \
    --ip "$invalid_ip" --plan-file invalid.tfplan >/dev/null 2>&1; then
    echo "Expected rejection of $invalid_ip." >&2
    exit 1
  fi
done

printf 'update_public_cidr.sh tests passed.\n'
