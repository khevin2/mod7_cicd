#!/usr/bin/env bash
set -Eeuo pipefail

# Discovers the current Jenkins, application, and monitoring addresses from
# Terraform, retrieves their ED25519 host keys, and synchronizes Ansible's
# inventory and known_hosts file.
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

retrieve_console_host_key() {
  local instance_output=$1
  local host_address=$2
  local key_file=$3
  local instance_id
  local aws_region

  command -v aws >/dev/null || return 1

  instance_id=$(terraform_output "$instance_output") || return 1
  [[ -n $instance_id && $instance_id != null ]] || return 1

  aws_region=${AWS_REGION:-${AWS_DEFAULT_REGION:-}}
  if [[ -z $aws_region ]]; then
    aws_region=$(aws configure get region 2>/dev/null) || return 1
  fi
  [[ -n $aws_region ]] || return 1

  # Amazon Linux publishes its public host keys in the authenticated EC2 boot
  # console. This is a safe fallback when port 22 is intentionally allowlisted.
  aws ec2 get-console-output \
    --region "$aws_region" \
    --instance-id "$instance_id" \
    --latest \
    --query Output \
    --output text 2>/dev/null |
    awk -v host="$host_address" \
      '$1 == "ssh-ed25519" { print host, $1, $2; found = 1; exit } END { if (!found) exit 1 }' \
      >"$key_file"
}

