# Jenkins build 1: dependency gate blocked the build

Read-only verification on 2026-11-10 of the operator-started `mod9-secure-ecs/1` build, executed on 2026-11-09.

- Source commit: `c06817da5a1b137ba70be3bee0c18bcf2ab96434`.
- Both Git-history and working-tree Gitleaks scans reported no leaks.
- Application tests: one suite, four tests passed.
- Archived `sonarqube-quality-gate.json`: `projectStatus.status=OK`.
- Archived `sonarqube-issues.json`: `total=0` for the configured whole-project vulnerability query.
- Archived `snyk.json`: High-severity `SNYK-JS-BRACES-19963945`, package `braces@3.0.3`, introduced through `jest@29.7.0`.
- The dependency stage failed; image build, image scan/SBOM, publication and deployment stages were skipped.
- Jenkins retained the test results and security reports. Final build result: `FAILURE`.

This provides live evidence of SAST and secret-scan success for this revision and a dependency finding blocking downstream stages. It does not establish a passing SCA gate, image security, scanner-error handling, or deployment success.

Snyk's build output recommends upgrading Jest to `30.3.0`. The [Snyk advisory](https://security.snyk.io/vuln/SNYK-JS-BRACES-19963945) lists no fixed braces version; remediation must remove the affected dependency path rather than ignoring the finding. A new build must validate the updated dependency tree.
