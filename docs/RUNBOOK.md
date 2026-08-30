# Jenkins CI/CD deployment runbook

Use this runbook to provision and operate the GitHub-triggered Jenkins pipeline.
Replace placeholders locally. Never commit or print credentials, tokens, private
keys, host keys, account IDs, or unredacted endpoints.

## Architecture and prerequisites

The lab uses two Amazon Linux 2023 EC2 instances in one VPC:

- **Jenkins controller-runner:** Jenkins, Docker, Node.js, Nginx, and Certbot.
  Jenkins listens only on loopback; Nginx terminates TLS for `ci.kheven.me`.
- **Application host:** Docker runtime for the Express container. Jenkins reaches
  it through private-VPC SSH with a verified ED25519 known-host entry.

Jenkins needs Git, Docker Engine, Node.js 24, OpenSSH, and egress to GitHub,
Docker Hub, GHCR, Jenkins plugins, and Trivy databases. The required Jenkins
plugins are Pipeline, Git, Credentials Binding, Docker Pipeline, SSH Agent,
NodeJS, GitHub, JUnit, and Timestamper. The NodeJS tool is named `NodeJS24`.

| ID | Type | Use |
| --- | --- | --- |
| `registry_creds` | Username with password | GHCR push and deployment pull |
| `ec2_ssh` | SSH Username with private key | Application-host SSH login |

Keep credential values only in Jenkins. Verify both SSH host fingerprints through
a trusted channel and keep `StrictHostKeyChecking=yes`.

## Provision infrastructure

Terraform roots use reviewed saved plans. Keep `bootstrap.tfvars`,
`backend.hcl`, and `terraform.tfvars` ignored. Private keys never belong in
Terraform inputs.

```bash
cd infra/bootstrap
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -var-file=bootstrap.tfvars -out=bootstrap.tfplan
# Apply only after review and explicit approval:
terraform apply bootstrap.tfplan

cd ../live
terraform init -reconfigure -backend-config=backend.hcl
terraform fmt -check -recursive
terraform validate
terraform plan -out=live.tfplan
# Apply only after review and explicit approval:
terraform apply live.tfplan
```

The application security group exposes public TCP 80, permits TCP 22 only from
the Jenkins controller security group or the EC2 Instance Connect service, and
allows outbound TCP 443 only for registry pulls and package repositories. The
Jenkins security group separately restricts UI access to administrator CIDRs.
When webhooks are enabled, AWS permits TCP 443 to Nginx; Nginx then permits
only GitHub webhook source ranges on `/github-webhook/`.

## Configure application and Jenkins hosts

Copy the ignored inventory template, use trusted public-key scans only to compare
with independently observed fingerprints, and then supply the verified entries.

```bash
cp ansible/inventory/hosts.yml.example ansible/inventory/hosts.yml
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/install_docker.yml
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/install_jenkins_controller.yml
```

The controller playbook installs Jenkins, its plugins, Docker, Nginx, a
Let's Encrypt certificate, the GitHub webhook allowlist refresher, and the
Jenkins runtime user's verified application-host `known_hosts` file.

## Configure Jenkins

Create a **Pipeline from SCM** job using this repository's `Jenkinsfile`.
Create the credentials listed above. Then configure the following global
environment variable in **Manage Jenkins -> System -> Global properties ->
Environment variables**:

```text
APPLICATION_DEPLOY_HOST=<approved application private DNS name or IP>
```

A manual `DEPLOY_HOST` parameter overrides the global value. GitHub webhook
builds have no interactive parameters and therefore resolve the target from
`APPLICATION_DEPLOY_HOST`. The pipeline stops with an explicit error if neither
value is present.

After verifying the application host's ED25519 key, ensure the Jenkins service user
has only the verified host entry. Do not disable strict host-key checking.

## Configure GitHub webhook delivery

1. In the ignored `infra/live/terraform.tfvars`, set:

   ```hcl
   enable_jenkins_webhook_ingress = true
   ```

2. Create and review a saved plan, then apply only that plan:

   ```bash
   cd infra/live
   terraform plan -out=jenkins-webhook.tfplan
   terraform show -no-color jenkins-webhook.tfplan
   terraform apply jenkins-webhook.tfplan
   ```

3. Keep `githubPush()` in the Jenkinsfile and run the job once after adding it,
   so Jenkins persists the trigger.
4. In GitHub repository settings, create an active webhook:

   | Setting | Value |
   | --- | --- |
   | Payload URL | `https://ci.kheven.me/github-webhook/` |
   | Content type | `application/json` |
   | SSL verification | Enabled |
   | Events | Just the push event |

5. Push a harmless commit or redeliver a prior **push** event. The Jenkins console
   must begin with a GitHub-push cause. A `ping` validates the endpoint but does
   not prove that the job is scheduled.

The webhook path is public at the network layer only so GitHub can reach it. Nginx
refreshes GitHub's `hooks` CIDRs from `https://api.github.com/meta`, denies all
other sources on that path, and proxies the permitted request to loopback Jenkins.

