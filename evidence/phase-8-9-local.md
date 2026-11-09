# Phase 8–9 local evidence

Recorded 2026-11-04. No Jenkins or AWS operations were performed.

`PATH=/tmp/mod9-review-tools:$PATH TRIVY_CACHE_DIR=/tmp/mod9-review-cache python3 scripts/rehearse-repository-gate.py` ran Trivy 0.73.0 using database schema 2, updated 2026-11-04 07:16:25 UTC. Both scans used that same cached database. The current working-tree lockfile (SHA-256 `c41b53d44144fb42900d1fa66188dda7258480bbd5282ec3610c79427a915d2f`, HEAD `c6000085a00ddb372ce252abd2cbb4a79ced0468`) passed with exit 0 and no High/Critical findings. The historical `9662bf8` lockfile (SHA-256 `547688379110c5814efa01667d90c1451d9f0e09b519f42c5a9cca4a723daef8`) was rejected with exit 1 and five findings: CVE-2026-102276, CVE-2026-102278, CVE-2026-111181, CVE-2026-84375 and CVE-2026-90711. This is a dependency gate rehearsal, not a full clean pipeline or live deployment demonstration.

The offline retention helper's four unit tests passed. Existing deploy helper tests (5) and security gate tests (6) passed. Terraform formatting and provider validation passed; provider validation required running outside the filesystem sandbox. No AWS plan was run and no lifecycle policy was changed in AWS. Inventory completeness, actual cleanup and post-cleanup service health remain unverified.
