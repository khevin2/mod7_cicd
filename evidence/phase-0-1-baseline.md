# Phase 0–1 planning and baseline record

Date: 2026-11-01. Source: local checkout of `feature/secure-ecs-ec2` at `9662bf8835d19eed4e7f39ecc0a9b212c39db5c2`. This record concerns local inspection and checks; it does not establish the current state of AWS or Jenkins.

## Boundaries and decisions

- The working checkout and `COMPLETION.md` are in the project root. The plan remains an untracked local file until the user explicitly authorizes a commit.
- Do not commit, push, or modify cloud resources/files without the user's explicit permission. A GitHub branch was created before this instruction and has been checked out locally.
- Jenkins remains the intended CI platform. ECS EC2, ECR and the existing application are confirmed project choices. Scanner selection, hosting, sizing and infrastructure reuse are proposals pending the inputs in the tracker.
- The user selected `eu-north-1` for this project and has not yet configured AWS CLI access for this work. The AWS account and spending limit remain unconfirmed.
- The previous monitoring project records a historical `eu-north-1` deployment and an earlier teardown of app/Jenkins hosts. It also records later monitoring verification. These observations do not establish what exists now.
- Cost drivers to estimate before provisioning include the Jenkins host, ECS container instances and EBS, load balancer, public IPs, outbound networking/NAT or VPC endpoints, ECR storage, log ingestion/retention, and any SonarQube and monitoring hosts. Actual costs require region, sizes, operating hours and current pricing; no budget has been established.
- A future teardown must identify and preserve shared state, networking, monitoring, and rollback artifacts; project-owned resources are to be listed separately. No AWS operation is authorized by this document.

## Migration inventory

| Existing component | Phase 1 finding and planned treatment |
| --- | --- |
| `src/`, `test/`, `package*.json`, `Dockerfile` | Retain as the starting app, test suite and image definition; verify the current lockfile and runtime before adding features. |
| `Jenkinsfile`: checkout, installation, Jest/JUnit | Reuse the general stages and build metadata; add branch-specific job verification and the required gates. |
| `Jenkinsfile`: Trivy repository/image scans | Retain useful report generation and image scanning; remove the `--ignore-unfixed` policy for High/Critical vulnerability gates and add the other required scanners. |
| `Jenkinsfile`: GHCR environment and Push Image | Replace GHCR credentials/login/push with ECR authentication, commit tag and immutable digest capture. |
| `Jenkinsfile`: Deploy and Runtime Cleanup | Replace SSH and remote Docker deployment/cleanup with task definition rendering, ECS service update, health/rollback verification and bounded ECR/ECS retention. Preserve build cleanup and archived artifacts as appropriate. |
| `infra/modules/network` | Review as a reference; it currently provisions one public subnet and host security groups, so ECS/ALB subnet, network and access design needs work. |
| `infra/modules/ec2_host`, `infra/live` | Existing EC2 module is for standalone app and Jenkins hosts. Reuse Jenkins provisioning where appropriate; create ECS EC2 launch template, Auto Scaling group, capacity provider and service resources. Avoid accidentally replacing existing infrastructure. |
| `infra/modules/state_backend`, `infra/bootstrap` | Reuse patterns only after deciding whether existing state is shared or a new isolated backend is needed. Never assume permission to replace shared state. |
| `ansible/playbooks/install_jenkins_controller.yml` | Candidate for Jenkins host setup; review job, plugins and credential requirements. Current Jenkins availability is unverified. |
| `ansible/playbooks/install_docker.yml` | Standalone app-host setup is not the ECS deployment mechanism; ECS-optimized host bootstrapping needs separate design. |

## Monitoring integration gap

The prior monitoring project provides Prometheus recording rules, a Grafana dashboard and Grafana-managed 5xx and p95 latency alerts, with a Slack contact point. Its app exposes application metrics on port 9464, and its scrape configuration uses private app-host targets. The current `mod7_cicd` branch does not contain that metrics instrumentation. Existing rules therefore cannot simply be pointed at the new service: port the required instrumentation and tests or choose equivalent ECS-compatible signals, then adapt discovery/networking for changing task addresses and verify alert behavior. CloudWatch `awslogs` remains required for ECS task logs. The monitoring stack's current availability, network reachability and notification configuration are unverified.

Sources inspected locally: `../mod8_monitoring/README.md`, `../mod8_monitoring/monitoring/README.md`, `../mod8_monitoring/prometheus.yml`, and `../mod8_monitoring/monitoring/grafana/provisioning/alerting/webapp-alert-rules.yml`.

## Executed checks

- `git status --short --branch`: local branch tracks `origin/feature/secure-ecs-ec2`; local plan and assignment files were untracked.
- `node --version`: `v24.18.0`; `npm --version`: `11.16.0`.
- `npm run check`: passed.
- Docker CLI: `29.7.2`; local default Docker daemon was accessible outside the sandbox. Initial sandbox socket access was denied.

- `npm ci --no-audit --no-fund`: passed, installing 346 packages. It emitted deprecation notices for `inflight` and `glob`. The first sandboxed attempt was interrupted after network access stalled; the successful retry used network access outside the sandbox. Lockfiles were unchanged.
- `npm test -- --ci --runInBand`: passed outside the sandbox, 1 suite and 4 tests. The initial sandboxed run failed with `EPERM` because Supertest could not open a listening socket.
- `docker build --tag mod9-baseline:local .`: passed. Local image ID: `sha256:5f978f481032574d56afbc5ecb4c16a8c374ce6aa4d3f80b37e315c38827f96b`. Docker used its legacy builder because the buildx plugin was unavailable.
- A temporary container from that image ran as UID/GID 10001 and returned HTTP 200 with `{"service":"jenkins-webapp","status":"ok"}` from `/health`. Docker's health status was still `starting` at inspection; the endpoint response, rather than Docker's eventual healthy status, was verified. The temporary container was stopped.
- `npm audit --omit=dev --audit-level=high`: failed, reporting 1 High (`body-parser`, GHSA-27r3-jxmh-p828), 1 Critical (`proxy-addr`, GHSA-jqcg-44mw-7w3h), and 1 Moderate (`qs`). The image-build dependency installation independently reported the same severity counts. These are baseline findings, not a completed SCA gate; remediation and scanner verification belong to Phase 3.
