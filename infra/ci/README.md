# Shared Jenkins / SonarQube demo host

Local configuration only. No AWS resources have been created or changed by preparing these files. The operator runs all plans, applies, Ansible provisioning, and service operations. Do not run the previous `infra/live` root or its Jenkins playbook for this setup: they include the former standalone application host and DNS/SSH deployment assumptions.

## Scope and limits

- Account `447558491229`, profile `training`, region `eu-north-1`.
- One Amazon Linux 2023 x86_64 `t3.small`, encrypted 40 GiB gp3 root disk, 6 GiB disk swap. T3 Standard credit mode avoids surplus CPU credit charges; exhausted credits can throttle builds.
- Dedicated `10.80.0.0/16` VPC and public subnet. Confirm it does not overlap any network you intend to connect. No NAT Gateway, ALB, Elastic IP, application instance, or ECS resources are created here.
- SSH from your public IPv4 `/32` only. Jenkins `8080` and SonarQube `9000` bind to localhost. AWS VPC-provided DNS remains available; outbound HTTP/HTTPS supports package repositories and scanner services.
- Jenkins uses one executor and a 384 MiB maximum Java heap. SonarQube uses 256 MiB web/compute heaps and a 512 MiB search heap; PostgreSQL uses 64 MiB shared buffers and 20 connections. These are experimental settings, below SonarQube's published 4 GB host requirement. Swap does not guarantee successful analysis. Validate the actual tiny project and repeat before the demos.
- The AMI is fixed to `ami-0c0427b4be074f058`; the provider is fixed to `6.72.0`. Ansible fixes the AL2023 package snapshot, Jenkins/Java/Docker versions, Node archive checksum, and all 77 plugin versions/checksums. Artifact availability and future deprecation still require a deliberate refresh.
- The host has no AWS deployment role yet. Never copy your local AWS credentials to it. Scoped role-based access is a subsequent release-integration step.
- Jenkins Docker access is effectively root access. Run trusted lab jobs only. JCasC creates the Vault-defined administrator, disables signups and anonymous access, and replaces the interactive setup wizard. The single account is for the trusted lab operator.
- Jenkins starts at boot; SonarQube/PostgreSQL remain stopped until explicitly requested. Docker volumes preserve analysis data and the database between service stops. They do not survive deleting the root EBS volume; capture required evidence first.
- EC2 compute/public IPv4 while running, EBS storage, and network usage are billable. Stopping EC2 does not remove EBS charges. No cost ceiling or automatic teardown is configured. Public IP may change after stop/start.

## 1. Prepare and review the plan

From the repository root, create your SSH key if neither file already exists:

```bash
mkdir -p keys
if [ ! -e keys/mod9-ci ] && [ ! -e keys/mod9-ci.pub ]; then
  ssh-keygen -t ed25519 -f keys/mod9-ci -C mod9-ci
fi

export AWS_PROFILE=training
export AWS_REGION=eu-north-1
export AWS_DEFAULT_REGION=eu-north-1
export TF_VAR_owner=kheven
CI_PUBLIC_IP=$(curl --fail --silent --show-error https://checkip.amazonaws.com)
export TF_VAR_admin_cidr="${CI_PUBLIC_IP}/32"

terraform -chdir=infra/ci init
terraform -chdir=infra/ci fmt -check
terraform -chdir=infra/ci validate
terraform -chdir=infra/ci plan -out=ci.tfplan
terraform -chdir=infra/ci show -no-color ci.tfplan
```

Review the exact saved plan: one `t3.small`, 40 GiB encrypted root disk, Standard credits, SSH only from your address, no unrelated changes. State is local and ignored; back it up privately. Do not commit plans, keys, actual inventory, or state. `.terraform.lock.hcl` records the selected provider and belongs with the source.

Only the operator should run the following cloud-changing command after reviewing that plan:

```bash
terraform -chdir=infra/ci apply ci.tfplan
terraform -chdir=infra/ci output
```

## 2. Verify the host key and prepare inventory

Read the instance's boot console output through AWS, independently of the SSH connection:

```bash
CI_INSTANCE_ID=$(terraform -chdir=infra/ci output -raw instance_id)
aws ec2 get-console-output --profile training --region eu-north-1 \
  --instance-id "$CI_INSTANCE_ID" --latest --query Output --output text
```

Find the SSH ED25519 fingerprint. During the initial SSH connection, compare the displayed fingerprint against this trusted boot output. If the fingerprint is absent, wait for boot to finish or use the AWS console to inspect it; do not trust an unverified `ssh-keyscan` result.

