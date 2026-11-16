# Security policy and local scans

The assignment requires SAST, SCA, image scanning, secret detection and an image SBOM. All release gates must complete successfully before publication. `Jenkinsfile` configures scans on pushes and permits publication/deployment only for an explicitly approved manually started build. The complete release path was verified in Jenkins build 12; public webhook delivery remains unverified. See the [release runbook](../docs/SECURE_ECS_PIPELINE.md) and [submission evidence](../evidence/README.md).

## Gate policy

| Gate | Scope and blocking condition | Report |
| --- | --- | --- |
| SonarQube SAST | `src` and `test` as configured in `sonar-project.properties`. Wait for analysis and the configured quality gate; additionally query unresolved project-wide `VULNERABILITY` issues with Sonar severity `BLOCKER` or `CRITICAL`, mapped here to the assignment's Critical/High. Any issue blocks. Verify mapping and API compatibility with the chosen server before release. | `sonarqube-quality-gate.json`, `sonarqube-issues.json`; `sonarqube-failure.json` on scanner failure. The raw `sonarqube-analysis.log` is local and must not be archived. |
| Snyk SCA | `package-lock.json`, including development dependencies (`--dev`). Block High and Critical regardless of whether a fix exists. Snyk token and connectivity required; no `--fail-on` fixability filter. | `snyk.json` |
| Gitleaks | Git history reachable through local refs and the current working tree, including untracked files. Any secret finding blocks. Standard rules are extended with path exclusions for generated files, dependencies and `.git`. | `gitleaks-history.json`, `gitleaks-worktree.json`, with matches redacted |
| Trivy filesystem | Source dependency manifests/lockfiles, excluding installed `node_modules` and generated reports; High/Critical including unfixed block. | `trivy-repository.json` |
| Trivy misconfiguration | Repository configuration including Dockerfile and Terraform; High/Critical findings block. Generated dependencies, Terraform providers and reports are excluded. | `trivy-misconfig.json` |
| Trivy image | OS and language packages in the exact built image; High/Critical including unfixed block. Image secrets of any severity also block. | `trivy-image.json`; `trivy-image-secrets.json` contains only the finding count and scanner exit code. Raw secret findings remain in a temporary file and are removed. |
| Syft | Generate CycloneDX JSON from the exact image; a missing, invalid or empty component inventory blocks. The SBOM is inventory, not a vulnerability gate. | `sbom.cdx.json` |

Every scanner must return success and its expected report must exist and parse; missing credentials, unavailable tools, analysis errors and malformed reports fail closed. Resolve findings rather than adding broad exclusions. Scanner versions/digests and advisory database dates must be pinned and recorded before Jenkins release integration. SonarQube's built-in gate may address only new code: the separate project-wide issue check is required too. Review applicable security hotspots manually; they are not equivalent to confirmed vulnerabilities.

## Local execution

### Bounded infrastructure configuration exceptions

The CI and ECS demo retain public addressing to avoid NAT infrastructure. Subnets no longer automatically assign public IPs: the CI instance and ECS host launch template explicitly opt in. The application task security group has no egress and accepts application traffic only from the ALB.

The following resource-local Trivy exceptions expire on **2026-12-10**. They apply to configuration design rules only; vulnerability and secret gates are unchanged. Expiry requires removing the exception or explicitly reviewing the design again.

| Resource | Rule | Reason and limits |
| --- | --- | --- |
| `infra/ci/main.tf`, `aws_vpc_security_group_egress_rule.web` | AVD-AWS-0104 | Dynamic public package/scanner registry destinations; TCP 80/443 only, SSH ingress limited to administrator `/32`, Jenkins/SonarQube bound to loopback. |
| `infra/ecs-ec2/network.tf`, `aws_vpc_security_group_egress_rule.host_https` | AVD-AWS-0104 | Dynamic ECS/ECR/CloudWatch/registry endpoints over TCP 443 only; no host management ingress and no task egress. |
| `infra/ecs-ec2/service.tf`, `aws_lb.app` | AVD-AWS-0053 | A public demo application endpoint is intentional. Ingress is restricted to declared client IPv4 CIDRs; `0.0.0.0/0` is rejected by variable validation. |
| `infra/ecs-ec2/service.tf`, `aws_lb_listener.http` | AVD-AWS-0054 | Operator approved demo HTTP on 2026-11-10. Limited to the sample application and approved client CIDRs; no credentials or private data may use this listener. Jenkins/SonarQube access remains through SSH tunnels. Replace with HTTPS for use beyond this demo. |

