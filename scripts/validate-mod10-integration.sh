#!/usr/bin/env bash
set -Eeuo pipefail

# Local-only Module 10 integration check. It creates an isolated Docker network
# and short-lived containers, then removes them on exit. It never contacts AWS,
# Terraform, Jenkins, or any deployed environment.
repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
app_image=${MOD10_APP_IMAGE:-jenkins-webapp:mod10-phase4-local}
jaeger_image='jaegertracing/all-in-one:1.76.0@sha256:ab6f1a1f0fb49ea08bcd19f6b84f6081d0d44b364b6de148e1798eb5816bacac'
run_id="mod10-smoke-$$"
network_name="$run_id"
jaeger_name="$run_id-jaeger"
app_name="$run_id-app"

command -v curl >/dev/null
command -v docker >/dev/null
command -v jq >/dev/null

cleanup() {
  docker rm -f "$app_name" "$jaeger_name" >/dev/null 2>&1 || true
  docker network rm "$network_name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker image inspect "$app_image" >/dev/null
docker network create "$network_name" >/dev/null
docker run -d --name "$jaeger_name" --network "$network_name" \
  -p 127.0.0.1::16686 \
  -e COLLECTOR_OTLP_ENABLED=true \
  -e SPAN_STORAGE_TYPE=memory \
  -e MEMORY_MAX_TRACES=1000 \
  "$jaeger_image" >/dev/null

jaeger_port=$(docker port "$jaeger_name" 16686/tcp | sed -n 's/.*:\([0-9][0-9]*\)$/\1/p' | head -n 1)
test -n "$jaeger_port"
for _attempt in $(seq 1 30); do
  if curl --silent --fail "http://127.0.0.1:${jaeger_port}/" >/dev/null; then break; fi
  sleep 1
done
curl --silent --fail "http://127.0.0.1:${jaeger_port}/" >/dev/null

jaeger_ip=$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$jaeger_name")
test -n "$jaeger_ip"
docker run -d --name "$app_name" --network "$network_name" \
  -p 127.0.0.1::3000 -p 127.0.0.1::9464 \
  -e OTEL_TRACES_EXPORTER=otlp \
  -e OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf \
  -e OTEL_EXPORTER_OTLP_TRACES_ENDPOINT="http://${jaeger_ip}:4318/v1/traces" \
  -e OTEL_SERVICE_NAME=jenkins-webapp \
  -e OTEL_TRACES_SAMPLER=parentbased_traceidratio \
  -e OTEL_TRACES_SAMPLER_ARG=1 \
  "$app_image" >/dev/null

app_port=$(docker port "$app_name" 3000/tcp | sed -n 's/.*:\([0-9][0-9]*\)$/\1/p' | head -n 1)
metrics_port=$(docker port "$app_name" 9464/tcp | sed -n 's/.*:\([0-9][0-9]*\)$/\1/p' | head -n 1)
test -n "$app_port" && test -n "$metrics_port"
for _attempt in $(seq 1 30); do
  if curl --silent --fail "http://127.0.0.1:${app_port}/health" >/dev/null; then break; fi
  sleep 1
done
curl --silent --fail "http://127.0.0.1:${app_port}/health" >/dev/null
curl --silent --fail "http://127.0.0.1:${app_port}/" >/dev/null

metrics=$(curl --silent --fail "http://127.0.0.1:${metrics_port}/metrics")
trace_id=$(printf '%s\n' "$metrics" | sed -n 's/.*traceId="\([0-9a-f]\{32\}\)".*/\1/p' | head -n 1)
test -n "$trace_id"

for _attempt in $(seq 1 30); do
  traces=$(curl --silent --fail "http://127.0.0.1:${jaeger_port}/api/traces?service=jenkins-webapp&limit=20")
  if jq -e --arg trace_id "$trace_id" '.data[]? | select(.traceID == $trace_id)' <<<"$traces" >/dev/null; then break; fi
  sleep 1
done
jq -e --arg trace_id "$trace_id" '.data[]? | select(.traceID == $trace_id)' <<<"$traces" >/dev/null
docker logs "$app_name" 2>&1 | jq -R -e --arg trace_id "$trace_id" \
  'fromjson? | select(.event == "http_request_completed" and .trace_id == $trace_id and (.span_id | test("^[0-9a-f]{16}$")))' >/dev/null

printf '%s\n' 'Module 10 local integration: health, OpenMetrics exemplar, Jaeger trace, and JSON log trace ID match: passed'