```bash
CI_HOST_IP=$(terraform -chdir=infra/ci output -raw public_ip)
mkdir -p ansible/inventory
ssh -o UserKnownHostsFile=ansible/inventory/known_hosts \
  -o StrictHostKeyChecking=ask -o IdentitiesOnly=yes \
  -i keys/mod9-ci "ec2-user@$CI_HOST_IP" true

cp -n ansible/inventory/ci.yml.example ansible/inventory/ci.yml
```

Replace `REPLACE_WITH_TERRAFORM_PUBLIC_IP` in `ansible/inventory/ci.yml`. All paths assume commands run from the repository root. The CI inventory disables SSH connection multiplexing to avoid stale control sockets after network/IP changes, enables pipelining to avoid separate module transfers, and fixes the remote interpreter to `/usr/bin/python3`. Run only one provisioning process at a time. If the private key is passphrase-protected, load it into your SSH agent first. Do not disable host-key verification to fix connection errors.

## 3. Configure the host with Ansible

Only built-in Ansible modules are needed. `ansible/requirements-ci.txt` pins the tested controller version. Install it in a dedicated virtual environment if your Ansible version differs. Images are pinned in `ansible/vars/ci-images.yml`; the resolver script reads registry metadata without pulling images. Updating those digests does not establish image security or server compatibility; validate any upgrade before a demo.

Create an encrypted local Vault file before provisioning:

```bash
ansible-vault create ansible/inventory/ci-secrets.yml
```

In the Vault editor, define `ci_jenkins_admin_password` with a unique password of at least 16 characters. Use `ansible/vars/ci-secrets.yml.example` as the field reference, not as a working secret. Do not paste the password into commands, chat, source files, or command-line extra-vars. Keep the Vault password separately; `--ask-vault-pass` prompts privately. The Vault file is ignored by Git. On an existing host, this changes the managed administrator password and configuration to these declared values. Do not run provisioning during a build.

```bash
ansible-playbook -i ansible/inventory/ci.yml \
  ansible/playbooks/configure_ci_demo.yml \
  -e @ansible/vars/ci-images.yml --syntax-check

# Changes the EC2 host: operator runs this command.
ansible-playbook -i ansible/inventory/ci.yml \
  ansible/playbooks/configure_ci_demo.yml \
  -e @ansible/vars/ci-images.yml \
  -e @ansible/inventory/ci-secrets.yml --ask-vault-pass
```

The playbook installs exact Jenkins LTS, Java 21 and Docker package versions from the fixed package snapshot, installs the checksum-verified Node archive, enables swap, configures kernel/descriptor limits, and installs systemd services. It generates a database password on the host without printing it or storing it in Git/Terraform. Reruns reuse the password and volumes. Never delete only the environment file while preserving the database volume: a regenerated password would not update the existing PostgreSQL user.

SonarQube's dedicated units and containers must be managed through systemd; do not separately configure Docker restart policies. By default Ansible leaves SonarQube and PostgreSQL stopped, including on reruns. Do not rerun provisioning during an active build. Set `-e ci_sonar_running=true` only if you deliberately want them running afterward.

Ansible installs all direct and mandatory transitive plugins from `ansible/vars/ci-jenkins-plugins.json`. It checks checksums before startup, stops Jenkins only when plugin archives need replacement, and refuses unmanaged/disabled archives instead of silently deleting them. It verifies all locked versions are active through the authenticated Jenkins API. No plugin manager UI or moving dependency resolution is part of provisioning.

`ci-jenkins-casc.yml.j2` manages the administrator, authentication, one executor, `NodeJS24` path, lifecycle environment and URL. The password is deployed via the JCasC file secret source in `/etc/jenkins/ci-secrets`, readable only by root and the Jenkins group; `no_log` and `diff: false` protect Ansible output. `ci-jenkins-job.groovy.j2` defines the branch-specific `mod9-secure-ecs` pipeline **disabled** until remote source and gates are ready. Reapplying the declared configuration disables that job again intentionally. Do not make permanent UI changes; edit the managed files and rerun Ansible.

The next [security setup playbook](../../docs/CI_SECURITY_SETUP.md) manages scanner binaries, SonarQube project/gate/token provisioning and the ready Snyk token. Its live execution and actual scan results remain to be validated. Webhook/TLS and AWS release permissions remain integration work. No pipeline runs or publishes merely because either host playbook finishes.

## 4. Access and initialize services

Run a tunnel in a separate terminal:

```bash
CI_HOST_IP=$(terraform -chdir=infra/ci output -raw public_ip)
ssh -N -o ExitOnForwardFailure=yes \
  -o UserKnownHostsFile=ansible/inventory/known_hosts \
  -o StrictHostKeyChecking=yes -o IdentitiesOnly=yes \
  -i keys/mod9-ci \
  -L 127.0.0.1:8080:127.0.0.1:8080 \
  -L 127.0.0.1:9000:127.0.0.1:9000 "ec2-user@$CI_HOST_IP"
```

