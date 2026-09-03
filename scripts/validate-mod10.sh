#!/usr/bin/env bash
set -Eeuo pipefail

# Repository-only Module 10 validation. This script never contacts AWS,
# Terraform backends, Jenkins, or a remote Docker daemon.
repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

command -v jq >/dev/null
command -v rg >/dev/null

rg -Fq 'jaegertracing/all-in-one:1.76.0@sha256:' "$repository_root/monitoring/compose.yml"
rg -Fq '127.0.0.1:16686:16686' "$repository_root/monitoring/compose.yml"
rg -Fq 'JAEGER_OTLP_BIND_ADDRESS' "$repository_root/monitoring/compose.yml"
! rg -Fq '0.0.0.0:4318' "$repository_root/monitoring/compose.yml"
rg -Fq 'uid: jaeger' "$repository_root/monitoring/grafana/provisioning/datasources/jaeger.yml"
rg -Fq 'datasourceUid: jaeger' "$repository_root/monitoring/grafana/provisioning/datasources/prometheus.yml"
rg -Fq 'for: 10m' "$repository_root/monitoring/grafana/provisioning/alerting/webapp-alert-rules.yml"
rg -Fq 'jenkins-webapp-high-p95-latency' "$repository_root/monitoring/grafana/provisioning/alerting/webapp-alert-rules.yml"
rg -Fq 'Private OTLP/HTTP trace export to Jaeger' "$repository_root/infra/modules/network/main.tf"
rg -Fq 'Private OTLP/HTTP trace ingestion from the application VPC' "$repository_root/infra/modules/monitoring_network/main.tf"
rg -Fq 'APPLICATION_OTLP_TRACES_ENDPOINT' "$repository_root/Jenkinsfile"
rg -Fq 'OTEL_EXPORTER_OTLP_TRACES_ENDPOINT' "$repository_root/Jenkinsfile"
rg -Fq 'monitoring_jaeger_otlp_bind_address' "$repository_root/ansible/playbooks/install_monitoring_stack.yml"

jq empty "$repository_root/monitoring/grafana/dashboards/webapp-observability.json"
printf '%s\n' 'Module 10 Phase 3 static validation: passed (repository-only)'
