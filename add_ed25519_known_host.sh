#!/usr/bin/env bash
set -Eeuo pipefail

# Discovers the current Jenkins, application, and monitoring addresses from
# Terraform, retrieves their ED25519 host keys, and updates Ansible's
# known_hosts file.
# The one manual confirmation is intentional: automatically trusting a
# first-seen network key would defeat StrictHostKeyChecking.

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
terraform_directory="$repository_root/infra/live"
known_hosts_file="$repository_root/ansible/inventory/known_hosts"
inventory_file="$repository_root/ansible/inventory/hosts.yml"

for command in terraform ssh ssh-keyscan ssh-keygen mktemp; do
  command -v "$command" >/dev/null || {
    echo "Required command not found: $command" >&2
    exit 1
  }
done

terraform_output() {
  terraform -chdir="$terraform_directory" output -raw "$1" 2>/dev/null
}

update_jenkins_runtime_known_hosts() {
  local application_entry=$1
  local temporary_inventory

  temporary_inventory=$(mktemp "${inventory_file}.tmp.XXXXXX")
  if ! awk -v entry="$application_entry" '
    /^        jenkins_known_hosts_entries:[[:space:]]*$/ {
      print
      print "          - \"" entry "\""
      in_entries = 1
      found = 1
      next
    }
    in_entries && /^          - / { next }
    {
      in_entries = 0
      print
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$inventory_file" >"$temporary_inventory"; then
    rm -f "$temporary_inventory"
    echo "Could not find jenkins_known_hosts_entries in $inventory_file." >&2
    exit 1
  fi

  mv "$temporary_inventory" "$inventory_file"
}

jenkins_address=$(terraform_output jenkins_elastic_ip || true)
if [[ -z $jenkins_address || $jenkins_address == null ]]; then
  jenkins_address=$(terraform_output jenkins_public_ip)
fi
application_address=$(terraform_output application_private_ip)
monitoring_address=$(terraform_output monitoring_elastic_ip)

if [[ -z $jenkins_address || $jenkins_address == null || -z $application_address || $application_address == null || -z $monitoring_address || $monitoring_address == null ]]; then
  echo 'Terraform did not return usable Jenkins, application, and monitoring addresses.' >&2
  exit 1
fi

jenkins_key_file=$(mktemp)
application_key_file=$(mktemp)
monitoring_key_file=$(mktemp)
trap 'rm -f "$jenkins_key_file" "$application_key_file" "$monitoring_key_file"' EXIT

if ! ssh-keyscan -T 10 -t ed25519 "$jenkins_address" >"$jenkins_key_file" 2>/dev/null || [[ ! -s $jenkins_key_file ]]; then
  echo "Could not retrieve an ED25519 host key from Jenkins at $jenkins_address." >&2
  exit 1
fi

if ! ssh \
  -i "$repository_root/keys/jenkins-webapp-lab-ec2" \
  -o BatchMode=yes \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  "ec2-user@$jenkins_address" \
  "ssh-keyscan -T 10 -t ed25519 '$application_address' 2>/dev/null" >"$application_key_file" 2>/dev/null || [[ ! -s $application_key_file ]]; then
  echo "Could not retrieve an ED25519 host key from the application host at $application_address through Jenkins." >&2
  exit 1
fi

if ! ssh-keyscan -T 10 -t ed25519 "$monitoring_address" >"$monitoring_key_file" 2>/dev/null || [[ ! -s $monitoring_key_file ]]; then
  echo "Could not retrieve an ED25519 host key from monitoring at $monitoring_address." >&2
  exit 1
fi

jenkins_fingerprint=$(ssh-keygen -lf "$jenkins_key_file" -E sha256 | awk 'NR == 1 { print $2 }')
application_fingerprint=$(ssh-keygen -lf "$application_key_file" -E sha256 | awk 'NR == 1 { print $2 }')
monitoring_fingerprint=$(ssh-keygen -lf "$monitoring_key_file" -E sha256 | awk 'NR == 1 { print $2 }')

echo "Jenkins:     $jenkins_address  $jenkins_fingerprint"
echo "Application: $application_address  $application_fingerprint"
echo "Monitoring:  $monitoring_address  $monitoring_fingerprint"
echo
read -r -p 'Verify these fingerprints through a trusted channel, then type ADD to update known_hosts: ' confirmation
if [[ $confirmation != ADD ]]; then
  echo 'No changes made.'
  exit 0
fi

mkdir -p "$(dirname "$known_hosts_file")"
touch "$known_hosts_file"

# Verified host-key rotations replace older entries for these addresses.
for address in "$jenkins_address" "$application_address" "$monitoring_address"; do
  ssh-keygen -R "$address" -f "$known_hosts_file" >/dev/null 2>&1 || true
done
cat "$jenkins_key_file" >>"$known_hosts_file"
cat "$application_key_file" >>"$known_hosts_file"
cat "$monitoring_key_file" >>"$known_hosts_file"

# The controller playbook copies this verified application entry to
# /var/lib/jenkins/.ssh/known_hosts for pipeline deployment SSH.
application_key_entry=$(awk '/^[^#]/ { print; exit }' "$application_key_file")
update_jenkins_runtime_known_hosts "$application_key_entry"

echo "Verified ED25519 keys added to $known_hosts_file."
echo "Updated jenkins_known_hosts_entries in $inventory_file for $application_address."