Open `http://127.0.0.1:8080` and sign in as `labadmin` (or the configured `ci_jenkins_admin_id`) using the password you entered into Vault. There is no unlock/plugin/admin wizard. Ansible verifies that this login works before declaring success.

SonarQube remains stopped until explicitly requested. Use [configure_ci_security.yml](../../ansible/playbooks/configure_ci_security.yml) to manage its project, administrator credential, analysis token and Jenkins bindings; do not treat installed containers as configured SAST before this stage and actual analysis succeed. For an operator-controlled startup check on EC2:

```bash
sudo /usr/local/sbin/mod9-sonar start
# Read-only status check; do not record secrets.
curl --fail --silent http://127.0.0.1:9000/api/system/status
sudo /usr/local/sbin/mod9-sonar stop
```

For this trusted host's Jenkins job, JCasC already declares `MANAGE_LOCAL_SONAR=true`, `SONAR_HOST_URL=http://127.0.0.1:9000`, and `SONAR_SCANNER_JAVA_OPTS=-Xmx256m`. The Jenkinsfile starts SonarQube before SAST, waits for readiness, waits for analysis/gate results, then stops both services in the SAST stage's `post { always { ... } }`. Startup, readiness, and scan errors still fail the build. The outer pipeline timeout remains 60 minutes; measure actual runtime before deciding whether to extend it. Later pipeline stages remain sequential.

This job is not ready for a release until scanner tools/version pins, quality gate compatibility, GitHub branch/job/webhook, AWS role, ECR/ECS settings, and image approval have been validated. Leave `RELEASE_APPROVED=false`.

## 5. Validate the demo configuration

On EC2, inspect without changing resources:

```bash
free -h
swapon --show
df -h /
sysctl vm.max_map_count fs.file-max
sudo systemctl --no-pager status jenkins
sudo systemctl --no-pager status mod9-sonarqube mod9-sonar-db
sudo journalctl -k --no-pager | grep -Ei 'out of memory|oom|killed process' || true
sudo journalctl -u jenkins -u mod9-sonarqube -u mod9-sonar-db --since '1 hour ago' --no-pager
```

Stopped SonarQube units report inactive status until started intentionally. After startup, verify `/api/system/status` reports `UP`, record `/api/server/version`, and inspect `docker stats --no-stream`. `systemctl start` alone is not proof of completed analysis. Demonstrate actual analysis and quality gate completion, followed by SonarQube stopping before the Docker build. Repeat for the intended 1–3 demos and check for OOM kills, restarts, exhausted disk and timeouts. Keep evidence sanitized. No successful deployment, analysis, or memory reliability is claimed by local syntax validation.

The GitHub webhook still needs a reachable authenticated/TLS endpoint; SSH-tunneled UIs alone do not satisfy push-trigger validation. Cleanup, retained evidence and teardown plans remain to be reviewed separately.

References: [Jenkins Linux installation](https://www.jenkins.io/doc/book/installing/linux/), [SonarQube host requirements](https://docs.sonarsource.com/sonarqube-community-build/server-installation/server-host-requirements), [Linux prerequisites](https://docs.sonarsource.com/sonarqube-community-build/server-installation/pre-installation/linux), [PostgreSQL compatibility](https://docs.sonarsource.com/sonarqube-community-build/server-installation/installing-the-database).

## Deliberate version refresh and local verification

The plugin resolver reads the official historical version catalog, selects releases whose core baseline supports `2.580.2`, and locks all mandatory dependencies, artifact URLs, SHA256 checksums and minimum dependency requirements. The resolver is a maintainer operation, never a provisioning step:

```bash
python3 scripts/lock-jenkins-plugins.py --jenkins-version 2.580.2 > /tmp/ci-jenkins-plugins.json
# Review the complete diff and compatible core before replacing the tracked lock.
diff -u ansible/vars/ci-jenkins-plugins.json /tmp/ci-jenkins-plugins.json
```

A local cold-start checker is available as `scripts/check-jenkins-bootstrap.py --artifacts /path/to/artifacts`, where the artifact directory contains the matching Jenkins WAR and checksum-verified `plugins/*.jpi`. It launches a disposable loopback-only Jenkins with a random password, verifies every plugin version/active state, authenticates through the file secret source, checks one executor, denies anonymous access and verifies the disabled SCM job. This is separate from Ansible provisioning and creates no cloud resources. A local pass does not prove the shared 2 GiB host can run scans reliably.

Pin updates must be tested together. Mutable advisory databases and external service availability are inherently time-dependent; version pinning does not freeze scan results. Source/configuration reproducibility also does not back up Jenkins history, SonarQube's database, credentials or Terraform state. Back up required state privately before teardown. Do not auto-delete plugin or database state to force convergence.
