# CI EC2 verification

Date: 2026-11-08. Source: live, read-only AWS CLI calls using profile `training`, plus read-only SSH. The user executed the Terraform apply; the assistant made no cloud configuration changes.

- Account: `447558491229`; region: `eu-north-1`; availability zone: `eu-north-1c`.
- Instance: `i-00b38e42f46bc87a6`, `t3.small`, running; public address `13.53.218.22` at verification time.
- EC2 instance, system and attached EBS reachability checks: all `ok` / `passed`.
- CPU credit specification: `standard`.
- Metadata: IMDSv2 tokens required, hop limit 1.
- Root volume: 40 GiB gp3, encrypted, in use, delete on termination.
- Security group ingress: TCP 22 from the configured administrator IPv4 `/32` only. Egress: TCP 80 and 443. No public Jenkins/SonarQube ports.
- AWS console output: cloud-init completed. ED25519 host fingerprint independently verified as `SHA256:NSA65Dvo2cNvdTCTjSP5lUmSZ9bnjq++qxc9xHjlphA` before SSH.
- Read-only SSH: Amazon Linux 2023.12.20261102; 1913 MiB total RAM; 0 swap before Ansible; root filesystem 40 GiB with approximately 39 GiB available; `cloud-init status` reports `done`.
- Local ignored inventory and known_hosts file prepared using the instance IP and AWS-verified public host key.

Boot output includes an SSM credential error because no instance management IAM role is configured. SSH works; SSM management and the scoped Jenkins release role remain unconfigured.

## After operator-run Ansible provisioning

Read-only SSH verification on 2026-11-08 confirmed:

- Jenkins `2.580.2`, Java 21 Corretto and Docker installed. Jenkins active/enabled with zero systemd restarts, one executor, security enabled, and the configured 384 MiB heap. Listener bound to localhost `8080`; unauthenticated HTTP returned 403, consistent with protected/setup access.
- Dedicated swap active: approximately 6 GiB. Host RAM: 1913 MiB total, approximately 1038 MiB available during inspection. Root filesystem: approximately 11 GiB used, 30 GiB available.
- `vm.max_map_count=524288`; host descriptor maximum exceeds SonarQube's required threshold.
- Both pinned container images and all four named volumes present. SonarQube/PostgreSQL units inactive and disabled as intended before explicit startup.
- Database environment file `0600 root:root`; lifecycle sudoers file `0440 root:root`. Secret values were not read.
- No OOM-kill matches in the inspected kernel journal. `sudo cloud-init status` reports done; the unprivileged status command encountered a runtime-config permission error.

Jenkins wizard/plugin setup, SonarQube startup, scanner installation, analysis and memory reliability remain unverified. These observations do not close ECS application infrastructure or release requirements.
