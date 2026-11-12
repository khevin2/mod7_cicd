# Cleanup verified — 2026-11-12

The operator applied the lifecycle-policy Terraform plan (one addition, no changes/deletions) and executed the reviewed cleanup. The assistant independently checked AWS read-only after execution.

- Revisions 4/5 are absent from the ACTIVE revision list. Active revisions 1/2/3/6 remain.
- Build 9/10 demo images were deleted. All four protected image digests remain, including Terraform bootstrap, prior normal releases, verified rollback revision 3 and current revision 6.
- Service remains on revision 6 with a single COMPLETED deployment, desired/running count 1 and no pending tasks.
- The running task is HEALTHY and uses build 12 digest `sha256:606ea7f71ad7b64019eed5814953af2d6bf5359cbc79f79fe26fbece19e1be1b`.
- The matching task IP/port 3000 is healthy in the ALB target group. HTTP `/health` returned `{"service":"jenkins-webapp","status":"ok"}`.
- ECR lifecycle policy is installed with one rule: expire only images explicitly tagged with prefix `retired-demo-`, one day after image push. General untagged expiry remains disabled. No protected image was marked for expiry.

See the adjacent sanitized verification JSON. Operator before/result snapshots remain in ignored `build-metadata/demo-cleanup/`. Cleanup never deleted task definitions, pruned shared Docker caches, or destroyed running project resources. Retained images were confirmed present; a fresh image pull/rollback deployment was not repeated after cleanup.
