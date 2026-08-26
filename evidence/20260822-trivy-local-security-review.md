# Local Trivy security review — 2026-08-22

## Scope and tooling

These checks ran locally in WSL with Docker against the source eligible for Git
publication and the image built from the current Dockerfile. No image was pushed,
no Jenkins build was triggered, and no cloud resource was changed.

- Trivy: 0.73.0
- Scanner image: `aquasec/trivy:0.73.0@sha256:7cced7cae583819fc7806d4cbc0dbbc7cad18b99f7d3e235192e6da8c091045c`
- Vulnerability database: `ghcr.io/aquasecurity/trivy-db:2`
- Application image: `jenkins-webapp:trivy-validation-20260822` (local only)

## Findings and remediation

The first repository misconfiguration scan reported three architecture-policy
groups: direct public subnet addressing, port-restricted egress to dynamic public
services, and SSE-S3 rather than a customer-managed KMS key. Each is required or
accepted for this bounded lab design. The exception is scoped to the affected
Terraform resource, documented beside it, and expires on 2027-08-22. No global
ignore file was added.

A full-working-tree secret scan identified the project-local EC2 private key. Git
confirmed that the key is covered by the `keys/` ignore rule and is not tracked.
The key was not read, altered, copied into the source-only scan, or included in an
artifact. The source-only secret gate then passed.

The first image vulnerability gate found fixable HIGH/CRITICAL CVEs in the npm
toolchain bundled with the Node runtime image (`brace-expansion`, `ip-address`,
`tar`, and `undici`). The service needs npm only in the dependency stage, so the
final Docker stage now removes npm and npx. The rebuilt image passed both image
gates.

## Final executed results

| Check | Result |
| --- | --- |
| `npm ci` in pinned Linux Node 24 image | Passed; npm audit reported 0 vulnerabilities. |
| `npm run check` | Passed. |
| `npm test -- --ci --runInBand` | Passed: 1 suite, 4 tests. |
| `docker build --check .` | Passed with no warnings. |
| Hardened application image build | Passed. |
| Hardened image runtime smoke test | Passed: UID/GID 10001, healthy, `/health` returned `status: ok`, and npm/npx were absent. |
| Trivy repository vulnerability and misconfiguration gate | Passed; exit 0 for fixable HIGH/CRITICAL findings. |
| Trivy repository secret gate | Passed on source-only content; exit 0. |
| Trivy image vulnerability gate | Passed; exit 0 for fixable HIGH/CRITICAL findings. |
| Trivy image secret gate | Passed; exit 0. |
| `terraform -chdir=infra fmt -check -recursive` | Passed. |
| `terraform -chdir=infra/bootstrap validate` | Passed. |
| `terraform -chdir=infra/live validate` | Passed. |

## Evidence limitation

This file proves local implementation checks only. A fresh Jenkins run after the
changes are committed and pushed is still required to prove the two Trivy stages,
archived non-secret JSON reports, immutable registry push, deployment, and Runtime
Cleanup in the integrated pipeline.

