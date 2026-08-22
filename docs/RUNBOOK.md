# Jenkins CI/CD deployment runbook

Use this runbook for the Express service in this repository. Replace all
angle-bracketed placeholders locally. Never commit or print credentials, tokens,
private keys, host keys, account IDs, or unredacted endpoints.

## Prerequisites and credentials

The Jenkins execution node needs Git, Docker Engine, Node.js 24, OpenSSH, and
network access to GitHub, Docker Hub, GHCR, the Trivy vulnerability databases, and
the deployment host TCP 22. The pipeline downloads the database from
ghcr.io/aquasecurity/trivy-db:2. Jenkins requires Pipeline, Git, Credentials
Binding, Docker Pipeline, SSH Agent, and NodeJS plugins, with a NodeJS installation
named NodeJS24. Trivy runs from the digest-pinned aquasec/trivy container and needs
no Jenkins plugin or host installation.

| ID | Type | Use |
| --- | --- | --- |
| registry_creds | Username with password | GHCR push and deployment pull |
| ec2_ssh | SSH Username with private key | SSH Agent deployment login |

Keep credential values only in Jenkins. The Jenkinsfile fixes ghcr.io,
khevin2/jenkins-webapp, and registry_creds as trusted configuration; callers cannot
redirect registry credentials with build parameters. Verify the EC2 ED25519 key via
a trusted channel and install it in the Jenkins runtime user known_hosts. The
deployment uses StrictHostKeyChecking=yes; do not weaken it.

## Provision and configure the host

Terraform roots are composition-only and use reviewed saved plans. Local
bootstrap.tfvars, backend.hcl, and terraform.tfvars are ignored; supply only
approved non-secret values and an existing public Ed25519 key.

~~~bash
cd infra/bootstrap
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -var-file=bootstrap.tfvars -out=bootstrap.tfplan
# Apply only after saved-plan review and explicit approval:
terraform apply bootstrap.tfplan

cd ../live
terraform init -reconfigure -backend-config=backend.hcl
terraform fmt -check -recursive
terraform validate
terraform plan -out=live.tfplan
# Apply only after saved-plan review and explicit approval:
terraform apply live.tfplan
~~~

The security group permits public TCP 80 and limits TCP 22 to approved Jenkins and
administrator public /32 CIDRs. After trusted host-key verification:

~~~bash
cp ansible/inventory/hosts.yml.example ansible/inventory/hosts.yml
ssh-keyscan -t ed25519 <EC2_PUBLIC_DNS_OR_IP> > /tmp/deployment_host_keyscan
ssh-keygen -lf /tmp/deployment_host_keyscan
# Compare the fingerprint with the trusted value before continuing.
install -m 600 /tmp/deployment_host_keyscan ansible/inventory/known_hosts
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/install_docker.yml
~~~

The playbook asserts Amazon Linux 2023, installs/enables Docker, and adds the SSH
user to the Docker group. Start a fresh SSH session and verify docker version.

## Configure and operate Jenkins

Create a Pipeline-from-SCM job using this repository Jenkinsfile, configure the
credentials above, then supply:

~~~text
DEPLOY_HOST=<EC2_PUBLIC_DNS_OR_IP>
DEPLOY_USER=ec2-user
DEPLOY_PORT=80
~~~

Required order: Checkout, Install and Validate, Test, Trivy Repository Scan,
Docker Build, Trivy Image Scan, Push Image, Deploy, Runtime Cleanup. The job
publishes a full-commit-SHA tag, deploys the immutable digest in
build-metadata/image-digest.txt, health-checks a temporary candidate, archives
test/metadata/non-secret security reports, then deletes its workspace in post.

## Security gates

The pipeline uses one scanner, Trivy, for dependency vulnerabilities, Terraform
and Dockerfile misconfigurations, repository secrets, image vulnerabilities, and
image secrets. The scanner image is pinned to both version 0.73.0 and an immutable
manifest digest. Repository and image gates fail on fixable HIGH or CRITICAL
findings. Informational JSON reports contain vulnerability and misconfiguration
results at all severities; secret results stay inside the ephemeral scanner
container and are never archived.

Checkout starts with deleteDir(), so ignored local credentials, Terraform plans,
and stale scanner/build files cannot enter the Jenkins workspace. The repository
scans also skip .git, node_modules, and ignored *.tfplan files. The runtime image
does not include npm or npx because they are required only in the dependency stage;
removing them eliminates an unused package-management attack surface.

Three current Terraform findings are accepted at the narrowest resource scope
because removing them would conflict with this lab architecture:

- A public subnet address is required for the direct EC2 public endpoint.
- Port-restricted egress must reach registries, package repositories, DNS, and NTP,
  whose public destination addresses are not stable.
- SSE-S3 protects the isolated lab state; the brief does not mandate a
  customer-managed KMS key.

Each exception is an inline Trivy annotation immediately above the affected
resource and expires on 2027-08-22. Review or remove the exception earlier if the
design adds a load balancer/private subnet, controlled egress, or a KMS policy. Do
not replace these with a global ignore file.

To reproduce the blocking repository checks locally from a source-only checkout:

