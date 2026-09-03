#!/usr/bin/env bash
# Read-only Module 10 live preflight.  This script intentionally uses only AWS
# describe/list/get APIs and optional HTTP GET health endpoints.  It never
# writes Terraform state, starts queries, changes resources, or retrieves
# secret values.  Its report omits account IDs, ARNs, resource IDs, addresses,
# credentials, and endpoint URLs.
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
report_path=${MOD10_PREFLIGHT_REPORT:-"$repo_root/evidence/mod10/phase5-readonly-preflight.md"}
aws_region=${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || true)}}
project_tag=${MOD10_PROJECT_TAG:-jenkins-webapp}
environment_tag=${MOD10_ENVIRONMENT_TAG:-lab}

if [[ -z "$aws_region" ]]; then
  printf '%s\n' 'AWS_REGION/AWS_DEFAULT_REGION or an AWS CLI default region is required.' >&2
  exit 2
fi
command -v aws >/dev/null
command -v jq >/dev/null

mkdir -p "$(dirname "$report_path")"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

aws_read() {
  aws --no-cli-pager --region "$aws_region" "$@"
}

identity=$(aws_read sts get-caller-identity --output json)
principal_type=$(jq -r '.Arn | if contains(":assumed-role/") then "assumed role" elif contains(":user/") then "IAM user" elif contains(":role/") then "IAM role" else "other" end' <<<"$identity")

aws_read ec2 describe-instances \
  --filters "Name=tag:Project,Values=$project_tag" "Name=tag:Environment,Values=$environment_tag" \
  --output json >"$tmp_dir/instances.json"
aws_read ec2 describe-vpcs \
  --filters "Name=tag:Project,Values=$project_tag" "Name=tag:Environment,Values=$environment_tag" \
  --output json >"$tmp_dir/vpcs.json"
aws_read ec2 describe-vpc-peering-connections \
  --filters "Name=tag:Project,Values=$project_tag" "Name=tag:Environment,Values=$environment_tag" \
  --output json >"$tmp_dir/peerings.json"
aws_read ec2 describe-route-tables \
  --filters "Name=tag:Project,Values=$project_tag" "Name=tag:Environment,Values=$environment_tag" \
  --output json >"$tmp_dir/routes.json"
aws_read ec2 describe-security-groups \
  --filters "Name=tag:Project,Values=$project_tag" "Name=tag:Environment,Values=$environment_tag" \
  --output json >"$tmp_dir/security-groups.json"
aws_read logs describe-log-groups \
  --log-group-name-prefix "/$project_tag/$environment_tag/" \
  --output json >"$tmp_dir/log-groups.json"

