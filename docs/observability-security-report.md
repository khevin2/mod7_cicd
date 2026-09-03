# Module 10 observability report

**Status: implementation verified locally; live acceptance evidence pending.** This
report distinguishes repository evidence from a deployed-runtime claim. No cloud
resource was changed while preparing it.

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

The local integration test verifies the equivalent chain through an in-memory
Jaeger-compatible trace capture and structured JSON log; it does not prove live
Jaeger export or CloudWatch ingestion.

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

No Module 10 symptom, alert timestamp, exemplar, Jaeger span, or exact
CloudWatch `trace_id`/`span_id` match has been captured from the deployed lab
yet. Therefore the acceptance narrative is **pending**, not a claim of a live
incident or successful alert test.

When the user performs the approved bounded test, `POST /test` accepts only two
documented modes: `value: "error"` produces a deliberate HTTP 500 and
`value: "latency"` produces a fixed 400 ms successful response. Capture each
mode separately through Pending, Firing, and Resolved, then record the UTC
symptom and alert timestamps. From the Grafana marker, open the matching Jaeger
trace and inspect the route-stable HTTP server span plus the relevant child
client span, status, duration, and sanitized error attribute. Use the exact
trace ID to filter CloudWatch JSON logs and verify the corresponding span ID.
The expected controlled root cause is the chosen `/test` mode; remediation is
to stop test traffic and return to ordinary traffic, not to alter the alert.

## Acceptance, limits, and final state

Repository checks currently prove HTTP server/client instrumentation, RED
metrics and exemplars, Jaeger/Grafana provisioning, both 10-minute alert rules,
and removal of `/_phase10/*`, `/_phase11/*`, controller, and port 9465. The
durable `/test` route and observability configuration remain. The final user
deployment and read-only checks must still prove healthy Jaeger, populated
Grafana panels, alert lifecycles, trace links, CloudWatch correlation, version
capture, and ordinary-request tracing.

Lab limits: Jaeger storage is intentionally non-durable/lab-scoped, sampling is
100%, and the application has no database dependency, so database tracing is
N/A. Keep sanitized evidence in `evidence/mod10/`; never add endpoints,
credentials, account identifiers, raw CloudWatch exports, or unsanitized
screenshots. Final acceptance remains blocked until the missing live evidence
is captured by the user-operated procedure and read-only verification confirms
recovery.
