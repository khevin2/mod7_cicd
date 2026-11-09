# Security demonstration and retention review

These are local preparations. No Jenkins build, release, cloud cleanup, commit, or push has been performed by this work. The existing `security-scan.sh misconfig` findings and the unvalidated SAST/Snyk integrations must be resolved before a passing baseline is possible. All cloud changes, commits and pushes require the user's explicit permission.

## Phase 8: local rehearsal and future live proof

Install the pipeline's pinned Trivy and jq and populate a trusted, current Trivy vulnerability database in a local cache first. With that cache available, run:

```sh
TRIVY_CACHE_DIR=/path/to/cache python3 scripts/rehearse-repository-gate.py
```

The script copies the current working-tree manifests and the historical `9662bf8` manifests into separate temporary directories, runs the actual repository gate against each using the same cached database, and deletes those directories. It succeeds only when the current manifests pass and the historical lockfile is rejected for at least one High/Critical vulnerability. It prints only commit identity, lockfile hashes, finding IDs and exit codes. The result is sensitive to database age and vulnerability reclassification; a scanner error is not evidence of rejection. This rehearsal does not test Jenkins, Snyk, SonarQube, images, or deployment. It does not modify the checkout. Record the Trivy and database versions and date alongside any saved output; inspect evidence before sharing.

Existing local synthetic image-secret rejection evidence is in [phase 6–7 evidence](../evidence/phase-6-7-local.md); it is not a Jenkins demonstration. For the remaining live exercise, first configure AWS and Jenkins, resolve the blocking scans, and record the approved account, baseline commit, pipeline run, service revision and digest. With separate explicit permission for the necessary commits and pushes, introduce a selected vulnerable dependency and its matching lockfile on the working branch. Record the rejected Jenkins gate and prove that the release stages did not run and the service revision and running digests stayed unchanged. In a subsequently authorized fix commit, update both manifests, run Jenkins again, and capture gates, SBOM, published digest, registered revision, service/target health, logs and endpoint response. Release requires explicit permission for the specific ECR and ECS changes, per the existing pipeline runbook.

Test synthetic secret rejection in an isolated, disposable workspace without a usable credential. Keep only redacted summaries and never commit the fixture. Gitleaks scans Git history as well as the worktree: removing a committed fixture does not remove it from history; use an uncommitted disposable fixture so future history scans remain clean. Never deploy a vulnerable fixture image.

## Phase 9: retain first, review before cleanup

The proposed ECR lifecycle policy now defaults to disabled. Untagged digests can still be used directly by ECS, or be child images of a multi-platform manifest; tag status cannot establish safety. Enabling `enable_untagged_image_expiry` is an explicit opt-in, **not** proof that expiry is safe. Review active and in-progress deployments, rollback targets, standalone tasks, other services/clusters/accounts that pull the repository, image indexes and child manifests, and any other consumers first. Immutable tags do not prevent deletion. Inspect the Terraform plan: where the old rule already exists, the new default proposes removing that lifecycle policy, and the `count` address changes. Apply only after explicit cloud-change permission. Keep the policy disabled if any required image could be untagged; this may increase storage costs.

The offline helper reviews task definition revisions; it makes no AWS calls or changes and never suggests deleting images. Create a private JSON snapshot with this shape, replacing every example value with complete, current account data:

```json
{
  "definitions": [
    {"arn": "arn:aws:ecs:eu-north-1:123456789012:task-definition/app:1", "status": "ACTIVE"},
    {"arn": "arn:aws:ecs:eu-north-1:123456789012:task-definition/app:2", "status": "ACTIVE"}
  ],
  "service_revisions": ["arn:aws:ecs:eu-north-1:123456789012:task-definition/app:2"],
  "task_revisions": ["arn:aws:ecs:eu-north-1:123456789012:task-definition/app:2"],
  "rollback_revisions": ["arn:aws:ecs:eu-north-1:123456789012:task-definition/app:1"]
}
```

Run `python3 scripts/retention-review.py /path/to/private-snapshot.json --keep 3`. The helper retains every listed service deployment, running or pending task and rollback revision, plus the newest three active revisions per family. Unknown or inactive protected references are rejected. Its output is **only a review list**, not authorization or a safe deletion determination: it cannot verify snapshot completeness, other AWS regions/accounts, scheduled tasks, external consumers, or races.

To collect a complete inventory, use read-only AWS ECS list/describe operations for every relevant cluster and service, including every service deployment and task set, running and pending standalone tasks, scheduled/event-driven task definitions, all active task definitions for each affected family, and explicitly selected rollback revisions. Observe pagination and API failures; include revisions referenced by non-service consumers. Inventory ECR images, tags, manifest lists and child digests separately and record any cross-account consumers. If any source is unavailable or a deployment is in progress, postpone cleanup. Recollect immediately before each individually approved change; a stale offline list cannot protect against new consumers. Obtain explicit permission specifying the exact revisions and resources before deregistration or any other cloud change. Retain before/after inventory, inspect service and target health, and verify rollback images still exist and can be pulled. No cleanup has been executed.

Jenkins currently retains 10 builds and 5 sets of artifacts; its post-build cleanup removes only the verified build-local image tag. Before those limits rotate evidence, export reviewed and redacted reports and deployment records to an approved location. Do not indiscriminately prune shared agent caches, workspaces, Docker images, or required evidence.

## Eventual teardown

Separately inventory project-owned ECS service/tasks, capacity, load balancer, logs, ECR, IAM and networking, and inspect dependencies and Terraform state. Preserve required evidence and rollback artifacts, estimate costs, and review a scoped destroy plan. Get explicit permission before stopping services, deleting images, or applying the plan. Shared state backends, shared VPCs, Jenkins, SonarQube, accounts and unrelated resources require a separate owner-approved process; do not include them in the project teardown. Confirm what remains and any continuing charges afterward.
