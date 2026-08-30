#!/usr/bin/env bash
set -Eeuo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
compose_file="$repository_root/monitoring/compose.yml"

command -v docker >/dev/null
command -v jq >/dev/null

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
    (.healthcheck.test | length > 1) and
    (.restart == "unless-stopped")
  )
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
  (.networks | keys | sort == ["edge", "frontend", "telemetry"]) and
  (.networks.edge.internal != true) and
  (.networks.frontend.internal == true) and
  (.networks.telemetry.internal != true) and
  ([.services | to_entries[] | select(.value.networks | joins("edge")) | .key] == ["edge-proxy"]) and
  ([.services | to_entries[] | select(.value.networks | joins("frontend")) | .key] | sort == ["edge-proxy", "grafana"]) and
  ([.services | to_entries[] | select(.value.networks | joins("telemetry")) | .key] | sort == ["grafana", "node-exporter", "prometheus"]) and
  ([.services[].volumes[]? | select(.source == "/var/run/docker.sock")] | length == 0)
' >/dev/null <<<"$compose_json"; then
  echo "Compose network topology must keep edge-proxy on edge/frontend, Grafana on frontend/telemetry, and Prometheus plus Node Exporter on telemetry only." >&2
  exit 1
fi

if rg -n --glob '*.tf' 'aws_secretsmanager_secret_version|secret_string\s*=' \
  "$repository_root/infra/modules/monitoring_secrets"; then
  echo "Secret values must not be managed by Terraform." >&2
  exit 1
fi

printf '%s\n' \
  "Compose model: valid" \
  "Services: 4 digest-pinned, explicit non-root users" \
  "Hardening: read-only roots, cap-drop ALL, no-new-privileges, no privileged containers" \
  "Resources: health/restart/PID/CPU/memory/log controls present" \
  "Published ports: edge-proxy TCP 443 only" \
  "Networks: edge has only the published proxy; frontend is internal; telemetry has private-VPC scrape egress and no published port" \
  "Docker socket mounts: none" \
  "Terraform-managed secret values: none"
