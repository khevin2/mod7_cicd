# Module 10 architecture guide

The `Module 10 runtime and convergence` page in `architecture.drawio` documents
the deployed advanced-observability design and the durable Ansible convergence
behavior. The earlier pages retain the Jenkins pipeline and broader Project 6
security context.

## Runtime flow

1. Jenkins validates, scans, publishes, and deploys an immutable application
   image digest to the application EC2 host.
2. The Express application creates inbound HTTP and Express spans, exposes
   bounded RED metrics with trace exemplars on private port 9464, and writes
   structured JSON logs containing `trace_id` and `span_id`.
3. Prometheus scrapes application and host metrics across VPC peering. The
   application independently exports sampled traces over private OTLP/HTTP TCP
   4318 to Jaeger.
4. Grafana queries Prometheus for RED and host panels and Jaeger for traces. A
   Prometheus exemplar opens the matching Jaeger trace. Grafana owns the two
   alerts: 5xx ratio above 5% for 10 minutes and p95 above 300 ms for 10 minutes.
5. The same trace ID is used to locate the matching application JSON event in
   CloudWatch Logs, completing the alert-to-metric-to-trace-to-log path.

## Ansible convergence flow

1. Ansible copies the approved monitoring and Grafana configuration and renders
   the runtime-only Slack contact point without displaying its secret.
2. It computes one fingerprint across datasource, managed-alert, contact-point,
   and dashboard-provider startup files.
3. It compares that value with the marker from the last successful Grafana
   provisioning load.
4. On drift or an interrupted previous deployment, Ansible restarts only
   Grafana, waits for Nginx `/healthz` to confirm Grafana readiness, and records
   the new fingerprint.
5. Dashboard JSON remains hot-reloaded through Grafana's 30-second file-provider
   poll. An unchanged second Ansible run does not restart Grafana.

## Security decisions

- TCP 4318 binds only to the monitoring host's private VPC address and accepts
  traffic only from the application VPC.
- Jaeger UI TCP 16686 binds only to loopback. Grafana, Prometheus, Node Exporter,
  native application ports, and the Docker API are not publicly exposed.
- Only administrator-restricted HTTPS 443 reaches the monitoring edge; the
  application retains its separately approved HTTP 80 lab endpoint.
- Trace IDs appear as exemplar metadata and JSON correlation fields, never as
  Prometheus labels. Jaeger uses bounded, non-durable in-memory lab storage.
- CloudWatch container logs retain the existing KMS encryption and 14-day
  retention boundary; secret values stay outside Git, Terraform state, Compose
  environment, logs, and evidence.
