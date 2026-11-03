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
    rm -f "$reports/sonarqube-analysis.log" "$reports/sonarqube-quality-gate.json" "$reports/sonarqube-issues.json" "$reports/sonarqube-failure.json"
    # The raw log can contain sensitive details and is never archived. Write
    # only a fixed-category diagnostic to the JSON artifacts on failure.
    if sonar-scanner -Dsonar.qualitygate.wait=true > "$reports/sonarqube-analysis.log" 2>&1; then
      :
    else
      scan_status=$?
      category=analysis_error
      if grep -Eiq 'QUALITY GATE.*FAIL|QUALITY GATE STATUS: ERROR' "$reports/sonarqube-analysis.log"; then
        category=quality_gate_failed
      elif grep -Eiq 'timed? out|timeout' "$reports/sonarqube-analysis.log"; then
        category=timeout
      elif grep -Eiq 'not authorized|unauthorized|authentication|HTTP (401|403)' "$reports/sonarqube-analysis.log"; then
        category=authentication_error
      fi
      jq -n --arg category "$category" --argjson exitCode "$scan_status" \
        '{scanner:"sonarqube", status:"failed", category:$category, exitCode:$exitCode, diagnostic:"Inspect the restricted local scanner log for details."}' \
        > "$reports/sonarqube-failure.json"
      echo "SonarQube analysis failed ($category); see the sanitized failure report." >&2
      exit "$scan_status"
    fi
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
  misconfig)
    command -v trivy >/dev/null
    command -v jq >/dev/null
    rm -f "$reports/trivy-misconfig.json"
    trivy fs --scanners misconfig --skip-dirs node_modules --skip-dirs security-reports --skip-dirs build-metadata --skip-dirs '**/.terraform' --severity HIGH,CRITICAL --exit-code 1 --format json --output "$reports/trivy-misconfig.json" .
    jq -e 'type == "object" and (.SchemaVersion | type == "number") and (.ArtifactName | type == "string") and (.Results | type == "array" or . == null)' "$reports/trivy-misconfig.json" >/dev/null
    ;;
  image)
    : "${IMAGE_REF:?Set IMAGE_REF to the local image to scan}"
    command -v trivy >/dev/null
    rm -f "$reports/trivy-image.json"
    trivy image --scanners vuln --severity HIGH,CRITICAL --exit-code 1 --format json --output "$reports/trivy-image.json" "$IMAGE_REF"
    jq -e 'type == "object" and (.SchemaVersion | type == "number") and (.ArtifactName | type == "string") and (.Results | type == "array" or . == null)' "$reports/trivy-image.json" >/dev/null
    ;;
  image-secrets)
    : "${IMAGE_REF:?Set IMAGE_REF to the local image to scan}"
    command -v trivy >/dev/null
    command -v jq >/dev/null
    rm -f "$reports/trivy-image-secrets.json"
    private_dir=$(mktemp -d)
    raw_report="$private_dir/report.json"
    trap 'rm -f "$raw_report"; rmdir "$private_dir"' EXIT
    if trivy image --scanners secret --exit-code 1 --format json --output "$raw_report" "$IMAGE_REF"; then
      scan_status=0
    else
      scan_status=$?
    fi
    # Only a count is retained: raw findings include matched secret values.
    if [[ -s "$raw_report" ]] && jq -e 'type == "object" and (.SchemaVersion | type == "number") and (.ArtifactName | type == "string") and (.Results | type == "array" or . == null)' "$raw_report" >/dev/null; then
      jq --argjson exitCode "$scan_status" '{scanner:"trivy-image-secrets", exitCode:$exitCode, findingCount:([.Results[]?.Secrets[]?] | length)}' "$raw_report" > "$reports/trivy-image-secrets.json"
    else
      jq -n --argjson exitCode "$scan_status" '{scanner:"trivy-image-secrets", exitCode:$exitCode, status:"invalid_or_missing_report"}' > "$reports/trivy-image-secrets.json"
      echo 'Image secret scan did not produce a valid report.' >&2
      exit 1
    fi
    if (( scan_status != 0 )); then
      exit "$scan_status"
    fi
    jq -e '.findingCount == 0' "$reports/trivy-image-secrets.json" >/dev/null
    ;;
  sbom)
    : "${IMAGE_REF:?Set IMAGE_REF to the local image to catalog}"
    command -v syft >/dev/null
    rm -f "$reports/sbom.cdx.json"
    syft "$IMAGE_REF" -o cyclonedx-json="$reports/sbom.cdx.json"
    jq -e '.bomFormat == "CycloneDX" and (.specVersion | type == "string") and (.components | type == "array") and (.components | length > 0)' "$reports/sbom.cdx.json" >/dev/null
    ;;
  *) echo "Usage: $0 {sast|sca|secrets|repository|misconfig|image|image-secrets|sbom}" >&2; exit 2 ;;
esac
