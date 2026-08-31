# Observability and security report

## Architecture and controls

The lab deploys an Express application through a GitHub-triggered Jenkins pipeline. Jenkins runs syntax and Jest/JUnit checks, repository and image Trivy gates, then publishes and deploys an immutable GHCR digest through strict SSH. Candidate health validation protects cutover; the prior image is retained for rollback. The application container runs as UID/GID 10001 with a read-only root filesystem, dropped capabilities, `no-new-privileges`, bounded resources, and no privileged mode or Docker socket.

Application/Jenkins resources (`10.70.0.0/16`) and monitoring resources (`10.80.0.0/16`) communicate over routed, non-transitive VPC peering. Prometheus privately scrapes application metrics (`:9464`) and Node Exporter (`:9100`); these endpoints are not public. Grafana alone is available on HTTPS to an approved administrator `/32`. Slack and Cloudflare credentials are retrieved at runtime from separately scoped Secrets Manager entries, never from Git, Terraform state, or evidence.

Prometheus evaluates every 15 seconds. The provisioned dashboard shows request rate (RPS), p95 latency, 5xx percentage, CPU, memory, disk, and target health. The high-error alert requires more than 5% 5xx responses for five minutes and at least 20 requests, preventing a tiny sample from generating noise.

## Controlled verification and logging

On 2026-08-30, all four post-recovery targets were `UP`: application, application-node, monitoring-node, and Prometheus. An approved fault test sent normal and deliberate requests every five seconds. The alert became Pending at 14:04:55 UTC, fired at 14:10:48 UTC after the five-minute requirement, and resolved at 14:15:52 UTC after traffic stopped. The internal controller was disabled, the fault route returned 404, and the normal healthy container was restored without fault injection. This is controlled test traffic, not a real service event.

CloudWatch Logs Insights found 156 application events matching the controlled 500-response filter between 14:04:28.862 and 14:10:55.089 UTC, which brackets the test. Application/container and selected system logs use encrypted CloudWatch log groups with 14-day retention. Structured application logging redacts bodies, headers, cookies, tokens, and other secrets.

## Audit, limitations, cost, and cleanup

The dedicated CloudTrail archive is live with multi-Region management events, log-file validation, KMS encryption, a public-blocked/versioned S3 bucket, and 30-day Standard-IA, 90-day Glacier, and 365-day expiry. GuardDuty is enabled in the lab Region; its recorded finding is an AWS-generated synthetic sample, not a real incident. CloudTrail and GuardDuty proof is retained separately to avoid repeating management actions solely for this report.

Monitoring runs on a cost-sensitive `t3.micro`; CPU, memory, and disk must be measured before any resize. Grafana, Node Exporter, and Nginx have documented fixable Trivy HIGH findings in their current official stable images; no CRITICAL finding was accepted, and the approved lab exception must be re-evaluated on each image update. Teardown requires preserving sanitized evidence, refreshing ownership, and applying only an explicitly approved destroy plan. Pre-existing or shared trails, detectors, keys, and resources are excluded.

Evidence: [Phase 11 verification](../evidence/20260830-phase11-live-verification.md), [CloudTrail verification](../evidence/20260828-phase6-live-verification.txt), [GuardDuty sample](../evidence/20260828-phase7-sample-finding.txt), and the [evidence index](../evidence/README.md).