The ALB now drops invalid header fields. The HTTP exception is confined to the named demo listener and expires on 2026-12-10; it does not waive transport encryption for other listeners or services.

Install compatible `sonar-scanner`, `snyk`, `gitleaks`, `trivy`, `syft`, `curl` and `jq` executables locally. Start SonarQube on a local-only address and configure `SONAR_HOST_URL` and `SONAR_TOKEN` privately. Set `SNYK_TOKEN` privately using an authorized Snyk account. Do not put token values into commands, documents or Git. Snyk sends dependency metadata to its service; SonarQube analysis goes to the configured server. Use only the approved local SonarQube instance. The verified Jenkins runs used managed credentials; a fresh environment requires its own private credential setup.

```bash
scripts/security-scan.sh secrets
scripts/security-scan.sh sast
scripts/security-scan.sh sca
scripts/security-scan.sh repository
scripts/security-scan.sh misconfig
IMAGE_REF=mod9-baseline:local scripts/security-scan.sh image
IMAGE_REF=mod9-baseline:local scripts/security-scan.sh image-secrets
IMAGE_REF=mod9-baseline:local scripts/security-scan.sh sbom
```

Reports default to ignored `security-reports/`; set `SECURITY_REPORT_DIR` to a unique local directory per run. Treat reports and scanner logs as sensitive even when secret matches are redacted. Inspect and sanitize before copying to `evidence/` or archiving. Capture tool versions, advisory database timestamps, commit SHA, run identifier, image ID/digest, report names and gate outcomes alongside each run. For deployed releases, add ECR digest and task definition revision and confirm both refer to the scanned image. Never rely on reports from an earlier invocation when the current command fails; each gate replaces its own report.

## Controlled verification

Use a disposable copy of the manifests and lockfile with a scanner-confirmed High/Critical dependency; run the real SCA gate and retain a sanitized failing report. Verify no publish/deploy stage ran, then repair the lockfile and repeat. Do not commit or deploy the vulnerable fixture. Also simulate a scanner service/tool failure and prove the gate exits nonzero and preserves any generated report. Test secret detection with a synthetic fixture in a disposable directory, never a real credential. Jenkins must archive sanitized reports in a `post { always { ... } }` path even on gate failure; the local script alone does not provide Jenkins artifact retention.

## Status

Verified on 2026-11-11/12: the [CI security playbook](../docs/CI_SECURITY_SETUP.md) configured pinned scanners, managed credentials and the overall security rating A gate. [Build 11](../evidence/20261111-jenkins-build-11-dependency-rejected.md) rejected the injected High-severity Snyk finding `SNYK-JS-BRACES-19963945`; downstream image and release stages were skipped. [Build 12](../evidence/20261112-jenkins-build-12-remediated.md) restored Jest 30.3.0, passed the complete pipeline and deployed ECS revision `mod9-ecs-app:6`.

The [archived reports](../evidence/submission/build-12/reports/) include the passing SonarQube gate and whole-project issue query, Snyk and Trivy reports, empty Gitleaks reports, the image-secret summary and the CycloneDX SBOM. These runs verified Snyk authentication and SonarQube analysis/API compatibility. The rating A condition supplements the project-wide vulnerability check. Results apply to the recorded source commit and image digest; every later release must run the gates again.

Public webhook delivery, notification delivery, host replacement/draining, live scanner-error injection and a synthetic secret-rejection exercise remain unverified, as disclosed in the [evidence limits](../evidence/README.md#limits). Passing reports do not establish those additional behaviors.