## Pipeline and security gates

The required order is Checkout, Install and Validate, Test, Observability and
Infrastructure Validation, Trivy Repository Scan, Docker Build, Trivy Image
Scan, Push Image, Deploy, and Runtime Cleanup. The validation stage runs metric,
Prometheus-rule, dashboard JSON, Compose, Ansible configuration, and
committed-secret checks. Terraform formatting, validation, plans, and approved
applies remain a local, reviewed workflow and are never run by Jenkins.

The pipeline scans dependencies, Terraform, Dockerfile configuration, repository
secrets, image vulnerabilities, and image secrets. Fixable HIGH or CRITICAL
findings block the build. It publishes non-secret JUnit, metadata, and Trivy
vulnerability/misconfiguration reports; secret reports remain inside the scanner
container.

Terraform egress exceptions are narrowly scoped to the two required security-group
resources, documented inline, and expire on 2027-08-22. They cover required
traffic without a global allow-all rule. The application host permits HTTPS only;
AmazonProvidedDNS and the Amazon Time Sync Service are not filtered by security
ignore files.
groups. The Jenkins controller retains separately scoped HTTPS, HTTP, DNS, NTP,
and private-VPC SSH rules. Do not replace the documented exceptions with global

## Verify a deployment

Use a successful GitHub-triggered run as the release evidence. Confirm the
pipeline's commit, immutable digest, test report, and final result. Then verify the
application host:

```bash
curl --fail --silent --show-error --max-time 15 http://<APPLICATION_PUBLIC_DNS_OR_IP>/health
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=<VERIFIED_KNOWN_HOSTS_FILE> ec2-user@<APPLICATION_PUBLIC_DNS_OR_IP> \
  'docker inspect --format="{{.Config.Image}} {{.State.Status}} {{.State.Health.Status}}" jenkins-webapp'
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=<VERIFIED_KNOWN_HOSTS_FILE> ec2-user@<APPLICATION_PUBLIC_DNS_OR_IP> \
  'docker image inspect jenkins-webapp:rollback'
```

Confirm HTTP 200, one running healthy application container, an immutable digest
matching build metadata, and a retained `jenkins-webapp:rollback` image.

## Configure and verify monitoring

Before the monitoring playbook is run, set these ignored inventory values to
the approved **private** application-host endpoints:

```yaml
monitoring_application_metrics_target: "<application-private-ip-or-dns>:9464"
monitoring_application_node_exporter_target: "<application-private-ip-or-dns>:9100"
```

The playbook renders these values into Prometheus file-based service discovery;
they do not enter Git, Terraform state, or the public edge. First run the local
static gate:

```bash
bash scripts/validate-phase8.sh
```

### Phase 10 approved deployment procedure

Run this procedure only after the exact Terraform plan has been reviewed and
explicitly approved. It intentionally keeps Terraform, DNS, and Ansible as
separate checkpoints: the permanent Cloudflare DNS-only record is user-managed,
and neither secret value may appear in Terraform or inventory.

```bash
# Repository-only check; makes no cloud or host changes.
bash scripts/validate-phase10.sh

cd infra/live
terraform init -reconfigure -backend-config=backend.hcl
terraform fmt -check -recursive
terraform validate
terraform plan -out=phase10.tfplan
terraform show -no-color phase10.tfplan
# Confirm exact creates/changes, ownership tags, and no unapproved delete or replacement.
# Apply only after explicit approval for this saved plan:
terraform apply phase10.tfplan
terraform output
```

Use the `monitoring_elastic_ip` output to create the DNS-only
`grafana.kheven.me` A record manually. Verify it resolves to that address before
certificate issuance. Populate the ignored `ansible/inventory/hosts.yml` only
with the monitoring Elastic IP, verified ED25519 host key, private application
metrics/exporter targets, certificate email, Region, and the two named secret
**ARNs**. Set the Slack webhook and Cloudflare DNS token values separately in
their named Secrets Manager containers; never add their values to inventory.

```bash
# Compare this result to an independently trusted fingerprint before adding it.
ssh-keyscan -t ed25519 <MONITORING_ELASTIC_IP>

ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/install_docker.yml
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/install_monitoring_stack.yml
# The second run must be idempotent apart from expected service reconciliation.
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/install_monitoring_stack.yml

cd infra/live
terraform plan
```

### Diagnose the monitoring Compose stack over SSH

The monitoring playbook passes `AWS_REGION` to every Docker Compose command so
the `awslogs` logging driver can resolve its Region. An interactive SSH shell
does not inherit that Ansible task environment. For manual status or recovery
checks, supply the Region explicitly:

```bash
sudo env AWS_REGION=eu-north-1 \
  docker compose -f /opt/monitoring/monitoring/compose.yml ps
```

If Compose reports that `AWS_REGION` is missing, use the command above rather
than altering `compose.yml` or disabling CloudWatch logging. `sudo cd ...` does
not change an interactive shell's directory; use `cd ...` without `sudo`, or
continue specifying the Compose file with its absolute path.

