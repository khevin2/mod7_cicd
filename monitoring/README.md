# Hardened monitoring runtime

`compose.yml` is the Phase 3 runtime boundary for Prometheus, Grafana, the
monitoring host's Node Exporter, and an unprivileged Nginx TLS edge. Only host
TCP 443 is published. The edge proxy alone joins a non-internal edge bridge;
the frontend bridge between Nginx and Grafana is Docker-internal. The telemetry
bridge has no published ports but permits Prometheus to reach the application
metrics and Node Exporter through the private VPC peering route. Grafana's
native listener and both exporters remain inaccessible from the public network.
A separate internal `prometheus-ui` bridge joins only Nginx and Prometheus, so
the proxy can expose the authenticated UI without gaining access to exporters.

All four image references include both a version tag and an immutable
multi-platform digest resolved from their official registries on 2026-08-27.
The tag keeps the selected release human-readable; the digest controls the
actual content. Re-resolve and scan each digest before a later upgrade.

## Current image-gate status

The Phase 3 deployment uses the newest official stable images pinned in
`compose.yml`. The 2026-08-27 exact-digest Trivy scan found no HIGH/CRITICAL
findings in Prometheus, and no CRITICAL findings in any selected image. It did
report fixable HIGH findings in Grafana bundled plugin binaries, Node Exporter's
Go runtime, and Nginx Alpine OpenSSL packages. The supported alternative image
variants tested that day were not cleaner.

The project owner has explicitly accepted these Trivy HIGH findings for this
lab so the Ansible gate is `accepted_stable_image_exception`. This is a recorded
exception, not a claim that the findings are fixed or false positives. Re-scan
the exact digests before every image update; adopt a clean official stable image
as soon as one is available. Do not carry this exception into production without
a separate risk review and compensating controls.

## Runtime inputs

The deployment playbook creates these untracked, EBS-backed paths:

- `/opt/monitoring/secrets/grafana-admin-password`, generated locally and
  exposed to Grafana through a file-backed Compose secret.
- `/opt/monitoring/monitoring/grafana/provisioning/alerting/contactpoints.yml`,
  rendered with the Slack incoming webhook fetched from its one named Secrets
  Manager container. It is runtime-only, owned by Grafana, mode `0400`, and
  shares the single read-only provisioning-directory mount with non-secret
  alert-rule configuration.
- `/etc/letsencrypt/cloudflare.ini`, containing only the scoped Cloudflare DNS
  token fetched from its one named Secrets Manager container.
- `/opt/monitoring/tls`, a least-readable copy of the issued certificate and
  private key for the unprivileged proxy.
- `/opt/monitoring/nginx-secrets/prometheus.htpasswd`, containing only the
  bcrypt htpasswd entry fetched from its named Secrets Manager container. The
  directory is mounted read-only into Nginx and no other container.

No secret value belongs in Git, Terraform input/state, Compose environment,
Docker labels, command arguments, logs, or evidence. The ignored inventory holds
only the three secret ARNs, not values. The EC2 role created in Phase 4 must receive
only the read policy output by `infra/modules/monitoring_secrets` plus scoped KMS
decrypt access.

Generate the Prometheus entry on a trusted administrator workstation with an
interactive prompt:

```bash
htpasswd -nBC 12 prometheus-admin
```

Use a unique password of at least 24 characters, keep its plaintext only in a
password manager, and put the single resulting `prometheus-admin:$2...` line in
the Terraform-created Secrets Manager container out of band. Rerunning the
playbook validates and installs the hash, then safely reloads Nginx. Rotation
uses the same procedure; verify the new password and confirm the old one returns
`401`.

## Hardening boundary

Every service is non-root, read-only, capability-free, protected with
`no-new-privileges`, resource/PID constrained, restart-controlled, health-checked,
and configured with bounded local log rotation. Writable state is limited to two
named volumes and small `tmpfs` mounts. There is no privileged container and no
Docker socket mount.

Node Exporter is the documented exception: it joins the host PID namespace and
bind-mounts `/` read-only with `rslave` propagation so it can report the host's
procfs, sysfs, and filesystem state through `/host`. It remains UID/GID 65534,
has no capabilities, cannot write the host, and has no published port. Removing
the host namespace/mount would materially reduce required host telemetry; adding
write access, the Docker socket, host networking, or privilege is not approved.

Prometheus and Node Exporter use container-local health checks; Nginx checks
Grafana over the private frontend. Phase 10 must additionally verify
`https://grafana.kheven.me/api/health`, authenticated
`https://metrics.kheven.me/-/ready`, the unauthenticated `401` response, and all
Prometheus targets before runtime readiness is claimed.

## Observability and alerting

`prometheus.yml` evaluates every 15 seconds, with explicit 15-second scrape
intervals and 10-second timeouts. It scrapes Prometheus itself, the monitoring
host Node Exporter, and two application-host endpoints: `/metrics` on 9464 and
Node Exporter on 9100. The application endpoints are rendered from approved
private `host:port` values in the ignored Ansible inventory into file-SD target
files; neither endpoint is committed or exposed publicly.

`recording-rules.yml` precomputes request rate, p95 latency, and 5xx percentage.
It deliberately contains no alert definitions. Grafana is the sole alerting
engine: its managed high-error rule requires more than 5% 5xx responses for
five minutes and at least 20 requests in the same five-minute window, then
routes firing and resolved notifications through the runtime-injected Slack
contact point. The traffic guard avoids noise from a tiny sample. The contact
point has a stable provisioning UID and is reconciled in place; it is not
deleted during startup because the Grafana alert rule references it.

Run `bash scripts/validate-phase8.sh` to validate the Prometheus configuration
and rules with the exact pinned Prometheus image and to check the provisioned
dashboard and alert metadata. Runtime target, panel, Slack, and alert-state
proof remains Phase 10/11 work.
