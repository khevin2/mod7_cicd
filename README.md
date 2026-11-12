# Secure CI/CD pipeline — Jenkins, ECR and ECS on EC2

This lab hardens the existing Express application with SAST, dependency, image and secret scans, generates a CycloneDX SBOM, and deploys approved images by digest to Amazon ECS on EC2. Terraform manages infrastructure; Ansible manages Jenkins, its locked plugins, scanner tools, SonarQube and job configuration.

The assignment is in [Secure CI-CD Pipeline.md](Secure%20CI-CD%20Pipeline.md). Start with the [submission evidence index](evidence/README.md) for executed results and the exported reports.

## Verified results

| Check | Result |
| --- | --- |
| Vulnerable dependency injection | Build 11 rejected a High-severity Snyk finding; downstream image/release stages were skipped and ECS remained unchanged. |
| Fix and successful release | Build 12 passed the gates and deployed `mod9-ecs-app:6`. |
| Release image | `sha256:606ea7f71ad7b64019eed5814953af2d6bf5359cbc79f79fe26fbece19e1be1b` |
| Automatic rollback | Build 10 intentionally failed revision 5; ECS restored revision 3 and its original digest, with target/application health verified. |
| Monitoring | Real-metric alarm evaluation transitioned OK → ALARM → OK; original configuration restored. |
| Cleanup | Revisions 4/5 and their two demo images removed; active/rollback/bootstrap images retained and revision 6 remained healthy. |

Results were verified on 2026-11-11/12. [Archived JSON, reports and SBOM](evidence/submission/) preserve the release evidence after Jenkins artifact rotation. Account identifiers, addresses and paths in those exports are redacted; use actual Terraform outputs for reproduction.

## Architecture and pipeline

[Editable ECS architecture diagram](docs/architecture-ecs.drawio) · [diagram guide](docs/architecture-ecs.md)

```text
GitHub → Jenkins on EC2 → ECR → ECS service → application task on EC2
             │                                   ↑
             ├─ Gitleaks, tests, SonarQube, Snyk   ALB ← approved client CIDRs
             └─ Trivy, Syft                      │
                                             CloudWatch logs/alarms
```

Jenkins and SonarQube/PostgreSQL share one `t3.small`, one executor and 6 GiB swap. Stages run sequentially; SonarQube stops after SAST. Jenkins and SonarQube bind to loopback and are accessed through SSH tunnels. The separate application VPC contains the ALB and an ECS capacity provider backed by an Auto Scaling group. Tasks use `awsvpc` networking and accept port 3000 only from the ALB security group.

Pipeline order: checkout → secret scans → install/tests → SAST → SCA/repository/configuration scans → image build → image scans/SBOM → approved ECR publication → approved ECS deployment and exact revision/digest/health verification. High/Critical vulnerabilities and detected secrets block release; scanner errors also fail the pipeline. Narrow lab infrastructure exceptions are documented in [security policy](security/SECURITY.md).

The EC2 publisher role supplies scoped ECR/ECS permissions without stored AWS access keys. Snyk and SonarQube tokens are supplied through managed Jenkins credentials. All publication/deployment flags default false; releases require a manual operator cause and explicit approval. The verified runs were manually started: the current deployment has no verified public GitHub webhook route.

## Reproduce the lab

Prerequisites: Git, Node.js 24, npm, Terraform, AWS CLI profile `training` in `eu-north-1`, Python 3 and the [pinned Ansible controller](ansible/requirements-ci.txt). Docker is needed for local container checks. Provisioning also requires an operator-owned Snyk account/token and private Vault inputs.

1. Provision the CI EC2 host using [infra/ci/README.md](infra/ci/README.md). Verify its SSH host key and configure ignored inventory/Vault inputs.
2. Run `configure_ci_demo.yml`, then follow [CI security setup](docs/CI_SECURITY_SETUP.md) for `configure_ci_security.yml`. Jenkins plugins and tools are installed by Ansible, not manually through the UI.
3. Run [scan-only validation](docs/SECURE_ECS_PIPELINE.md). Resolve findings without bypassing gates.
4. Provision [ECS/ECR foundations](infra/ecs-ec2/README.md), publish a scanned image, then create the initial service using that ECR digest as `release_image`.
5. Generate release settings and review/apply scoped CI IAM through [the release runbook](docs/SECURE_ECS_PIPELINE.md). Run `run_ci_release.yml` for an approved release.
6. Follow [rollback/monitoring](docs/PHASE_7_RUNBOOK.md) and [security/cleanup](docs/PHASE_8_9_RUNBOOK.md) runbooks for the demonstrations and scoped cleanup.

Use reviewed Terraform plans. Keep the original non-null Terraform `release_image` after bootstrap: Jenkins owns later task revisions, and Terraform ignores changes to the service task definition. Recreate ignored configuration and secrets on a fresh checkout; do not commit keys, tfvars, state, Vault files or saved plans.

## Local application checks

```bash
npm ci
npm run check
npm test -- --ci --runInBand
npm start
# From another terminal:
curl --fail http://127.0.0.1:3000/health
```

The production container runs as UID/GID 10001 and listens on port 3000. Its health endpoint returns `{"service":"jenkins-webapp","status":"ok"}`.

## Limits and historical material

This is a cost-constrained lab with one desired application task. It is not a highly available service. The shared CI instance is below SonarQube's published production sizing; successful demos do not establish production reliability. The client-restricted ALB listener uses demo HTTP under the documented exception, with no sensitive application traffic.

CloudWatch notifications are not configured or tested. Host replacement/draining, live scanner-error injection and a synthetic secret-rejection exercise are not claimed. Older August screenshots, `architecture.drawio`, `requirements.md` and `docs/RUNBOOK.md` describe the previous GHCR/SSH-to-EC2 project, not this ECS release. Current assignment evidence is separated in the index.

Use [the teardown guidance](docs/PHASE_8_9_RUNBOOK.md#eventual-teardown) after preserving evidence and reviewing resource ownership. Cleanup of old revisions is separate from destroying the running lab.
