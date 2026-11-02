#!/usr/bin/env bash
# One local gate per invocation; non-zero always means do not release.
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
reports=${SECURITY_REPORT_DIR:-"$root/security-reports"}
mkdir -p "$reports"
reports=$(cd -- "$reports" && pwd)
case "${1:-}" in
  sast)
    : "${SONAR_HOST_URL:?Set SONAR_HOST_URL to your local SonarQube URL}"
    : "${SONAR_TOKEN:?Set SONAR_TOKEN in your environment; do not commit it}"
    command -v sonar-scanner >/dev/null
    command -v curl >/dev/null
    command -v jq >/dev/null
    rm -f "$reports/sonarqube-analysis.log" "$reports/sonarqube-quality-gate.json" "$reports/sonarqube-issues.json"
    # Keep a log even if analysis or the quality gate fails.
    sonar-scanner -Dsonar.qualitygate.wait=true > "$reports/sonarqube-analysis.log" 2>&1 || { echo 'SonarQube analysis/quality gate failed; inspect the local report.' >&2; exit 1; }
    # Request open security vulnerabilities for the entire project, not just new code.
    # Curl reads authentication from standard input so the token is not an argument.
    [[ "$SONAR_TOKEN" =~ ^[a-zA-Z0-9_.-]+$ ]] || { echo 'Unsupported Sonar token format' >&2; exit 2; }
    printf 'user = "%s:"\n' "$SONAR_TOKEN" | curl --fail --silent --show-error --config - \
      --get --data-urlencode 'projectKey=mod9-jenkins-webapp' \
      "${SONAR_HOST_URL%/}/api/qualitygates/project_status" > "$reports/sonarqube-quality-gate.json"
    jq -e '.projectStatus.status == "OK"' "$reports/sonarqube-quality-gate.json" >/dev/null
    printf 'user = "%s:"\n' "$SONAR_TOKEN" | curl --fail --silent --show-error --config - \
      --get --data-urlencode 'componentKeys=mod9-jenkins-webapp' \
      --data-urlencode 'types=VULNERABILITY' --data-urlencode 'resolved=false' \
      --data-urlencode 'severities=BLOCKER,CRITICAL' --data-urlencode 'ps=1' \
      "${SONAR_HOST_URL%/}/api/issues/search" > "$reports/sonarqube-issues.json"
    jq -e '(.total | type == "number") and (.issues | type == "array") and (.total == 0)' "$reports/sonarqube-issues.json" >/dev/null
    ;;
  sca)
    : "${SNYK_TOKEN:?Set SNYK_TOKEN in your environment; do not commit it}"
    command -v snyk >/dev/null
    rm -f "$reports/snyk.json"
    snyk test --dev --severity-threshold=high --json-file-output="$reports/snyk.json"
    jq -e 'type == "object" and (.vulnerabilities | type == "array") and ([.vulnerabilities[] | select(.severity == "high" or .severity == "critical")] | length == 0)' "$reports/snyk.json" >/dev/null
    ;;
  secrets)
    command -v gitleaks >/dev/null
    # Scan local Git history and the working tree; redact every finding.
    command -v jq >/dev/null
    rm -f "$reports/gitleaks-history.json" "$reports/gitleaks-worktree.json"
    gitleaks git "$root" --log-opts="--all" --redact=100 --report-format=json --report-path="$reports/gitleaks-history.json" --exit-code=1
    jq -e 'type == "array" and length == 0' "$reports/gitleaks-history.json" >/dev/null
    gitleaks dir "$root" --redact=100 --report-format=json --report-path="$reports/gitleaks-worktree.json" --exit-code=1
    jq -e 'type == "array" and length == 0' "$reports/gitleaks-worktree.json" >/dev/null
    ;;
  repository)
    command -v trivy >/dev/null
    rm -f "$reports/trivy-repository.json"
    trivy fs --scanners vuln --include-dev-deps --skip-dirs node_modules --skip-dirs security-reports --severity HIGH,CRITICAL --exit-code 1 --format json --output "$reports/trivy-repository.json" .
    jq -e 'type == "object" and (.SchemaVersion | type == "number") and (.ArtifactName | type == "string") and (.Results | type == "array" or . == null)' "$reports/trivy-repository.json" >/dev/null
    ;;
  image)
    : "${IMAGE_REF:?Set IMAGE_REF to the local image to scan}"
    command -v trivy >/dev/null
    rm -f "$reports/trivy-image.json"
    trivy image --scanners vuln --severity HIGH,CRITICAL --exit-code 1 --format json --output "$reports/trivy-image.json" "$IMAGE_REF"
    jq -e 'type == "object" and (.SchemaVersion | type == "number") and (.ArtifactName | type == "string") and (.Results | type == "array" or . == null)' "$reports/trivy-image.json" >/dev/null
    ;;
  sbom)
    : "${IMAGE_REF:?Set IMAGE_REF to the local image to catalog}"
    command -v syft >/dev/null
    rm -f "$reports/sbom.cdx.json"
    syft "$IMAGE_REF" -o cyclonedx-json="$reports/sbom.cdx.json"
    jq -e '.bomFormat == "CycloneDX" and (.specVersion | type == "string") and (.components | type == "array") and (.components | length > 0)' "$reports/sbom.cdx.json" >/dev/null
    ;;
  *) echo "Usage: $0 {sast|sca|secrets|repository|image|sbom}" >&2; exit 2 ;;
esac
