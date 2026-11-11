# Jenkins release and ECS monitoring

This is a local implementation, not proof of an executed Jenkins or AWS deployment. Phase 3 scanner validation and Phases 4–5 provisioning remain prerequisites. Jenkins, credentials, AWS CLI access, the service and alert destination must be configured and verified before live use. The user must explicitly authorize any cloud-changing action; no commit, push, or cloud change is authorized by this document.

## Jenkins job

### Jenkins-driven ECS release

After the baseline service exists, generate environment-specific release settings from its Terraform outputs and read-only AWS identity/service queries:

```bash
python3 scripts/export-ci-release-config.py --profile training
AWS_PROFILE=training terraform -chdir=infra/ci plan -out=ecs-release.tfplan
AWS_PROFILE=training terraform -chdir=infra/ci show -no-color ecs-release.tfplan
```

The generator writes ignored `infra/ci/ecs-release.auto.tfvars.json` and `ansible/inventory/ci-release.yml`. Regenerate them after recreating the ECS stack; do not hand-copy a stale execution-role ARN. The Terraform input defaults to null on a fresh checkout, so the initial CI host can be created before the ECS stack. After reviewing the exact plan, the operator applies it. The initial release-access plan creates one inline IAM policy on the existing CI role and changes no runtime resources.

Deployment permissions are limited to the existing service, registration of revisions in the application task family, inspection of tasks in the named cluster, and passing the one execution role to `ecs-tasks.amazonaws.com`. Task listing uses `Resource="*"` with an exact cluster condition. ELB target-health inspection requires `Resource="*"` and is limited to `eu-north-1`. There are no ECS create/delete-service, EC2/ASG, ECR deletion or IAM modification permissions. See the [ECS authorization reference](https://docs.aws.amazon.com/service-authorization/latest/reference/list_ecs.html) and [ELB authorization reference](https://docs.aws.amazon.com/service-authorization/latest/reference/list_elbv2.html).

Commit and push the intended pipeline source yourself, then explicitly authorize one release by running:

```bash
ansible-playbook -i ansible/inventory/ci.yml \
  ansible/playbooks/run_ci_release.yml \
  -e @ansible/inventory/ci-secrets.yml \
  --ask-vault-pass
```

This command configures the job through Ansible, preserves both scanner credential bindings, installs the generated non-secret release environment through JCasC, and queues `PUBLISH_APPROVED=true`, `RELEASE_APPROVED=true`. It authorizes publication and ECS update for the newly queued build. Before queuing, Ansible verifies the expected EC2 role and that Jenkins can inspect the active service. The pipeline still requires every security gate, a manual user cause, image identity verification, the requested completed ECS revision, matching running task digest, healthy targets and a successful application health response. A successful waiter following rollback fails the revision checks.

Normal `run_ci_validation.yml` invocations keep both approvals false. Existing publish-only commands keep deployment false. Foundation/security reruns retain generated release environment settings when the ignored inventory file exists. A release can be monitored after a controller interruption without starting another build:

```bash
ansible-playbook -i ansible/inventory/ci.yml \
  ansible/playbooks/run_ci_release.yml \
  -e @ansible/inventory/ci-secrets.yml \
  -e '{"ci_resume_validation":true}' --tags ci_build --ask-vault-pass
```

Keep the Terraform `release_image` bootstrap digest unchanged and non-null after the first deployment. Terraform ignores later service task-definition changes owned by Jenkins. Live release/rollback evidence must still be collected; policy simulation and local tests are not a deployment.

### First publication after foundations

The CI Terraform root now declares an EC2 publisher role and instance profile. Its policy permits registry authentication and push/pull verification only for `mod9-ecs` in account `447558491229`, region `eu-north-1`. Registry authentication requires `Resource="*"`; repository operations use the exact repository ARN. This role grants no ECS deployment permissions.

After the operator reviews and applies `infra/ci/publisher.tfplan`, commit and push the pipeline changes, then run:

```bash
ansible-playbook -i ansible/inventory/ci.yml \
  ansible/playbooks/run_ci_validation.yml \
  -e @ansible/inventory/ci-secrets.yml \
  -e '{"ci_publish_approved":true}' \
  --ask-vault-pass
```

This explicit operator choice queues `PUBLISH_APPROVED=true`, `RELEASE_APPROVED=false`. Ansible first checks that Jenkins can use the intended EC2 role. Jenkins rebuilds, scans and inventories the image, and publishes it only after all preceding gates pass. It verifies the ECR digest resolves to the scanned local image ID and archives `build-metadata/image-digest.txt`. ECS deployment is skipped. Default invocations remain scan-only. Use the published digest to prepare the separate Terraform plan that bootstraps the ECS task definition and service; later release integration still needs scoped ECS permissions and environment configuration.

For the new CI host, use the [Ansible/JCasC setup](../infra/ci/README.md) rather than the plugin/setup wizard. The complete plugin dependency closure is checksum-locked, and the administrator, `NodeJS24` installation and lifecycle environment are declared in source. Ansible seeds `mod9-secure-ecs` disabled until the remote branch and all integration prerequisites are verified. Permanent configuration changes belong in the managed declarations. SonarQube project/token setup and scanner tool provisioning remain separate automation work.

The [CI security playbook](CI_SECURITY_SETUP.md) now prepares scanner tools and SonarQube project, gate, account/token and JCasC bindings. It must be operator-run and verified; local tests alone do not establish passing security gates.

Configure a dedicated Pipeline-from-SCM job for `feature/secure-ecs-ec2`, with a complete clone and the GitHub push trigger. Only grant job administration and manual-build permissions to approved users. Push-triggered builds scan and test only. To authorize publication and deployment, the user must explicitly approve that particular release and an authorized operator must start the job manually with `RELEASE_APPROVED=true`; the pipeline rejects release requests without a manual user cause. A checked parameter authorizes both publishing to ECR and updating the ECS service for that build. Do not check it until the user has explicitly approved both actions. Keep the default false and do not provide release credentials to untrusted jobs.

The pipeline uses the existing `NodeJS24` Jenkins tool and executables `gitleaks`, `trivy`, `syft`, `snyk`, `sonar-scanner`, `aws`, `jq`, Python 3, Docker, and curl on a trusted agent. Versions are checked before scanning: Gitleaks 8.28.0, Trivy 0.73.0 and Syft 1.38.0; configure the tested Snyk and SonarScanner versions as `EXPECTED_SNYK_VERSION` and `EXPECTED_SONAR_SCANNER_VERSION`. Pin the agent's actual tools and verify checksums or image digests when provisioning it; setting an expected version does not itself install or authenticate a binary. Record the SonarQube server version and verify its issue API and severity mapping before release.

Jenkins requires these secret text credential IDs:

| ID | Purpose |
| --- | --- |
| `sonarqube-token` | SAST token used only in the SAST stage |
| `snyk-token` | SCA token used only in the SCA stage |

Configure `SONAR_HOST_URL` for the approved SonarQube server. Snyk communicates dependency metadata to its service. Do not put tokens in the Jenkinsfile, global plaintext variables, source control, reports, or command arguments. Lock down Jenkins artifact access: even redacted reports and AWS metadata can reveal internal details. Gitleaks runs with 100% redaction; SonarScanner's raw log is not archived. Check reports before copying them into submission evidence.

Set these **non-secret job environment variables** from reviewed Terraform outputs and the confirmed AWS account:

| Variable | Value |
| --- | --- |
| `AWS_ACCOUNT_ID` | Approved 12-digit account ID |
| `ECR_REPOSITORY` | ECR repository name, e.g. `mod9-ecs` |
| `ECS_CLUSTER` / `ECS_SERVICE` | Existing cluster and service names |
| `ECS_FAMILY` | Task definition family, e.g. `mod9-ecs-app` |
| `TASK_EXECUTION_ROLE_ARN` | Approved ECS execution role ARN |
| `ECS_LOG_GROUP` | Application log group, e.g. `/ecs/mod9-ecs` |
| `APP_HEALTH_URL` | Approved reachable ALB endpoint ending in `/health` |

The pipeline fixes `AWS_REGION=eu-north-1` and checks the AWS caller's account before any release mutation. Arrange role-based Jenkins agent access with the minimum ECR push, ECS registration/service update/describe, `iam:PassRole` for the named execution role, ELB target-health describe, and STS identity permissions. Grant no permissions to change infrastructure or unrelated roles. Verify the policy with a reviewed IAM plan; this repository does not create or attach the Jenkins role. Ensure the ALB security group accepts health requests from the Jenkins agent.

Each run records its source commit, build number, local image ID, tool versions, scan reports and SBOM. A release pushes a commit-and-build tag and pulls the resulting ECR digest to confirm it matches the scanned image ID. It registers a task definition containing that digest, updates the existing service, waits for stability, then confirms the requested revision is the completed primary deployment, each running task has that revision and digest, its ALB target is healthy, and `/health` succeeds. A waiter returning successfully after rollback does **not** count as a successful release. The verifier expects the single-architecture image produced by the current Docker build; multi-platform manifest-list digests need additional child-digest validation before use.

Artifacts are archived in Jenkins `post { always { ... } }` so failure reports and intermediate deployment evidence survive a failed stage. A failed SonarQube analysis produces an archived, fixed-category JSON diagnostic; its raw log stays out of the archive. Image secret findings are scanned in a private temporary file and only the count and exit status are archived. After archiving, Jenkins attempts to remove only the local image tag whose identity matches this build's recorded image ID; it does not prune other images. Do not claim that a green scan-only build deployed an image. Tool or scanner failures block release; SAST/SCA credentials and the exact SonarQube API behavior must still be validated. The optional `build-metadata` directory contains environment-specific identifiers; sanitize before publishing evidence.

## Monitoring configuration

Terraform in `infra/ecs-ec2/monitoring.tf` creates a CloudWatch dashboard and four alarms. These are proposed lab resources and incur charges after approval and apply.

- Target-generated 5xx rate greater than 5% and target p95 response time greater than 300 ms, each for two five-minute periods and only when each period has at least 20 requests.
- Unhealthy target count above zero, and no healthy targets (including missing target metrics) for three minutes.
- Dashboard panels for request/5xx counts, target p95, target health, and ECS CPU/memory.

This adapts the prior project's alert thresholds to ALB metrics. It does not import its Prometheus/Grafana deployment or its application instrumentation: target response time is measured by ALB until response headers and is not identical to the prior application histogram. ALB-generated 5xx responses are outside the target 5xx metric; use the target-availability alarm and add an ALB-generated 5xx alarm if that signal is required. The no-healthy-target alarm intentionally enters ALARM during the foundations-only stage before a service is running, or when target metrics disappear. Account for that during provisioning.

`alarm_actions` accepts existing SNS topic ARNs; it defaults to an empty list, so alarms have **no notifications** until a permitted destination and subscriptions are configured. This stack does not create subscriptions or send test messages. Validate permissions and delivery with the destination owner before enabling it. The app's `awslogs` stream prefix is `app`; the stream name includes the task ID. Match it to the running task and the recorded revision/image digest when capturing logs. Log retention is configured in the ECS Terraform root.

## Future live validation and recovery

After the foundations and a security-approved baseline service exist, review and obtain explicit permission for the exact Terraform plan that adds the alarms. Verify dimensions and dashboard data against the new ALB and service. In a controlled lab with an approved test workload and traffic generator, send at least 20 requests per five-minute window with >5% target 5xx for two windows, verify the alarm transition and any explicitly authorized notification, then stop fault injection and verify recovery. Use an isolated approved test workload; the current application has no fault-injection route. Never infer a successful notification from an alarm state alone.

For rollback validation, retain a known-good task revision and image. After explicit permission for the exact test deployment, register a task definition using the same security-approved image but an intentionally failing test command or health check; update the lab service, observe circuit-breaker rollback, and verify the prior revision and healthy target recover. The Jenkins verifier must fail the attempted release even if `services-stable` returns after rollback. Do not perform this test in a production service. ECS instance draining/replacement also changes cloud state and requires separate explicit permission and adequate capacity. Record the starting and restored revision, target health, logs, time, and alert status.

No live alarm, notification, deployment, rollback, or host-replacement evidence has been collected yet. Automated local tests use a fake AWS CLI and do not establish AWS or Jenkins behavior.
