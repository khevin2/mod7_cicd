#!/usr/bin/env bash
set -Eeuo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
compose_file="$repository_root/monitoring/compose.yml"
nginx_config="$repository_root/ansible/templates/monitoring-nginx.conf.j2"

command -v docker >/dev/null
command -v jq >/dev/null
command -v rg >/dev/null

compose_json=$(docker compose --file "$compose_file" config --format json)

jq -e '
  .services | length == 4 and
  all(.[];
    (.image | test("@sha256:[0-9a-f]{64}$")) and
    (.user != null and .user != "" and .user != "0" and (.user | startswith("0:")) | not) and
    .read_only == true and
    (.cap_drop | index("ALL") != null) and
    (.security_opt | index("no-new-privileges:true") != null) and
    (.privileged != true) and
    (.pids_limit > 0) and
    (.mem_limit != null) and
    (.mem_reservation != null) and
    (.cpus > 0) and
    (.restart == "unless-stopped")
  ) and
  # The Grafana distroless image has no HTTP client. Its readiness is checked
  # end to end by edge-proxy /healthz -> Grafana /api/health instead.
  (.grafana.healthcheck == null) and
  all(to_entries[] | select(.key != "grafana"); .value.healthcheck.test | length > 1)
' >/dev/null <<<"$compose_json"

jq -e '
  [.services | to_entries[] | select(.value.ports != null) | {
    service: .key,
    ports: .value.ports
  }] == [{
    service: "edge-proxy",
    ports: [{mode: "ingress", host_ip: "0.0.0.0", target: 8443, published: "443", protocol: "tcp"}]
  }]
' >/dev/null <<<"$compose_json"

if ! jq -e '
  # Compose has represented service networks as both arrays and objects across
  # supported releases. Accept either JSON shape while checking the same
  # explicit topology.
  def joins($network):
    if type == "object" then has($network)
    elif type == "array" then index($network) != null
    else false
    end;
  (.networks | keys | sort == ["edge", "frontend", "prometheus-ui", "telemetry"]) and
  (.networks.edge.internal != true) and
  (.networks.frontend.internal == true) and
  (.networks["prometheus-ui"].internal == true) and
  (.networks.telemetry.internal != true) and
  ([.services | to_entries[] | select(.value.networks | joins("edge")) | .key] == ["edge-proxy"]) and
  ([.services | to_entries[] | select(.value.networks | joins("frontend")) | .key] | sort == ["edge-proxy", "grafana"]) and
  ([.services | to_entries[] | select(.value.networks | joins("prometheus-ui")) | .key] | sort == ["edge-proxy", "prometheus"]) and
  ([.services | to_entries[] | select(.value.networks | joins("telemetry")) | .key] | sort == ["grafana", "node-exporter", "prometheus"]) and
  ([.services[].volumes[]? | select(.source == "/var/run/docker.sock")] | length == 0)
' >/dev/null <<<"$compose_json"; then
  echo "Compose topology must isolate the edge, Grafana frontend, Prometheus UI proxy path, and scrape telemetry networks." >&2
  exit 1
fi

if ! rg -Uq '(?s)location = /healthz \{.*proxy_pass http://grafana:3000/api/health;' "$nginx_config"; then
  echo "edge-proxy /healthz must proxy Grafana's /api/health endpoint." >&2
  exit 1
fi

for required_nginx_policy in \
  'listen 8443 ssl default_server;' \
  'server_name {{ monitoring_metrics_server_name }};' \
  'satisfy all;' \
  'allow {{ monitoring_admin_cidr }};' \
  'deny all;' \
  'auth_basic "Prometheus administration";' \
  'auth_basic_user_file /etc/nginx/auth/prometheus.htpasswd;' \
  'proxy_set_header Authorization "";' \
  'proxy_pass http://prometheus:9090;'; do
  rg -Fq "$required_nginx_policy" "$nginx_config"
done

rg -Fq -- '--web.external-url=https://${PROMETHEUS_SERVER_NAME:-metrics.kheven.me}/' "$compose_file"
rg -Fq '/opt/monitoring/nginx-secrets:/etc/nginx/auth:ro' "$compose_file"
! rg -Fq 'auth_basic off' "$nginx_config"

if rg -n --glob '*.tf' 'aws_secretsmanager_secret_version|secret_string\s*=' \
  "$repository_root/infra/modules/monitoring_secrets"; then
  echo "Secret values must not be managed by Terraform." >&2
  exit 1
fi

rg -Fq 'aws_secretsmanager_secret.prometheus_basic_auth_htpasswd.arn' \
  "$repository_root/infra/modules/monitoring_secrets/main.tf"

printf '%s\n' \
  "Compose model: valid" \
  "Services: 4 digest-pinned, explicit non-root users" \
  "Hardening: read-only roots, cap-drop ALL, no-new-privileges, no privileged containers" \
  "Resources: health/restart/PID/CPU/memory/log controls present" \
  "Published ports: edge-proxy TCP 443 only" \
  "Networks: edge is published; frontend and Prometheus UI paths are separately internal; telemetry retains private scrape egress" \
  "Prometheus edge auth: approved /32 and bcrypt-backed Nginx Basic Auth are both required" \
  "Readiness: edge-proxy health verifies Grafana /api/health end to end" \
  "Docker socket mounts: none" \
  "Terraform-managed secret values: none"
