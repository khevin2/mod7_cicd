#!/usr/bin/env bash
set -Eeuo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repository_root"

required_files=(
  README.md
  docs/RUNBOOK.md
  docs/observability-security-report.md
  architecture.drawio
  prometheus.yml
  monitoring/grafana/dashboards/webapp-observability.json
  evidence/README.md
)
for file in "${required_files[@]}"; do test -s "$file"; done

node -e "JSON.parse(require('fs').readFileSync('monitoring/grafana/dashboards/webapp-observability.json', 'utf8'))"
node -e "const fs=require('fs'); const xml=fs.readFileSync('architecture.drawio','utf8'); if (!xml.startsWith('<mxfile') || !xml.includes('</mxfile>')) process.exit(1)"

for file in README.md docs/RUNBOOK.md docs/observability-security-report.md evidence/README.md; do
  if rg -n 'COMPLETION\.md' "$file"; then
    echo "Submission document references the private tracker: $file" >&2
    exit 1
  fi
done

if git ls-files | rg -n '(^COMPLETION\.md$|(^|/)terraform\.tfstate|\.tfplan$|(^|/)hosts\.yml$|(^|/)keys/)' ; then
  echo 'A sensitive local artifact is tracked.' >&2
  exit 1
fi

echo 'Phase 12 static submission checks: passed'
if test -f docs/observability-security-report.pdf; then
  page_count=$(node -e "const fs=require('fs');const pdf=fs.readFileSync('docs/observability-security-report.pdf').toString('latin1');process.stdout.write(String((pdf.match(/\\/Type \\/Page\\b/g)||[]).length))")
  test "$page_count" = 2
  echo 'Two-page PDF structure: passed'
else
  echo 'PDF rendering and visual inspection remain separate checks.'
fi
