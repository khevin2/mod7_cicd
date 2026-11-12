# Security demonstration and retention review

Build 11 demonstrated the injected vulnerable dependency being rejected; build 12 passed after remediation and deployed revision 6. The operator executes commits, builds, Terraform applies and cleanup commands. The assistant prepares local files and inspects AWS read-only.

## Phase 8: local rehearsal and future live proof

Install the pipeline's pinned Trivy and jq and populate a trusted, current Trivy vulnerability database in a local cache first. With that cache available, run:

```sh
TRIVY_CACHE_DIR=/path/to/cache python3 scripts/rehearse-repository-gate.py
```

The script copies the current working-tree manifests and the historical `9662bf8` manifests into separate temporary directories, runs the actual repository gate against each using the same cached database, and deletes those directories. It succeeds only when the current manifests pass and the historical lockfile is rejected for at least one High/Critical vulnerability. It prints only commit identity, lockfile hashes, finding IDs and exit codes. The result is sensitive to database age and vulnerability reclassification; a scanner error is not evidence of rejection. This rehearsal does not test Jenkins, Snyk, SonarQube, images, or deployment. It does not modify the checkout. Record the Trivy and database versions and date alongside any saved output; inspect evidence before sharing.

Existing local synthetic image-secret rejection evidence is in [phase 6–7 evidence](../evidence/phase-6-7-local.md); it is not a Jenkins demonstration. For the remaining live exercise, first configure AWS and Jenkins, resolve the blocking scans, and record the approved account, baseline commit, pipeline run, service revision and digest. With separate explicit permission for the necessary commits and pushes, introduce a selected vulnerable dependency and its matching lockfile on the working branch. Record the rejected Jenkins gate and prove that the release stages did not run and the service revision and running digests stayed unchanged. In a subsequently authorized fix commit, update both manifests, run Jenkins again, and capture gates, SBOM, published digest, registered revision, service/target health, logs and endpoint response. Release requires explicit permission for the specific ECR and ECS changes, per the existing pipeline runbook.

Test synthetic secret rejection in an isolated, disposable workspace without a usable credential. Keep only redacted summaries and never commit the fixture. Gitleaks scans Git history as well as the worktree: removing a committed fixture does not remove it from history; use an uncommitted disposable fixture so future history scans remain clean. Never deploy a vulnerable fixture image.

## Phase 9: retain first, review before cleanup

The ECR lifecycle policy expires only images explicitly marked with a `retired-demo-` tag, after one day from image push. No current image has this marker. Never mark an active, rollback or bootstrap digest: a matching tag can expire the whole digest even if other tags exist. Optional general untagged expiry remains disabled by default because untagged images can be referenced by digest or be manifest-list children. Retention review must account for in-progress deployments, rollback targets, tasks and any external consumers. Immutable tags do not prevent deletion.

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

## Operator commands: scoped demo cleanup

Pause new Jenkins releases during this operation. The only intended targets are revisions 4 and 5, which contain the deliberate `exit 1` health check, and their build 9/10 images. These definitions are not used by scheduled jobs or external consumers in this lab. Retain revision 1/bootstrap, revision 3/verified rollback, revision 6/current release and all other active-definition image references. No task-definition deletion or broad Docker pruning is used.

The prepared Terraform plan adds the lifecycle rule; review it before applying:

```bash
terraform -chdir=infra/ecs-ec2 show -no-color retention.tfplan
AWS_PROFILE=training terraform -chdir=infra/ecs-ec2 apply retention.tfplan
```

Regenerate/review the cleanup inventory, then execute the exact matching review:

```bash
python3 scripts/cleanup-demo-revisions.py --profile training
python3 scripts/cleanup-demo-revisions.py --profile training --execute
```

The first command makes read-only AWS calls and saves `build-metadata/demo-cleanup/review.json`. The second rechecks account, stable deployment and all regional cluster/service/task references, resolves every ACTIVE task-definition image reference, rejects shared digests and manifest indexes, and requires an unchanged review. It deregisters only revisions 4/5 and deletes only the two reviewed digests after another definition-reference check. The exact target list and partial results are recorded in `result.json`. If interrupted after a mutation, stop and inspect that result and AWS state; do not blindly rerun. External/cross-account consumers are outside this lab inventory. Do not reuse this narrow demo cleanup helper as general repository retention automation.

The lifecycle policy provides an opt-in future expiry mechanism. This run removes the reviewed obsolete demo images immediately and never tags retained images. The assistant verifies current revision, endpoint/target health and retained rollback/bootstrap image availability after operator execution. Keep Jenkins build 10/11/12 evidence before artifact rotation.

## Eventual teardown

Separately inventory project-owned ECS service/tasks, capacity, load balancer, logs, ECR, IAM and networking, and inspect dependencies and Terraform state. Preserve required evidence and rollback artifacts, estimate costs, and review a scoped destroy plan. Get explicit permission before stopping services, deleting images, or applying the plan. Shared state backends, shared VPCs, Jenkins, SonarQube, accounts and unrelated resources require a separate owner-approved process; do not include them in the project teardown. Confirm what remains and any continuing charges afterward.
