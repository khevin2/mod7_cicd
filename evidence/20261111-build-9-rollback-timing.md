# Build 9 rollback and monitoring evidence

The operator ran the controlled rollback job and real-metric monitoring exercise on 2026-11-11. The assistant inspected Jenkins artifacts and AWS state read-only.

Build 9 reached the ECS deployment stage at 08:57:30 UTC. The observer exhausted its original 120-check window at 09:09:06 UTC and deliberately produced no success proof. Jenkins archived the diagnostic snapshots and finished FAILURE. Resuming Ansible returned HTTP 404 for the absent proof artifact; this is not a completed controller acceptance run.

The attempted revision was `mod9-ecs-app:4`, deployment `ecs-svc/0749019577928644644`. ECS events subsequently recorded that exact deployment failing at 09:15:33 UTC, automatic rollback to deployment `ecs-svc/7539563186179171185`, and completion at 09:16:11 UTC. The assistant independently verified revision `mod9-ecs-app:3` PRIMARY/COMPLETED, desired/running count 1, healthy task and matching healthy ALB target `10.90.2.31:3000`, and an application `/health` response with status `ok`.

The restored image digest is `sha256:3039df6513879f725a50238c5bf68ed974b454a0c75037722d8e506b17e51aec`, matching the archived pre-demo baseline. This verifies later automatic recovery; it does not retroactively create a proof artifact or change build 9's result.

The observer now permits 360 checks at five-second intervals (30 minutes plus API time). Five observer regression tests pass, including recovery after the previous 120-check limit and rejection of missing failure evidence, wrong digest and unhealthy targets. A new operator-run build is still required to demonstrate the complete Jenkins/Ansible proof path.

The operator's monitoring result in ignored `build-metadata/monitoring-demo-20261111T093015Z/monitoring-demo-result.json` reports PASS: real metric verified, ALARM observed, original threshold 1 restored, and recovery to OK observed. No notification actions were configured; notification delivery remains unverified.
