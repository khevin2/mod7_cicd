#!/usr/bin/env bash
set -Eeuo pipefail

# This is deliberately a repository-only gate. It neither contacts AWS nor
# starts a server; live verification remains dependent on the approved Phase 10
# deployment and the controlled procedure in docs/RUNBOOK.md.
repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

for file in "$repository_root/src/fault-injection.js" "$repository_root/src/app.js" "$repository_root/src/server.js" "$repository_root/docs/RUNBOOK.md"; do
  test -f "$file"
done

rg -Fq "FAULT_INJECTION_ENABLED" "$repository_root/src/server.js"
rg -Fq "'127.0.0.1'" "$repository_root/src/server.js"
rg -Fq "app.get('/_phase11/fault'" "$repository_root/src/app.js"
rg -Fq "faultInjection?.isEnabled()" "$repository_root/src/app.js"

# The controller must not be mapped through the normal application deployment.
if rg -n -- "-p .*9465|FAULT_INJECTION_ENABLED=true" "$repository_root/Jenkinsfile"; then
  echo "The Phase 11 controller must not be published or enabled by normal CI deployment." >&2
  exit 1
fi

rg -Fq 'Controlled Phase 11 fault test' "$repository_root/docs/RUNBOOK.md"
rg -Fq 'FAULT_INJECTION_ENABLED=true' "$repository_root/docs/RUNBOOK.md"
rg -Fq '/_phase11/disable' "$repository_root/docs/RUNBOOK.md"

echo 'Phase 11 repository preflight: passed'
echo 'Fault injection: disabled by default; control listener is loopback-only and not published by Jenkins'
echo 'Live boundary: do not run the controlled test until Phase 10 is complete and the exact deployment is approved'
