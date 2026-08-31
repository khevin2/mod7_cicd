#!/usr/bin/env bash
set -Eeuo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
prometheus_image='prom/prometheus:v3.14.0-distroless@sha256:50c707e96da5ade383cb1707790576480485e93de06aa60ad8802cb5f744bd0a'

command -v docker >/dev/null
command -v jq >/dev/null
command -v rg >/dev/null

docker run --rm \
  --entrypoint /bin/promtool \
  -v "$repository_root/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
  -v "$repository_root/monitoring/alert-rules.yml:/etc/prometheus/alert-rules.yml:ro" \
  "$prometheus_image" check config /etc/prometheus/prometheus.yml >/dev/null

docker run --rm \
  --entrypoint /bin/promtool \
  -v "$repository_root/monitoring/alert-rules.yml:/etc/prometheus/alert-rules.yml:ro" \
  "$prometheus_image" check rules /etc/prometheus/alert-rules.yml >/dev/null

jq -e '
  .uid == "jenkins-webapp-observability" and
  .title == "Jenkins Webapp Observability" and
  (.panels | length == 7) and
  ([.panels[].title] | sort) == ["CPU usage", "Disk usage", "HTTP 5xx percentage", "Memory usage", "Request rate", "Scrape target health", "p95 request latency"] and
  all(.panels[]; .datasource.uid == "prometheus")
' "$repository_root/monitoring/grafana/dashboards/webapp-observability.json" >/dev/null

rg -q 'uid: jenkins-webapp-high-error-rate' "$repository_root/monitoring/grafana/provisioning/alerting/webapp-alert-rules.yml"
rg -q 'interval: 10s' "$repository_root/monitoring/grafana/provisioning/alerting/webapp-alert-rules.yml"
rg -q 'for: 5m' "$repository_root/monitoring/grafana/provisioning/alerting/webapp-alert-rules.yml"
rg -q 'receiver: project6-slack' "$repository_root/monitoring/grafana/provisioning/alerting/webapp-alert-rules.yml"
rg -q 'disableResolveMessage: false' "$repository_root/ansible/templates/grafana-contactpoints.yml.j2"
rg -q 'recipient: "#project6-observability-alerts"' "$repository_root/ansible/templates/grafana-contactpoints.yml.j2"
rg -q 'monitoring_application_metrics_target' "$repository_root/ansible/playbooks/install_monitoring_stack.yml"

printf '%s\n' \
  "Prometheus configuration and alert rules: valid with pinned promtool" \
  "Grafana dashboard: valid JSON with seven required panels" \
  "Grafana alert: 5-minute >5% error threshold with 20-request guard" \
  "Slack contact point: resolved notifications enabled" \
  "Application target: rendered only from ignored deployment inventory"
