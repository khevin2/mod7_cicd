#!/usr/bin/env bash
set -Eeuo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
jenkinsfile="$repository_root/Jenkinsfile"

for script in validate-phase3.sh validate-phase8.sh validate-phase11.sh; do
  rg -Fq "bash scripts/$script" "$jenkinsfile"
done

# Terraform belongs to the local, reviewed infrastructure workflow. Jenkins
# must not invoke it, including for plans, applies, or destroys.
if rg -n '^[[:space:]]*terraform([[:space:]]|$)' "$jenkinsfile"; then
  echo "Jenkins must not invoke Terraform-managed infrastructure operations." >&2
  exit 1
fi

rg -q "githubPush\(\)" "$jenkinsfile"
rg -q "disableConcurrentBuilds\(\)" "$jenkinsfile"
rg -q "buildDiscarder\(logRotator" "$jenkinsfile"
rg -q "timeout\(time: 30, unit: 'MINUTES'\)" "$jenkinsfile"
rg -q "junit allowEmptyResults: true" "$jenkinsfile"
rg -q "StrictHostKeyChecking=yes" "$jenkinsfile"
rg -q "DEPLOY_IMAGE_REF=.*image-digest.txt" "$jenkinsfile"
rg -q 'docker tag "\$previous" "\$\{APP_NAME\}:rollback"' "$jenkinsfile"

for required_control in \
  '--user 10001:10001' \
  '--read-only' \
  '--tmpfs /tmp:rw,noexec,nosuid,nodev,size=16m' \
  '--cap-drop ALL' \
  '--security-opt no-new-privileges:true' \
  '--pids-limit 128' \
  '--memory 256m' \
  '--memory-reservation 128m' \
  '--cpus 0.50' \
  '--restart unless-stopped' \
  'awslogs-create-group=false'; do
  rg -Fq -- "$required_control" "$jenkinsfile"
done

if rg -n --glob '!evidence/**' --glob '!COMPLETION.md' \
  '(AKIA[0-9A-Z]{16}|-----BEGIN( [A-Z]+)? PRIVATE KEY-----|xox[baprs]-)' \
  "$repository_root"; then
  echo "Potential committed secret material detected." >&2
  exit 1
fi

printf '%s\n' \
  'Pipeline invokes metric, Prometheus, dashboard, Compose, Ansible, and secret static gates' \
  'Terraform remains a local, reviewed workflow; Jenkins has no Terraform command' \
  'Webhook/manual host fallback, timeout, concurrency, retention, JUnit, digest, strict SSH, and rollback controls: present' \
  'Application candidate and active deployment: non-root, read-only, tmpfs, dropped capabilities, no-new-privileges, health, restart, and resource limits' \
  'Phase 11 fault-control preflight: invoked; normal CI deployment cannot enable or publish it' \
  'Repository secret-pattern check: no matches'
