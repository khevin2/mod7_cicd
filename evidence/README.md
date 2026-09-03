# Submission evidence index

This directory contains sanitized evidence from commands and checks actually
executed for this lab. Configuration explains intended behavior; it is not a
substitute for runtime evidence. The Phase 12 report links only to dated
records below; controlled traffic and synthetic findings are labeled as such.

## Redaction and retention

Included copies omit credential values, tokens, passwords, private keys, AWS
account IDs, unnecessary EC2 identifiers/public addresses, email addresses, and
unrelated terminal/browser content. Original captures stay outside the repository
under ignored raw/private storage. The sanitized screenshot set under screenshots/
documents Jenkins build #4, GHCR, EC2 state, and public browser accessibility.

## Rubric-to-evidence map

| Requirement | Direct evidence | Current status |
| --- | --- | --- |
| Project 6 source and read-only baseline | 20260827-source-baseline.txt; 20260827-read-only-preflight.txt | Verified 2026-08-27; prior lab stack absent, no cloud mutation. |
| Project 6 ownership and cleanup boundary | 20260827-resource-ownership.md | Pre-existing, referenced, rejected, and lab-created resources classified. |
| Project 6 decisions and cost impact | 20260827-cost-and-decisions.md | Inputs resolved and fixed/usage-priced cost drivers documented. |
| Phase 3 hardened Compose and secret-safe definitions | 20260827-phase3-static-validation.txt; current monitoring/, Ansible, and Terraform module | Static controls verified 2026-08-27; newest official stable images are approved for this lab with a documented exception for known fixable Trivy HIGH findings (no CRITICAL findings). |
| Phase 4 monitoring Terraform composition | 20260828-phase4-static-validation.txt; current infra/live and monitoring modules | Structural controls verified 2026-08-28; provider-backed validation, IaC scan, saved plans, and any apply remain pending. |
| Phase 6 encrypted CloudTrail archive | 20260828-phase6-live-verification.txt; current infra/modules/cloudtrail_archive | Live trail delivery, digest, encryption, public-access block, policy restrictions, lifecycle, and lab ownership verified 2026-08-28. |
| Phase 7 GuardDuty detector and synthetic finding | 20260828-phase7-guardduty-detector.txt; 20260828-phase7-sample-finding.txt | Verified 2026-08-28 in eu-north-1; tagged detector enabled, optional plans disabled, and AWS sample marker confirmed. |
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
| Runbook and reproducibility | ../README.md; ../docs/RUNBOOK.md | Deployment, verification, diagnosis, alert, rollback, and cleanup procedures are documented. |
| Local Phase 11 quality and security review | 20260821-phase11-local-quality-review.md | Clean-checkout tests, no-cache build, static review, and limitations recorded. |
| Local Trivy repository and image gates | 20260822-trivy-local-security-review.md | Source and hardened image gates passed locally; fresh Jenkins execution remains pending. |
| Phase 11 live alert and recovery verification | 20260830-phase11-live-verification.md | Controlled Pending-to-Firing-to-Resolved test, CloudWatch correlation, restored digest, and four healthy scrape targets verified 2026-08-30. |
| Module 10 read-only preflight | mod10/phase5-readonly-preflight.md | Read-only topology, private-OTLP exposure, log metadata, and CPU review refreshed 2026-09-03; live trace/alert evidence remains pending. |
| Module 10 report | ../docs/observability-security-report.md; ../docs/observability-security-report.pdf | Two-page report distinguishes local implementation proof from pending user-operated live acceptance evidence. |

## Evidence limitations

- The listed Jenkins build captures predate the current Trivy and Runtime Cleanup stages; a fresh successful build with archived non-secret reports remains required for that specific CI claim.
- Current Phase 11 verification is recorded as sanitized text. Add dashboard, alert, and CloudWatch screenshots only after review and redaction; do not fabricate screenshots from configuration.
- Module 10 requires separate, deployed Jaeger/exemplar/CloudWatch trace correlation and both 10-minute alert lifecycles. The report deliberately does not treat prior Phase 11 evidence as proof of these requirements.

## Captured files

- 20260827-source-baseline.txt — exact source alignment and local tool limitations.
- 20260827-read-only-preflight.txt — sanitized current AWS/GitHub/runtime absence checks.
- 20260827-resource-ownership.md — resource ownership and teardown exclusions.
- 20260827-cost-and-decisions.md — approved inputs and point-in-time AWS cost impact.
- 20260827-phase3-static-validation.txt — daemon-free Compose/security structure and syntax checks; runtime limitations explicit.
- 20260828-phase4-static-validation.txt — monitoring and peering Terraform structural checks; provider-validation limitation explicit.
- 20260828-phase7-guardduty-detector.txt — sanitized enabled-detector, ownership-tag, and optional-feature status.
- 20260828-phase7-sample-finding.txt — sanitized AWS-generated synthetic finding fields.
- 20260828-phase6-live-verification.txt — sanitized CloudTrail, S3, KMS, ownership, lifecycle, and fresh-delivery verification.
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
- 20260830-phase11-live-verification.md — sanitized controlled alert lifecycle, log correlation, and restored runtime verification.
- screenshots/ — sanitized build #4, credential-ID, GHCR, EC2, and public browser captures.
