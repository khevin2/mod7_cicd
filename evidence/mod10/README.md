# Module 10 Evidence Index

This directory contains sanitized, reviewer-facing evidence for Advanced
Observability and Distributed Tracing. Never add credentials, cookies, tokens,
account IDs, ARNs, IP addresses, endpoint URLs, raw CloudWatch exports, or
unsanitized screenshots.

## Capture sequence

1. `baseline.md`: at least ten minutes of normal request rate, p95 latency,
   error ratio, CPU, memory, scrape health, and no firing Module 10 alert.
2. `error-alert.md` and `error-alert-*.png`: controlled error test pending,
   firing after ten minutes, and resolved state, with the dashboard time range.
3. `latency-alert.md` and `latency-alert-*.png`: the equivalent independent
   p95-latency test evidence.
4. `trace-correlation.md` and `trace-correlation-*.png`: one Grafana
   exemplar, the same trace in Jaeger, its relevant span/error attribute, and
   an exact `trace_id` CloudWatch JSON match that also shows `span_id`.
5. `versions.md`: Node and installed OpenTelemetry package versions,
   Prometheus, Grafana, Jaeger, and CloudWatch logging-path versions.
6. `recovery.md`: controller disabled, ordinary traffic recovered, alerts
   resolved, and test endpoints unavailable after the final clean deployment.

Each Markdown summary must label the action as user-operated or read-only,
state timestamps in UTC, identify the evidence file names, and avoid sensitive
identifiers. The correlation summary must demonstrate:

`symptom -> alert -> metric exemplar -> Jaeger trace/span -> JSON log -> controlled root cause`

`phase5-readonly-preflight.md` is pre-rollout discovery only; it does not prove
runtime trace export or alert behavior.
