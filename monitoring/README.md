# Hardened monitoring runtime

`compose.yml` is the Phase 3 runtime boundary for Prometheus, Grafana, the
monitoring host's Node Exporter, and an unprivileged Nginx TLS edge. Only host
TCP 443 is published. Prometheus, Grafana's native listener, and Node Exporter
exist only on Docker internal networks.

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
- `/opt/monitoring/secrets/grafana-contactpoints.yml`, rendered with the Slack
  incoming webhook fetched from its one named Secrets Manager container.
- `/etc/letsencrypt/cloudflare.ini`, containing only the scoped Cloudflare DNS
  token fetched from its one named Secrets Manager container.
- `/opt/monitoring/tls`, a least-readable copy of the issued certificate and
  private key for the unprivileged proxy.

Neither secret value belongs in Git, Terraform input/state, Compose environment,
Docker labels, command arguments, logs, or evidence. The ignored inventory holds
only the two secret ARNs, not values. The EC2 role created in Phase 4 must receive
only the read policy output by `infra/modules/monitoring_secrets` plus scoped KMS
decrypt access.

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

Grafana's container-local health command proves its binary remains executable;
Nginx performs the network liveness check at the only published endpoint. Phase
10 must additionally verify `https://grafana.kheven.me/api/health` through the
proxy and all Prometheus targets before runtime readiness is claimed.