prepare_updated_inventory() {
  local application_entry=$1
  local output_file=$2

  if ! awk \
    -v application_address="$application_address" \
    -v application_entry="$application_entry" \
    -v jenkins_address="$jenkins_address" \
    -v monitoring_address="$monitoring_address" \
    -v monitoring_private_address="$monitoring_private_address" '
    /^        deployment_host:[[:space:]]*$/ {
      host = "deployment"
      print
      next
    }
    /^        jenkins_controller:[[:space:]]*$/ {
      host = "jenkins"
      print
      next
    }
    /^        monitoring_host:[[:space:]]*$/ {
      host = "monitoring"
      print
      next
    }
    host == "deployment" && /^          ansible_host:/ {
      print "          ansible_host: \"" application_address "\""
      deployment_host_updated = 1
      host = ""
      next
    }
    host == "jenkins" && /^          ansible_host:/ {
      print "          ansible_host: \"" jenkins_address "\""
      jenkins_host_updated = 1
      host = ""
      next
    }
    host == "monitoring" && /^          ansible_host:/ {
      print "          ansible_host: \"" monitoring_address "\""
      monitoring_host_updated = 1
      host = ""
      next
    }
    /ProxyCommand=/ {
      if (sub(/ec2-user@[^"[:space:]]+/, "ec2-user@" jenkins_address)) {
        proxy_updated = 1
      }
      print
      next
    }
    /^        jenkins_known_hosts_entries:[[:space:]]*$/ {
      print
      print "          - \"" application_entry "\""
      in_entries = 1
      runtime_key_updated = 1
      next
    }
    in_entries && /^          - / { next }
    /^        monitoring_application_metrics_target:/ {
      print "        monitoring_application_metrics_target: \"" application_address ":9464\""
      metrics_target_updated = 1
      in_entries = 0
      next
    }
    /^        monitoring_application_node_exporter_target:/ {
      print "        monitoring_application_node_exporter_target: \"" application_address ":9100\""
      node_exporter_target_updated = 1
      in_entries = 0
      next
    }
    /^        monitoring_jaeger_otlp_bind_address:/ {
      print "        monitoring_jaeger_otlp_bind_address: \"" monitoring_private_address "\""
      jaeger_address_updated = 1
      in_entries = 0
      next
    }
    {
      in_entries = 0
      print
    }
    END {
      if (!deployment_host_updated || !jenkins_host_updated ||
          !monitoring_host_updated || !proxy_updated || !runtime_key_updated ||
          !metrics_target_updated || !node_exporter_target_updated ||
          !jaeger_address_updated) {
        exit 1
      }
    }
  ' "$inventory_file" >"$output_file"; then
    echo "Could not update all managed address fields in $inventory_file." >&2
    exit 1
  fi
}

jenkins_address=$(terraform_output jenkins_elastic_ip || true)
if [[ -z $jenkins_address || $jenkins_address == null ]]; then
  jenkins_address=$(terraform_output jenkins_public_ip)
fi
application_address=$(terraform_output application_private_ip)
monitoring_address=$(terraform_output monitoring_elastic_ip)
monitoring_private_address=$(terraform_output monitoring_private_ip)

for address_name in jenkins_address application_address monitoring_address monitoring_private_address; do
  address=${!address_name}
  if [[ -z $address || $address == null || ! $address =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
    echo "Terraform did not return a usable IPv4 address for $address_name." >&2
    exit 1
  fi
done

jenkins_key_file=$(mktemp)
application_key_file=$(mktemp)
monitoring_key_file=$(mktemp)
temporary_known_hosts=
temporary_inventory=

cleanup() {
  rm -f "$jenkins_key_file" "$application_key_file" "$monitoring_key_file"
  if [[ -n $temporary_known_hosts ]]; then
    rm -f "$temporary_known_hosts" "$temporary_known_hosts.old"
  fi
  if [[ -n $temporary_inventory ]]; then
    rm -f "$temporary_inventory"
  fi
}
trap cleanup EXIT

if ! ssh-keyscan -T 10 -t ed25519 "$jenkins_address" >"$jenkins_key_file" 2>/dev/null || [[ ! -s $jenkins_key_file ]]; then
  echo "Jenkins SSH at $jenkins_address is not reachable; trying its authenticated EC2 console output." >&2
  if ! retrieve_console_host_key jenkins_instance_id "$jenkins_address" "$jenkins_key_file"; then
    echo "Could not retrieve the Jenkins ED25519 host key by SSH or from its EC2 console output." >&2
    echo "Check that the instance is running, your AWS CLI is authenticated, and its boot console contains SSH host keys." >&2
    exit 1
  fi
fi

if ! ssh \
  -i "$repository_root/keys/jenkins-webapp-lab-ec2" \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$jenkins_key_file" \
  "ec2-user@$jenkins_address" \
  "ssh-keyscan -T 10 -t ed25519 '$application_address' 2>/dev/null" >"$application_key_file" 2>/dev/null || [[ ! -s $application_key_file ]]; then
  echo "The application key is not reachable through Jenkins; trying its authenticated EC2 console output." >&2
  if ! retrieve_console_host_key instance_id "$application_address" "$application_key_file"; then
    echo "Could not retrieve the application ED25519 host key through Jenkins or from its EC2 console output." >&2
    exit 1
  fi
fi

if ! ssh-keyscan -T 10 -t ed25519 "$monitoring_address" >"$monitoring_key_file" 2>/dev/null || [[ ! -s $monitoring_key_file ]]; then
  echo "Monitoring SSH at $monitoring_address is not reachable; trying its authenticated EC2 console output." >&2
  if ! retrieve_console_host_key monitoring_instance_id "$monitoring_address" "$monitoring_key_file"; then
    echo "Could not retrieve the monitoring ED25519 host key by SSH or from its EC2 console output." >&2
    exit 1
  fi
fi

jenkins_fingerprint=$(ssh-keygen -lf "$jenkins_key_file" -E sha256 | awk 'NR == 1 { print $2 }')
application_fingerprint=$(ssh-keygen -lf "$application_key_file" -E sha256 | awk 'NR == 1 { print $2 }')
monitoring_fingerprint=$(ssh-keygen -lf "$monitoring_key_file" -E sha256 | awk 'NR == 1 { print $2 }')

echo "Jenkins:     $jenkins_address  $jenkins_fingerprint"
echo "Application: $application_address  $application_fingerprint"
echo "Monitoring:  $monitoring_address  $monitoring_fingerprint"
echo
read -r -p 'Verify these fingerprints through a trusted channel, then type ADD to update known_hosts and the inventory: ' confirmation
if [[ $confirmation != ADD ]]; then
  echo 'No changes made.'
  exit 0
fi

mkdir -p "$(dirname "$known_hosts_file")"
touch "$known_hosts_file"

temporary_known_hosts=$(mktemp "${known_hosts_file}.tmp.XXXXXX")
temporary_inventory=$(mktemp "${inventory_file}.tmp.XXXXXX")
cp "$known_hosts_file" "$temporary_known_hosts"

# Remove both the newly discovered addresses and addresses referenced by the
# previous inventory, so reprovisioned hosts do not leave stale trust entries.
mapfile -t previous_addresses < <(
  awk '
    /^[[:space:]]+ansible_host:/ {
      address = $2
      gsub(/"/, "", address)
      print address
    }
    /ProxyCommand=/ {
      address = $0
      sub(/^.*ec2-user@/, "", address)
      sub(/".*$/, "", address)
      print address
    }
  ' "$inventory_file"
)

# Verified host-key rotations replace older entries for these addresses.
for address in "${previous_addresses[@]}" "$jenkins_address" "$application_address" "$monitoring_address"; do
  ssh-keygen -R "$address" -f "$temporary_known_hosts" >/dev/null 2>&1 || true
done
cat "$jenkins_key_file" >>"$temporary_known_hosts"
cat "$application_key_file" >>"$temporary_known_hosts"
cat "$monitoring_key_file" >>"$temporary_known_hosts"

# The controller playbook copies this verified application entry to
# /var/lib/jenkins/.ssh/known_hosts for pipeline deployment SSH.
application_key_entry=$(awk '/^[^#]/ { print; exit }' "$application_key_file")
prepare_updated_inventory "$application_key_entry" "$temporary_inventory"

mv "$temporary_known_hosts" "$known_hosts_file"
mv "$temporary_inventory" "$inventory_file"

echo "Verified ED25519 keys added to $known_hosts_file."
echo "Synchronized Terraform addresses and jenkins_known_hosts_entries in $inventory_file."
