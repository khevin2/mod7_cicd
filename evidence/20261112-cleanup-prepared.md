# Scoped demo cleanup prepared

No cleanup or lifecycle-policy application was executed by the assistant. Read-only account inventory selected only broken demo revisions `mod9-ecs-app:4` and `mod9-ecs-app:5`, with images:

- `sha256:f24ba1b8ad0f5869c0d1226cf927b47c063cfcef151a134bf3d2b5dfcdba78fa` (build 9)
- `sha256:a60f51db113b133f2ac410b2c6b0ae11fcf40b32ea7bb1966447ddbbb5337d88` (build 10)

The account's regional ECS service/task and ACTIVE task-definition inventory found no remaining consumers of those two revisions/digests. The helper retains all other active-definition image references, including bootstrap revision 1, previous normal release revision 2, verified rollback revision 3 and current revision 6. The two intentionally broken revisions are not scheduled/external consumers in this lab; pause releases during operator execution.

Eight local guard tests pass: exact target selection, service/task references, shared digests, shared tag references, unexpected health checks, manifest indexes, stale reviews and default read-only behavior. `terraform validate` passed. A saved plan generated with `-refresh=false` proposes exactly one addition: a lifecycle policy limited to explicit `retired-demo-` tags. It proposes no changes/deletions to running resources. The operator must review/apply it and execute cleanup; independent post-cleanup service, target, endpoint and retained-image checks remain pending.
