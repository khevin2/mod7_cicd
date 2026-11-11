# Controlled rollback and monitoring checks

Baseline: Jenkins build 8 deployed healthy revision `mod9-ecs-app:3`. Execute these checks one at a time after committing/pushing the intended source. The assistant prepares code and reads state; only the operator runs commands that change AWS or start Jenkins builds.

## 1. Automatic rollback demonstration

```bash
ansible-playbook -i ansible/inventory/ci.yml \
  ansible/playbooks/run_ci_rollback_demo.yml \
  -e @ansible/inventory/ci-secrets.yml \
  --ask-vault-pass
```

This explicitly authorizes one controlled unhealthy deployment. The build still runs every scan, builds/publishes the approved image and generates its SBOM. Immediately before registering the test revision, the deployment script requires a healthy completed baseline, 100% minimum healthy capacity and an enabled rollback circuit breaker. It records the baseline revision and running image digests. The test revision keeps the scanned image and changes only the container health check to `exit 1`, with short test intervals. Normal builds leave this option false and retain the real health check.

ECS's circuit breaker must reject that deployment and automatically restore the prior revision. The observer makes read-only calls, records service snapshots and requires failure evidence tied to the attempted deployment ID. It then requires the baseline revision, original image digest set, healthy corresponding ALB targets and healthy application response. It never performs a manual rollback.

**Expected Jenkins result: FAILURE.** This preserves the required failed outcome for the attempted release even after automatic recovery. Ansible accepts the demonstration only when the failed build also archived `rollback-demo-result.json` proving automatic rollback, image identity and target/application health. A scanner failure, ordinary deployment failure or old healthy service without corresponding failure evidence is not sufficient.

The observer allows up to 120 checks, five seconds apart, plus API time. If it cannot prove recovery, Ansible fails; inspect the archived `rollback-observations.jsonl`, `rollback-failure-observed.json`, baseline snapshots and service events before making further changes. A subsequent read-only recovery check cannot retroactively change the Jenkins result.

After a controller interruption, resume observation without queuing another test:

```bash
ansible-playbook -i ansible/inventory/ci.yml \
  ansible/playbooks/run_ci_rollback_demo.yml \
  -e @ansible/inventory/ci-secrets.yml \
  -e '{"ci_resume_validation":true}' --tags ci_build --ask-vault-pass
```

## 2. Real-metric alarm evaluation and restoration

The four deployed alarms currently have no notification actions. This check verifies actual CloudWatch metric evaluation and recovery; it does not test notification delivery or cause an application outage.

Review the prepared local configurations, or regenerate them read-only:

```bash
python3 scripts/exercise-monitoring.py --profile training \
  --output-dir build-metadata/monitoring-demo-review
```

The helper requires the expected availability alarm in `OK`, no notification actions, correct ALB/target-group dimensions, and a fresh real `HealthyHostCount` datapoint equal to one. It refuses to change an already unhealthy or unexpected baseline. The prepared exercise changes only the threshold from 1 to 2, so one healthy target becomes a real breaching datapoint. The task count and app are unchanged.

Run the controlled evaluation:

```bash
python3 scripts/exercise-monitoring.py --profile training --execute
```

The operator command temporarily updates the alarm, observes `ALARM`, restores its exact original configuration in `finally`, and waits for `OK`. Each wait is bounded to eight minutes; actual metric evaluation usually needs several periods. It saves original/test alarm payloads, real metric datapoints, state history and a result JSON in a timestamped ignored `build-metadata/monitoring-demo-*` directory. `PASS` requires observing both transitions and restoring the original configuration. The helper refuses to run if notification actions have since been configured, so it does not send unrequested notifications.

On an ordinary error or keyboard interrupt the helper attempts restoration. If the process is forcibly killed or restoration cannot complete, review its saved original configuration and restore that exact payload yourself:

```bash
aws cloudwatch put-metric-alarm --profile training --region eu-north-1 \
  --cli-input-json file://build-metadata/monitoring-demo-TIMESTAMP/alarm-original.json
```

Replace the timestamp with the directory printed by the run. Do not use `set-alarm-state`: a synthetic forced state is not evidence of metric evaluation. Verify the alarm returns to `OK` and Terraform sees no threshold drift before considering the exercise complete.

## Evidence and remaining checks

Keep the Jenkins failed-build artifacts and monitoring result/history. Review generated files before copying sanitized evidence into tracked `evidence/`. Notification delivery remains unconfigured and unverified; host replacement/draining and the remaining security-negative/webhook/retention checks are separate work. A successful rollback exercise demonstrates deployment circuit-breaker recovery, not high availability for the single-task service.