instances_summary=$(jq -c '
  [.Reservations[].Instances[]? |
    {role: ([.Tags[]? | select(.Key == "Role") | .Value][0] // "unclassified"),
     state: .State.Name, type: .InstanceType,
     has_public_address: ((.PublicIpAddress // "") != "")}]
  | group_by(.role) | map({role: .[0].role, instances: length,
      states: (group_by(.state) | map({state: .[0].state, count: length})),
      instance_types: (group_by(.type) | map({type: .[0].type, count: length})),
      public_addresses_present: any(.[]; .has_public_address)})' "$tmp_dir/instances.json")
vpc_count=$(jq '.Vpcs | length' "$tmp_dir/vpcs.json")
peering_summary=$(jq -c '[.VpcPeeringConnections[]? | .Status.Code] | group_by(.) | map({state: .[0], count: length})' "$tmp_dir/peerings.json")
peering_route_count=$(jq '[.RouteTables[]?.Routes[]? | select(.VpcPeeringConnectionId? != null)] | length' "$tmp_dir/routes.json")
sg_summary=$(jq -c '
  [.SecurityGroups[]? |
    {role: ([.Tags[]? | select(.Key == "Role") | .Value][0] // "unclassified"),
     ingress_4318: ([.IpPermissions[]? | select((.FromPort // -1) <= 4318 and (.ToPort // -1) >= 4318)] | length),
     ingress_4318_public: ([.IpPermissions[]? | select((.FromPort // -1) <= 4318 and (.ToPort // -1) >= 4318) | .IpRanges[]? | select(.CidrIp == "0.0.0.0/0")] | length),
     ingress_4318_private_or_sg: ([.IpPermissions[]? | select((.FromPort // -1) <= 4318 and (.ToPort // -1) >= 4318) | (.IpRanges[]? | select(.CidrIp != "0.0.0.0/0")), .UserIdGroupPairs[]?] | length),
     egress_4318: ([.IpPermissionsEgress[]? | select((.FromPort // -1) <= 4318 and (.ToPort // -1) >= 4318)] | length)}]' "$tmp_dir/security-groups.json")
log_summary=$(jq -c '[.logGroups[]? | {retention_days: (.retentionInDays // "never-expire"), stored_bytes: .storedBytes}]' "$tmp_dir/log-groups.json")

# CPU is available through the native EC2 metric. Memory and disk capacity are
# deliberately not guessed: they need the existing host telemetry/host read.
cpu_summary='[]'
mapfile -t monitoring_instance_ids < <(jq -r '.Reservations[].Instances[]? | select(([.Tags[]? | select(.Key == "Role") | .Value][0] // "") == "monitoring") | .InstanceId' "$tmp_dir/instances.json")
if ((${#monitoring_instance_ids[@]})); then
  start_time=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)
  end_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cpu_samples=()
  for instance_id in "${monitoring_instance_ids[@]}"; do
    cpu_samples+=("$(aws_read cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization --dimensions "Name=InstanceId,Value=$instance_id" --statistics Average --period 300 --start-time "$start_time" --end-time "$end_time" --output json | jq '[.Datapoints[].Average]')")
  done
  cpu_summary=$(printf '%s\n' "${cpu_samples[@]}" | jq -s 'add // [] | if length == 0 then {status: "no recent CPU datapoints"} else {status: "available", samples: length, minimum_percent: (min * 100 | round / 100), maximum_percent: (max * 100 | round / 100), average_percent: (add / length * 100 | round / 100)} end')
fi

http_status() {
  local endpoint=$1
  if [[ -z "$endpoint" ]]; then
    printf '%s' 'not configured'
    return
  fi
  # Do not print the target.  A GET health probe is the only optional HTTP call.
  curl --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 10 --max-redirs 0 "$endpoint" 2>/dev/null || printf '%s' 'unreachable'
}

grafana_status=$(http_status "${MOD10_GRAFANA_HEALTH_URL:-}")
prometheus_status=$(http_status "${MOD10_PROMETHEUS_READY_URL:-}")
application_status=$(http_status "${MOD10_APPLICATION_HEALTH_URL:-}")

cat >"$report_path" <<EOF
# Module 10 Phase 5 Read-Only Preflight

Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Safety statement

This report was generated only with AWS \`get-caller-identity\`, \`describe-*\`,
and CloudWatch \`get-metric-statistics\` APIs, plus optional HTTP GET health
probes. No cloud resource, deployed runtime, Terraform state, Secrets Manager
value, CloudWatch log event, Jenkins job, container, or Grafana configuration
was changed. Account IDs, ARNs, resource IDs, IP addresses, CIDRs, endpoint
URLs, credentials, and tokens are intentionally omitted.

## Identity and scope

- Region: \`$aws_region\`
- Caller credential: reachable; principal type: $principal_type
- Resource selector: Project=\`$project_tag\`, Environment=\`$environment_tag\`

## AWS topology summary

- Tagged VPCs discovered: $vpc_count
- Instances: \`$instances_summary\`
- VPC peering states: \`$peering_summary\`
- Routes that reference a VPC peering connection: $peering_route_count
- Security-group TCP 4318 summary: \`$sg_summary\`

Interpretation: any non-zero \`ingress_4318_public\` is unexpected and blocks
rollout. A zero ingress count confirms TCP 4318 is not yet present; a non-zero
private-or-security-group count requires user review against the approved
application-to-monitoring path. Resource identifiers are intentionally not
recorded here.

## Logging and monitoring headroom

- Matching CloudWatch log-group metadata: \`$log_summary\`
- Monitoring-host CPU (previous hour): \`$cpu_summary\`
- Monitoring-host memory/disk: not available from native EC2 metrics; obtain
  through an existing read-only host telemetry view or an already-approved,
  read-only host session. Do not use SSM Run Command.

## Optional HTTP GET probes

- Grafana health: $grafana_status
- Prometheus readiness: $prometheus_status
- Application health: $application_status

\`not configured\` means no endpoint was supplied to this script; it is not a
health result. Endpoint values are intentionally omitted from the report.

## Exact user-controlled rollout mutation set

1. Review a Terraform plan that is limited to private TCP 4318 egress from the
   application security boundary and private TCP 4318 ingress on the monitoring
   security boundary, with no public source or public listener.
2. Deploy the reviewed monitoring Compose/Ansible configuration to introduce
   Jaeger, bind its OTLP receiver only to the approved monitoring private
   address, and keep its UI loopback-only.
3. Supply the approved non-secret private OTLP endpoint to the deployment
   workflow and deploy the application image.

The user owns every rollout, rollback, Terraform plan/apply, Ansible action,
container lifecycle action, and Jenkins build. Stop and investigate before
rollout if a tagged resource is missing, a peering is not active, an unexpected
public TCP 4318 rule exists, or unrelated resource drift appears.
EOF

printf 'Wrote sanitized read-only preflight report: %s\n' "$report_path"
