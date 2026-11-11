# Jenkins build 5: passing scan-only baseline

Read-only verification on 2026-11-11 of the operator-started `mod9-secure-ecs/5` build confirmed final result `SUCCESS`.

- Commit: `5c4ecc5c63a12856e2f73a4cf3ab1bc47eff776f`.
- Scanned image ID: `sha256:4c1935632b0f84867a7781b8861277d12dfc0fec5ffea9b84db9ead854df5a22`.
- Gitleaks history and working tree reports: zero findings.
- SonarQube gate: `OK`; configured whole-project vulnerability query: zero matching issues.
- Snyk report: zero returned vulnerabilities at the configured High/Critical threshold, including development dependencies.
- Trivy repository and image vulnerability reports: zero returned findings at the configured High/Critical threshold, including unfixed vulnerabilities.
- Trivy configuration report: zero returned findings under the documented, resource-specific demo policy exceptions.
- Trivy image secret report: exit code 0 and zero findings.
- CycloneDX SBOM: valid declared format with 242 inventoried components.

The report JSON files and SBOM were read from this build's archived artifacts. This is a passing scan-only baseline, not an ECS deployment or ECR publication. Live scanner-error rejection, webhook behavior, deployment, monitoring, rollback and cleanup acceptance evidence remain outstanding. Prior builds 1 and 4 provide real dependency/image vulnerability rejection evidence.
