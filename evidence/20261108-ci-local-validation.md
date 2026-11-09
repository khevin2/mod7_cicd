# Shared CI host: local validation

Date: 2026-11-08. Working branch: `feature/secure-ecs-ec2`. Local edits only; no commit or Jenkins run was created.

## Implemented locally

- `infra/ci`: dedicated CI networking, SSH-only ingress, one AL2023 `t3.small`, Standard CPU credits, encrypted 40 GiB gp3 disk, account guard, separate local state.
- `ansible/playbooks/configure_ci_demo.yml`: 6 GiB swap, kernel mapping limit, Java/Jenkins/Docker, one Jenkins executor, small JVM heaps, pinned SonarQube/PostgreSQL images, persistent volumes and root-owned database environment.
- Systemd container services and `mod9-sonar` helper; SonarQube/database disabled at boot and stopped by default after provisioning.
- Optional `MANAGE_LOCAL_SONAR=true` lifecycle in the Jenkins SAST stage, including unconditional stage cleanup after gate success or failure.
- Operator setup commands in `infra/ci/README.md`. Previous ECS drafts and unrelated local work were preserved.

## Executed checks

- Terraform AWS provider initialized locally: HashiCorp AWS `6.72.0`; lockfile created.
- `terraform -chdir=infra/ci validate`: passed. Provider socket initialization failed in the sandbox; validation succeeded outside the sandbox. No plan/apply was executed.
- Terraform formatting checks: passed for the new root and modified EC2 module files.
- Ansible syntax check with a temporary YAML inventory and the image pin vars: passed. No Ansible play was executed against a host.
- YAML parsing and strict Jinja rendering of both service templates: passed.
- `systemd-analyze verify` on the rendered units: passed locally; no service was started.
- `bash -n ansible/files/mod9-sonar`: passed.
- Mocked lifecycle checks: start waits for `UP`, stop orders SonarQube before PostgreSQL, service-start failure returns nonzero, extra helper arguments rejected. Mock checks do not establish actual server readiness.
- Docker Hub digest resolver executed read-only: returned valid immutable references for SonarQube Community and PostgreSQL 17; no Docker pulls occurred locally.
- `git diff --check`: passed.

## Outstanding live acceptance

The operator must review/run a Terraform plan and apply, verify the SSH host key, run Ansible, initialize both applications, install plugins/scanner tools, configure credentials and quality gates, establish webhook and scoped AWS role access, and verify actual pipeline outcomes. The 2 GiB shared host is below SonarQube's documented host sizing and remains an experiment. Successful startup, repeated analysis, memory/swap behavior, absence of OOM kills, deployed application and demo reliability are unverified. No requirement for live Jenkins or AWS evidence is closed by these local checks.
