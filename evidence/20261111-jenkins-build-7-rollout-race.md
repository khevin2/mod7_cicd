# Jenkins build 7: successful deployment, premature verification failure

The operator-started release build 7 passed its security gates and published the image for commit `0c929ddac67041edd887798eaf0ecdcc4b6db978`. Jenkins registered `mod9-ecs-app:2` and updated the service, but ended with `FAILURE` during post-wait verification.

The archived `service-after.json` showed the requested revision, desired/running counts 1/1, and a single PRIMARY deployment still reporting `IN_PROGRESS`. The AWS `services-stable` waiter checks deployment/task counts, not `rolloutState`; its success preceded the completed-state update. The verifier correctly refused incomplete proof but lacked a bounded retry for this transition.

Subsequent read-only AWS verification on 2026-11-11 confirmed:

- The service PRIMARY rollout is `COMPLETED` on `mod9-ecs-app:2`, desired/running 1/1.
- Task `c64bb976ffab40238e41ce9299c9ac72` is healthy and uses the requested revision.
- Its image digest is `sha256:71b8b266020bab4b9ef8ee8fa6cbaf4440d7afc3918ffe6f39e3b65aa04b7fa6`, matching the image published by build 7.
- The ALB target is healthy, and `/health` returns `{"service":"jenkins-webapp","status":"ok"}`.

The local verifier now polls the requested revision up to 60 times, five seconds apart after the standard waiter. It rejects an inactive/mismatched service revision or an explicitly failed requested rollout, and times out if completion is never observed. Task/image/target/application verification remains required after rollout completion.

All eight deployment/publishing regression tests passed, including `IN_PROGRESS` transitioning to `COMPLETED`, a stuck rollout timing out, explicit failed rollout, rollback despite waiter success, wrong image digest, unhealthy target and image-change rejection before publication. These tests use fake local tools and make no cloud changes.

Build 7 remains a failed Jenkins run; the later healthy service state does not retroactively make its pipeline successful. The operator must commit/push the fix and run a new approved release for a passing integrated result. The assistant performed no cloud mutation.

Reference: [AWS services-stable waiter criteria](https://docs.aws.amazon.com/cli/latest/reference/ecs/wait/services-stable.html).