~~~bash
TRIVY_IMAGE='aquasec/trivy:0.73.0@sha256:7cced7cae583819fc7806d4cbc0dbbc7cad18b99f7d3e235192e6da8c091045c'
TRIVY_DB='ghcr.io/aquasecurity/trivy-db:2'
docker volume create jenkins-webapp-trivy-cache
docker run --rm -v "$PWD:/workspace:ro" -v jenkins-webapp-trivy-cache:/root/.cache/trivy "$TRIVY_IMAGE" fs \
  --db-repository "$TRIVY_DB" --scanners vuln,misconfig --severity HIGH,CRITICAL \
  --ignore-unfixed --exit-code 1 --skip-dirs /workspace/.git \
  --skip-dirs /workspace/node_modules --skip-files '**/*.tfplan' /workspace
docker run --rm -v "$PWD:/workspace:ro" -v jenkins-webapp-trivy-cache:/root/.cache/trivy "$TRIVY_IMAGE" fs \
  --db-repository "$TRIVY_DB" --scanners secret --severity HIGH,CRITICAL \
  --exit-code 1 --skip-dirs /workspace/.git --skip-dirs /workspace/node_modules \
  --skip-files '**/*.tfplan' /workspace
~~~

## Verify a deployment

~~~bash
curl --fail --silent --show-error --max-time 15 http://<EC2_PUBLIC_DNS_OR_IP>/
curl --fail --silent --show-error --max-time 15 http://<EC2_PUBLIC_DNS_OR_IP>/health
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=<VERIFIED_KNOWN_HOSTS_FILE> ec2-user@<EC2_PUBLIC_DNS_OR_IP> \
  'docker ps --filter name=jenkins-webapp; docker inspect --format="{{.State.Health.Status}}" jenkins-webapp'
~~~

Confirm HTTP 200, exactly one healthy jenkins-webapp container, port mapping 80:3000,
and a digest matching the archived successful-build metadata. Store only sanitized
output under evidence.

## Rollback and downtime

Candidate health is checked before cutover, but replacing the single port-80
container causes brief downtime. The pipeline attempts automatic rollback if
post-cutover health fails. For manual rollback, obtain the previous known-good
digest from build metadata or host inspection:

~~~bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=<VERIFIED_KNOWN_HOSTS_FILE> ec2-user@<EC2_PUBLIC_DNS_OR_IP>
docker rm -f jenkins-webapp
docker run -d --name jenkins-webapp --restart unless-stopped -p 80:3000 \
  ghcr.io/khevin2/jenkins-webapp@sha256:<PREVIOUS_KNOWN_GOOD_DIGEST>
curl --fail --silent --show-error --max-time 10 http://127.0.0.1:80/health
~~~

Retain active and previous tagged images until rollback is no longer needed.

## Cleanup and teardown

Runtime Cleanup removes only jenkins-webapp-candidate, dangling layers, and the
host GHCR login; it retains tagged active/rollback images and checks health/disk
capacity. Do not use broad Docker prune commands without separate approval. The
Jenkins post block archives outputs, removes the per-build Trivy cache volume and
scanner image, then deleteDir removes the workspace. Capture a successful
post-change build before claiming the security and cleanup stages as evidenced.

Retain evidence, destroy infra/live, verify live state is empty, then separately
review any backend removal. The state bucket is versioned, encrypted, access-blocked,
and protected from routine destruction.

## Troubleshooting

| Symptom | Safe recovery |
| --- | --- |
| Git checkout fails | Confirm SCM URL and private-repo credential access; run git ls-remote against the repository URL without displaying credential-bearing URLs. |
| Install, check, or test fails | Reproduce with npm ci, npm run check, and npm test -- --runInBand; fix reviewed source/lockfile and rerun. |
| Docker permission denied | Verify id and docker version; add only the approved user to docker, open a fresh session, and recheck. Docker-group access is privileged. |
| GHCR auth/push fails | Verify the fixed registry_creds ID/type and package scope with its owner. Use docker login --password-stdin, never a command-line password. |
| Trivy cannot download its image or databases | Treat this as scanner setup failure. Verify Docker Hub/GHCR egress and DNS, then rerun; never bypass or mark the security gate successful. |
| Trivy reports HIGH/CRITICAL findings | Review the archived non-secret JSON, upgrade or reconfigure the affected component, rebuild from the same source revision, and rerun. Do not add broad ignores. |
| SSH authentication fails | Check ec2_ssh, DEPLOY_USER, approved /32 ingress, and TCP 22 reachability with BatchMode and the approved key. |
| Host-key verification fails | Stop. Compare a scanned ED25519 fingerprint with the trusted value; update known_hosts only after verified key rotation. |
| Port 80 conflict | Inspect sudo ss -ltnp '( sport = :80 )' and docker ps; remove only an approved conflicting process/container. |
| Health timeout | Inspect docker ps, candidate/application logs, and docker inspect health. Preserve the known-good app and roll back after failed cutover. |
| Disk exhausted | Run df -h / and docker system df; remove only the named candidate and dangling layers, retaining active/previous images. |

## Evidence handling

Use YYYYMMDD-purpose.ext. Redact sensitive values, keep raw captures outside Git,
and consult [the evidence index](../evidence/README.md). Archive vulnerability and
misconfiguration reports only; never retain a Trivy secret report.