After the second playbook run, capture sanitized evidence for the applied
resource inventory, container versions/health, `https://grafana.kheven.me/api/health`,
Prometheus target state, dashboard, and fresh CloudWatch events. The final
Terraform plan must show no changes, or each change must be explained before
claiming Phase 10 complete.

After the approved Phase 10 deployment, verify that Prometheus lists four
healthy targets (itself, monitoring Node Exporter, application metrics, and
application Node Exporter) and that the `Jenkins Webapp Observability` dashboard
has data for RPS, p95, 5xx percentage, CPU, memory, disk, and scrape health.
The high-error alert fires only after the ratio remains above 5% for five
minutes and at least 20 requests occurred in the window. Test it only via the
approved internal fault-injection path, then capture normal, pending, firing,
and resolved states and the paired Slack messages without exposing the webhook.

## Controlled Phase 11 fault test

Do not perform this procedure until Phase 10 has completed, the exact deployed
digest is recorded, and the operator has approval for the temporary test. The
application keeps the mechanism disabled by default. The normal Jenkins
deployment must never set `FAULT_INJECTION_ENABLED=true` or publish port 9465.

For the approved test only, start the already-verified immutable application
digest with `FAULT_INJECTION_ENABLED=true` while retaining every normal runtime
hardening, log-driver, health-check, port, and resource option. The process then
opens its control listener only on `127.0.0.1:9465` **inside the container**; it
is not Docker-published and cannot be reached from the network. From the
application host, use `docker exec` to POST to `/_phase11/enable`, then generate
the controlled traffic only against `/_phase11/fault`. The route is a 404 until
enabled and returns a bounded, deliberate 500 response only while enabled.

Capture the baseline, Pending, Firing, and Resolved alert states with timestamps.
Maintain more than 20 requests in the five-minute window and an error ratio above
5% for more than five minutes. Stop traffic, POST to `/_phase11/disable` through
the container-local control listener, and confirm that `/_phase11/fault` is 404
before collecting recovery evidence. Restore the normal deployment without
`FAULT_INJECTION_ENABLED` after the test. Never put a test-control endpoint,
Docker socket, token, or temporary environment value in public evidence.

## Rollback and cleanup

Candidate health is checked before cutover. If post-cutover health does not recover,
the pipeline restores the previous image. The current previous image is retained as
`jenkins-webapp:rollback`.

For a manual rollback, connect with strict host verification and run:

```bash
docker rm -f jenkins-webapp
docker run -d --name jenkins-webapp --restart unless-stopped \
  --user 10001:10001 --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,size=16m \
  --cap-drop ALL --security-opt no-new-privileges:true \
  --pids-limit 128 --memory 256m --memory-reservation 128m --cpus 0.50 \
  --log-driver awslogs --log-opt awslogs-region=eu-north-1 \
  --log-opt awslogs-group=/jenkins-webapp/lab/application/containers \
  --log-opt awslogs-stream=active --log-opt awslogs-create-group=false \
  -p 80:3000 -p 9464:9464 jenkins-webapp:rollback
curl --fail --silent --show-error --max-time 10 http://127.0.0.1:80/health
```

Runtime Cleanup removes only the named candidate, dangling layers, and registry
login. It retains active and rollback tags. Do not use broad Docker prune commands
without separate approval.

## Troubleshooting

| Symptom | Safe recovery |
| --- | --- |
| GitHub delivery fails before Jenkins | Check the saved Terraform plan was applied, DNS resolves to the controller, Nginx is active, and the controller's GitHub CIDR allowlist is populated. |
| GitHub delivery succeeds but no job starts | Run the Pipeline once after adding `githubPush()`; verify the job configuration contains a GitHub push trigger. |
| Webhook build says deployment host is required | Set `APPLICATION_DEPLOY_HOST` in Jenkins Global properties, or supply `DEPLOY_HOST` for a manual override. |
| Trivy setup/download fails | Treat it as a failed security gate. Verify Docker Hub/GHCR egress and DNS, then rerun; never bypass the scan. |
| Trivy finds HIGH/CRITICAL issues | Review non-secret reports, remediate the source or configuration, and rerun. Do not add broad ignores. |
| SSH authentication or host verification fails | Stop. Check `ec2_ssh`, approved ingress, and the independently verified ED25519 entry. Do not weaken strict checking. |
| Monitoring Compose says `AWS_REGION` is missing | Run Compose with `sudo env AWS_REGION=eu-north-1`; Ansible supplies this only during playbook tasks. Do not remove the `awslogs` configuration. |
| Deployment health fails | Inspect application logs and health. Preserve the current/rollback images and use the rollback command only after diagnosis. |

## Evidence handling

Use `YYYYMMDD-purpose.ext`, redact sensitive values, and keep raw captures outside
Git. Consult [the evidence index](../evidence/README.md) before publishing evidence.
Archive vulnerability and misconfiguration reports only; never retain a Trivy secret
report.
