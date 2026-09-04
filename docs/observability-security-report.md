# Module 10 observability report

**Status: implementation and deployed-runtime acceptance evidence verified.**
The retained evidence confirms the configured design and the live monitoring,
alerting, tracing, logging, correlation, and recovery path. No cloud resource
was changed while preparing this report.

## Architecture and telemetry flow

`jenkins-webapp` emits bounded RED metrics on its private metrics endpoint and
structured JSON logs to stdout. Prometheus scrapes the metrics, evaluates
recording rules, and supplies Grafana dashboards and alerts. OpenTelemetry HTTP
and Express instrumentation creates server and outbound-client spans. In a
deployment, the application exports sampled traces via OTLP/HTTP only to the
approved private Jaeger receiver; Grafana resolves histogram exemplars to that
Jaeger datasource. The log record retains only `trace_id` and `span_id` for
cross-tool correlation.

The intended investigation path is:

`symptom -> alert -> RED metric/exemplar -> Jaeger trace and span -> CloudWatch JSON log -> controlled root cause`.

The integration test verifies the chain through a Jaeger-compatible trace
capture and structured JSON log. Retained deployed-runtime evidence separately
confirms live Jaeger export and CloudWatch ingestion.

## RED policy and safety controls

| Signal | Definition | Alert threshold and hold time |
| --- | --- | --- |
| Rate | `jenkins_webapp_http_requests_total` | Dashboard only |
| Errors | 5xx requests / all requests over 5 minutes | >5%, at least 20 requests, sustained 10 minutes |
| Duration | p95 of request-duration histogram over 5 minutes | >300 ms, at least 20 requests, sustained 10 minutes |

Grafana is the sole alert engine and evaluates the alert group every 10 seconds.
The histogram includes sampled W3C trace IDs as exemplars without adding them as
Prometheus labels. Metric labels are bounded to method, route, and status code.
Logs allowlist operational fields and never include request bodies, headers,
cookies, tokens, query values, or arbitrary errors. The OTLP endpoint rejects
public addresses and credentials. Sampling is `parentbased_traceidratio` at
100% for this lab; production use must reduce it according to volume and
retention policy.

## Controlled incident analysis

The Module 10 deployed evidence has been reviewed and verified. It captures the
controlled symptom, alert lifecycle, Grafana exemplar, matching Jaeger spans,
exact CloudWatch `trace_id`/`span_id` correlation, and recovery to healthy
ordinary traffic.

The approved bounded test used the two documented `POST /test` modes:
`value: "error"` produced a deliberate HTTP 500 and `value: "latency"`
produced a fixed 400 ms successful response. Each mode was assessed separately
through Pending, Firing, and Resolved. The evidence follows the Grafana marker
to the matching Jaeger trace, route-stable server span, relevant client span,
status, duration, and sanitized error attribute, then uses the exact trace ID
to verify the corresponding CloudWatch JSON log and span ID. The controlled
root cause was the selected `/test` mode; recovery was achieved by stopping
test traffic rather than suppressing or bypassing the alert.

## Acceptance, limits, and final state

Repository checks prove HTTP server/client instrumentation, RED metrics and
exemplars, Jaeger/Grafana provisioning, both 10-minute alert rules, and removal
of `/_phase10/*`, `/_phase11/*`, controller, and port 9465. Deployed-runtime
evidence verifies healthy Jaeger, populated Grafana panels, alert lifecycles,
trace links, CloudWatch correlation, version capture, recovery, and
ordinary-request tracing. The durable `/test` route and observability
configuration remain.

Lab limits: Jaeger storage is intentionally non-durable/lab-scoped, sampling is
100%, and the application has no database dependency, so database tracing is
N/A. Keep sanitized evidence in `evidence/mod10/`; never add endpoints,
credentials, account identifiers, raw CloudWatch exports, or unsanitized
screenshots. Final acceptance is verified from the retained sanitized evidence.
