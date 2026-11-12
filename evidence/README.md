# Secure ECS pipeline submission evidence

The current assignment is [Secure CI-CD Pipeline.md](../Secure%20CI-CD%20Pipeline.md). The November evidence below concerns ECR/ECS on EC2. August screenshots and logs belong to the earlier GHCR/SSH project and are retained as historical material only.

## Required deliverables

| Requirement | Submitted evidence |
| --- | --- |
| CI configuration | [Jenkinsfile](../Jenkinsfile), [Ansible playbooks](../ansible/playbooks/), locked plugins/tools in [Ansible vars](../ansible/vars/) |
| SAST | [Build 12 SonarQube gate](submission/build-12/reports/sonarqube-quality-gate.json), [whole-project vulnerability query](submission/build-12/reports/sonarqube-issues.json) |
| SCA | [Build 12 Snyk report](submission/build-12/reports/snyk.json) |
| Image/repository/configuration scans | [Image](submission/build-12/reports/trivy-image.json), [repository](submission/build-12/reports/trivy-repository.json), [configuration](submission/build-12/reports/trivy-misconfig.json) |
| Secret scans | [Git history](submission/build-12/reports/gitleaks-history.json), [worktree](submission/build-12/reports/gitleaks-worktree.json), [image summary](submission/build-12/reports/trivy-image-secrets.json) |
| SBOM | [CycloneDX JSON](submission/build-12/reports/sbom.cdx.json) |
| Versioned ECR release and digest | [Build 12 evidence](20261112-jenkins-build-12-remediated.md), [image digest](submission/build-12/release/image-digest.txt), [source commit](submission/build-12/release/git-commit.txt) |
| Task definition | [Template](../ecs/task-definition.json.tftpl), [rendered input](submission/build-12/release/task-definition.rendered.json), [registered revision](submission/build-12/release/task-definition.registered.json) |
| ECS service update | [Before](submission/build-12/release/service-before.json), [update response](submission/build-12/release/service-update.json), [after](submission/build-12/release/service-after.json) |
| Exact running image and health | [Tasks](submission/build-12/release/running-tasks.json), [ALB target health](submission/build-12/release/target-health.json), [application response](submission/build-12/release/health-response.json) |
| Injected vulnerable dependency blocks pipeline | [Build 11 verification](20261111-jenkins-build-11-dependency-rejected.md), [failed Snyk report](submission/build-11/reports/snyk.json), [unsafe source commit](submission/build-11/release/git-commit.txt) |
| Successful fix | [Build 12 remediation](20261112-jenkins-build-12-remediated.md), passing reports and release records above |
| Automatic failed-release recovery | [Build 10 verification](20261111-build-10-rollback-verified.md), [rollback proof JSON](submission/build-10/release/rollback-demo-result.json) |
| CloudWatch task logging | [Current task startup and 14-day retention](submission/cloudwatch-logs.json) |
| CloudWatch alarm evaluation | [Alarm result JSON](submission/monitoring-demo-result.json), [monitoring context](20261111-build-9-rollback-timing.md); notification delivery is not configured |
| ECR lifecycle and old image/revision cleanup | [Verified cleanup](20261112-cleanup-verified.md), [verification JSON](20261112-cleanup-verified.json), [Terraform policy](../infra/ecs-ec2/registry.tf) |
| Architecture and reproducibility | [README](../README.md), [ECS diagram](../docs/architecture-ecs.drawio), [release runbook](../docs/SECURE_ECS_PIPELINE.md), [CI infrastructure](../infra/ci/README.md), [ECS infrastructure](../infra/ecs-ec2/README.md) |

Console stage/result excerpts: [build 10](submission/build-10/console-stages.txt), [build 11](submission/build-11/console-stages.txt), [build 12](submission/build-12/console-stages.txt).

## Export integrity and interpretation

[Submission manifest](submission/manifest.json) lists SHA-256 checksums for the exported copies. They were read from Jenkins build 10/11/12 archives before artifact rotation. JSON content is preserved except redacted account identifiers, email addresses, network/resource addresses and local paths. Image digests, source commits and vulnerability identifiers remain unchanged. These are evidence copies, not registration/deployment inputs. Raw originals remain in ignored local storage.

Build 11 intentionally failed on HIGH `SNYK-JS-BRACES-19963945`; image/release stages were skipped and revision 3 stayed unchanged. Build 12 fixed the dependency and passed the complete release path to revision 6. Build 10's FAILURE is also intentional: automatic recovery does not make the rejected revision a successful release.

## Limits

The verified runs were manually initiated. Current public webhook delivery, notification delivery, host replacement/draining, live scanner-error injection and a synthetic secret-rejection test are not demonstrated. The service uses one desired task and a client-restricted demo HTTP listener. The shared CI host is a constrained demonstration setup. Older failed findings and diagnostic limitations remain visible in dated evidence rather than being presented as passing runs.
