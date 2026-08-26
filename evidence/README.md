# Submission evidence index

This directory contains sanitized evidence from commands and checks actually
executed for this lab. Configuration explains intended behavior; it is not a
substitute for runtime evidence.

## Redaction and retention

Included copies omit credential values, tokens, passwords, private keys, AWS
account IDs, unnecessary EC2 identifiers/public addresses, email addresses, and
unrelated terminal/browser content. Original captures stay outside the repository
under ignored raw/private storage. The sanitized screenshot set under screenshots/
documents Jenkins build #4, GHCR, EC2 state, and public browser accessibility.

## Rubric-to-evidence map

| Requirement | Direct evidence | Current status |
| --- | --- | --- |
| Git/GitHub, Terraform, AWS CLI, Jenkins LTS, SSH readiness | 20260820-prerequisite-checklist.md | Verified 2026-08-20; identity details redacted. |
| Jenkins LTS, plugins, NodeJS24, Docker/Git/SSH | 20260821-phase5-jenkins-readiness.txt | Jenkins 2.568.2 and required tools/plugins recorded. |
| Amazon Linux 2023 target and credential IDs | 20260821-phase7-readiness.txt | Target and protected IDs registry_creds/ec2_ssh checked without values. |
| Express install, syntax, tests, endpoints | 20260820-phase1-tests.txt; 20260820-phase1-health-check.txt | Four tests passed. |
| Container build and runtime checks | 20260820-phase2-docker-build.txt; 20260820-phase2-image-inspect.txt; 20260820-phase2-container-smoke.txt | Non-root, healthy local container verified. |
| Initial EC2 host inventory | 20260821-phase4-ec2-host.txt | Historical Amazon Linux 2 evidence only; not proof of AL2023 provisioning. |
| Jenkins six required stages and final success | 20260821-phase7-build4-console.txt; 20260821-phase7-readiness.txt | Build #4 SUCCESS from Checkout through Deploy; it predates the current Trivy and Runtime Cleanup stages. |
| Trivy repository and image security gates | Current Jenkinsfile; fresh Jenkins evidence pending | Implemented with a pinned scanner image; execution is not yet claimed. |
| Immutable image/digest traceability | 20260821-phase7-build4-console.txt; 20260821-phase8-deployed-verification.txt | Same digest recorded for push, deployment, and container. |
| Public root/health accessibility | 20260821-phase8-deployed-verification.txt; screenshots/public-browser-root.png | Terminal and browser checks captured HTTP 200 for build #4. |
| Runtime cleanup and disk capacity | 20260821-phase9-runtime-cleanup.txt | Host cleanup verified; new Jenkins cleanup stage needs a successful run. |
| Runbook and reproducibility | ../README.md; ../docs/RUNBOOK.md | Documentation implemented; recheck commands in Phase 11. |
| Local Phase 11 quality and security review | 20260821-phase11-local-quality-review.md | Clean-checkout tests, no-cache build, static review, and limitations recorded. |
| Local Trivy repository and image gates | 20260822-trivy-local-security-review.md | Source and hardened image gates passed locally; fresh Jenkins execution remains pending. |

## Remaining captures

- A fresh successful Jenkins build containing both Trivy stages and Runtime Cleanup.
- Archived trivy-repository.json and trivy-image.json from that successful build.
- A current public health check after that build.

## Captured files

- 20260820-prerequisite-checklist.md — prerequisite and tool checks.
- 20260820-phase1-tests.txt, 20260820-phase1-health-check.txt — app tests and local checks.
- 20260820-phase2-docker-build.txt, 20260820-phase2-image-inspect.txt, 20260820-phase2-container-smoke.txt — container checks.
- 20260821-phase4-ec2-host.txt — historical Amazon Linux 2 host evidence.
- 20260821-phase5-jenkins-readiness.txt — Jenkins readiness.
- 20260821-phase7-readiness.txt, 20260821-phase7-build4-console.txt — credential IDs and six-stage success.
- 20260821-phase8-deployed-verification.txt — digest and public terminal HTTP verification.
- 20260821-phase9-runtime-cleanup.txt — constrained host cleanup and disk capacity.
- 20260821-phase11-local-quality-review.md — clean-checkout, container, source, security, and documentation checks with limitations.
- 20260822-trivy-local-security-review.md — local Trivy findings, remediation, final gates, and limitations.
- screenshots/ — sanitized build #4, credential-ID, GHCR, EC2, and public browser captures.
