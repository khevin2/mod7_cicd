# Jenkins build 10: automatic rollback verified

The operator executed the rollback demonstration. Read-only inspection of Jenkins build 10 confirms the archived `build-metadata/rollback-demo-result.json` and final Jenkins FAILURE result on 2026-11-11 (post actions at 12:54:45 UTC).

The proof records all four checks as true: automatic rollback, image identity, corresponding target health and application health. The failed revision was `mod9-ecs-app:5`; ECS restored baseline `mod9-ecs-app:3`, with digest `sha256:3039df6513879f725a50238c5bf68ed974b454a0c75037722d8e506b17e51aec`.

Jenkins FAILURE is intentional: the requested unhealthy release failed even though automatic recovery succeeded. Build 10 generated the proof missing from build 9. The controller checks this proof rather than accepting every failed build as a successful demonstration. The assistant inspected the artifact and console; the operator's final Ansible recap was not separately captured here.

The separate real-metric alarm exercise already reported PASS with original configuration restored; see `20261111-build-9-rollback-timing.md`. Notification delivery and host replacement remain separate unverified requirements.
