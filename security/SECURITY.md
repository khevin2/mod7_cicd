# Security policy and local scans

The assignment requires SAST, SCA, image scanning, secret detection and an image SBOM. All release gates must complete successfully before publication. `Jenkinsfile` runs scans on pushes and permits publication/deployment only for an explicitly approved manually started build; the complete gates and Jenkins integration still require live validation before any release. See `docs/SECURE_ECS_PIPELINE.md`.

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

Install compatible `sonar-scanner`, `snyk`, `gitleaks`, `trivy`, `syft`, `curl` and `jq` executables locally. Start SonarQube on a local-only address and configure `SONAR_HOST_URL` and `SONAR_TOKEN` privately. Set `SNYK_TOKEN` privately when a Snyk account is available. Do not put token values into commands, documents or Git. Snyk sends dependency metadata to its service; SonarQube analysis goes to the configured server. Use only the approved local SonarQube instance. No Snyk scan has been authorized or run until account/access is settled.

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

The commands and policy are draft implementations pending real tool validation. In particular, Snyk access and a local SonarQube installation are unresolved. The tracked policy does not claim a clean SAST, SCA, secret, image scan or SBOM until real reports are checked.
