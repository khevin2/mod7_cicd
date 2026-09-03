#!/usr/bin/env bash
set -Eeuo pipefail

# This is deliberately a repository-only gate. It neither contacts AWS nor
# starts a server; it does not substitute for the live evidence collected using
# the controlled procedure in docs/RUNBOOK.md.
repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

command -v rg >/dev/null

for file in "$repository_root/src/app.js" "$repository_root/src/server.js" "$repository_root/docs/RUNBOOK.md"; do
  test -f "$file"
done

! rg -Fq "app.get('/_phase11/fault'" "$repository_root/src/app.js"
! rg -Fq '/_phase10/' "$repository_root/src/app.js" "$repository_root/src/server.js"
rg -Fq "app.post('/test'" "$repository_root/src/app.js"
rg -Fq "value === 'error'" "$repository_root/src/app.js"
rg -Fq "value === 'latency'" "$repository_root/src/app.js"
rg -Fq 'TEST_LATENCY_MS = 400' "$repository_root/src/app.js"

# The controller must not be mapped through the normal application deployment.
if rg -n -- "-p .*9465|CONTROLLED_TEST_ENABLED=true|FAULT_INJECTION_ENABLED=true" "$repository_root/Jenkinsfile"; then
  echo "No temporary test controller may be published or enabled by normal CI deployment." >&2
  exit 1
fi

rg -Fq 'Module 10 controlled correlation test' "$repository_root/docs/RUNBOOK.md"
rg -Fq 'POST /test' "$repository_root/docs/RUNBOOK.md"

echo 'Module 10 single test-route repository preflight: passed'
echo 'Error and fixed-latency test capabilities share POST /test; no controller is present'
echo 'Live boundary: collect Module 10 evidence only from the approved deployed immutable digest'
