# Phase 7 controlled checks prepared

Read-only preflight on 2026-11-11 confirmed `mod9-ecs-service` is healthy on completed revision 3, desired/running 1/1, with the deployment circuit breaker and rollback enabled. All four project metric alarms were `OK` and had empty notification action lists.

Prepared local automation:

- A per-build rollback option defaults false and requires explicit release approval. The operator-run wrapper requests the controlled health failure, records the healthy baseline first, and requires failure evidence plus automatic restoration of the original revision/digests/target/application health.
- Jenkins intentionally returns `FAILURE` for the rejected release. The Ansible wrapper separately requires the recovery-proof artifact; it cannot turn an ordinary failed build into a successful demonstration.
- A monitoring helper defaults to read-only preparation. Its explicit execution temporarily changes the existing real-metric availability threshold from 1 to 2, waits for `ALARM`, restores the original configuration, and waits for `OK`. No task count changes or notifications are included.

Validation:

- Ten deployment/publishing regression tests passed, including the complete fake-tool demo path retaining the scanned image, deliberate failing health check, rejection of an unhealthy baseline before registration, normal deployment, rollback/digest/target errors and bounded completion waiting.
- Four rollback observer tests passed. Original healthy state without corresponding failed-deployment evidence, a wrong restored digest and unhealthy target cannot produce a proof artifact. Verified recovery still returns a nonzero Jenkins exit status, and the observer issues no mutating AWS commands.
- Five monitoring tests passed: default read-only behavior, actual-condition fixture and exact restoration, restoration after timeout while retaining failure status, and refusal of notification/unhealthy-metric baselines.
- Shell and Ansible syntax checks passed. Read-only preparation against the live availability alarm verified a fresh real metric with one healthy target and saved review files in ignored `build-metadata/monitoring-demo-prepared`.

The assistant has not executed the rollback build or changed alarm configuration. Live rollback, alarm transitions and recovery evidence remain pending. Notification delivery remains unconfigured. See the [operator runbook](../docs/PHASE_7_RUNBOOK.md).
