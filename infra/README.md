# Terraform infrastructure workflow

The Terraform live root composes a shared VPC, a Jenkins controller-runner EC2,
and an application-host EC2. Both hosts use Amazon Linux 2023. Resources remain
inside child modules; the roots configure providers, compose modules, and expose
operational outputs.

## 1. Bootstrap remote state

Create the ignored `bootstrap/bootstrap.tfvars` with a globally unique,
non-secret `state_bucket_name` and approved owner. Terraform does not auto-load
this filename, so pass it explicitly:

```bash
cd infra/bootstrap
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -var-file=bootstrap.tfvars -out=bootstrap.tfplan
# Apply only after the saved plan has been reviewed and explicitly approved.
terraform apply bootstrap.tfplan
```

Copy sanitized bootstrap outputs into the ignored `live/backend.hcl`. Keep
`use_lockfile = true` for S3 native state locking.

## 2. Provision application and Jenkins hosts

Copy `live/terraform.tfvars.example` to ignored `live/terraform.tfvars`.
Supply approved CIDRs, ownership metadata, public-key paths, and instance settings.
Never provide private keys to Terraform.

`administrator_ssh_cidr` is the approved public `/32` used for both Jenkins SSH
administration and Jenkins HTTPS UI access. The application host continues to
accept deployment SSH from the Jenkins security group, not from a public CIDR.

When the administrator's public IPv4 changes, refresh the Terraform and Ansible
allowlists from the repository root:

```bash
./update_public_cidr.sh
```

The script validates the address, updates every Jenkins and monitoring CIDR in
the ignored local configuration, and creates the saved plan as
`infra/live/live.tfplan`. It safely replaces an older plan only after a new
plan succeeds and never applies the plan or runs Ansible.
Review the entire plan because this root uses unified state; after explicit
approval, apply that exact plan and run the playbook command(s) printed by the
script so the corresponding Nginx allowlist is updated too.

```bash
cd infra/live
terraform init -reconfigure -backend-config=backend.hcl
terraform fmt -check -recursive
terraform validate
terraform plan -out=live.tfplan
# Review the exact saved plan before approval and apply:
terraform apply live.tfplan
```

The application host exposes HTTP 80 for service verification. Its SSH ingress is
limited to the Jenkins controller security group and EC2 Instance Connect. Its
egress permits HTTPS only for registry pulls and package repositories. The Jenkins
host limits its UI to administrator CIDRs and keeps Jenkins itself on loopback behind Nginx TLS.

The direct HTTPS webhook route is intentionally opt-in:

```hcl
enable_jenkins_webhook_ingress = true
```

After setting it, create a dedicated saved plan and confirm it changes only Jenkins
security-group ingress:

```bash
terraform plan -out=jenkins-webhook.tfplan
terraform show -no-color jenkins-webhook.tfplan
# Apply only after review and explicit approval:
terraform apply jenkins-webhook.tfplan
```

AWS allows TCP 443 so GitHub can reach Nginx. The controller's Nginx configuration
restricts `/github-webhook/` to GitHub's current published hook CIDRs; this does
not make the Jenkins UI public.

## 3. Configure both hosts with Ansible

After each EC2 instance passes status checks, verify its ED25519 host-key
fingerprint through a trusted channel. Add only verified keys to the dedicated
Ansible known-hosts file.

```bash
cd ../..
cp ansible/inventory/hosts.yml.example ansible/inventory/hosts.yml
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/install_docker.yml
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/install_jenkins_controller.yml
```

The Docker playbook configures the application runtime. The Jenkins-controller
playbook configures Jenkins, Docker, Nginx, TLS, plugins, resource limits, the
GitHub webhook allowlist refresher, and the Jenkins service user's trusted
application-host key. Keep the actual inventory ignored because it contains local
paths and trusted host entries.

## Phase 3 monitoring security module

`modules/monitoring_secrets` defines three encrypted, tagged Secrets Manager
containers and the exact runtime read/decrypt policy: one each for the Slack
incoming webhook, Cloudflare DNS token, and Prometheus bcrypt htpasswd entry.
It intentionally defines no secret versions or values. The `live` root composes
this module with its customer-managed KMS key and monitoring EC2 role.

After an approved apply creates those empty containers, set each `SecretString`
out of band. Do not pass a value through Terraform variables, plans, or state.
The ignored Ansible inventory stores only the returned ARNs.

## Phase 4 monitoring infrastructure

The existing `live/` root is the single reproducible plan and state for the
application, Jenkins, and monitoring resources. It creates both non-overlapping
VPCs—application/Jenkins `10.70.0.0/16` and monitoring `10.80.0.0/16`—then
links them with one VPC peering connection, routes in both public route tables,
and narrowly scoped private TCP 9464/9100 monitoring rules. It also creates the
monitoring-only security group, SSM-managed Amazon Linux 2023 `t3.small`,
encrypted gp3 root volume, IMDSv2, Elastic IP, customer-managed KMS key, empty
monitoring secret containers, and a scoped runtime role. It intentionally
contains no Cloudflare provider, DNS record, or secret values.

Copy the existing example to an ignored local file, set the current Jenkins and
Grafana administrator `/32` values, then validate and save one plan. The
monitoring Elastic IP output is the hand-off for the user-managed DNS-only
`grafana.kheven.me` and `metrics.kheven.me` A records; verify both records before
running the TLS Ansible playbook. The same security-group TCP 443 rule restricts
both names to the approved administrator `/32`; ports 3000, 9090, and 9100 remain
unpublished.

```bash
cd infra/live
terraform init -reconfigure -backend-config=backend.hcl
terraform fmt -check -recursive
terraform validate
terraform plan -out=live.tfplan
terraform show -no-color live.tfplan
```

Do not apply until the exact saved plan, resource counts, ownership, and costs
are reviewed and approved. SSM Session Manager is the default monitoring-host
administration path. Monitoring SSH is disabled unless
`monitoring_enable_ssh = true` and an existing Ed25519 public-key path is
provided. Keep `enable_cross_vpc_private_dns = false` unless private-name
resolution is explicitly validated and needed.

## Phase 6 CloudTrail archive

The shared live root also contains a disabled-by-default `cloudtrail_archive`
module. It creates a new, dedicated lab trail only when
`enable_cloudtrail_archive = true` and a separately approved globally unique
`cloudtrail_archive_bucket_name` is provided. It never adopts an existing trail,
bucket, or KMS key. The module adds multi-Region/global management-event
collection, log-file validation, a scoped KMS key and CloudTrail bucket policy,
versioning/public-access controls, TLS-only access, and the approved archive
lifecycle. Follow [the CloudTrail archive procedure](../docs/CLOUDTRAIL_ARCHIVE.md)
for fresh discovery, saved-plan review, and runtime verification.

## Phase 7 GuardDuty

The shared live root includes a disabled-by-default `guardduty_detector` module.
It can create a new tagged detector only after current regional discovery shows
that no detector exists and the exact saved plan is approved. It intentionally
keeps optional GuardDuty protection plans disabled. Never import, alter, or
teardown an existing/shared detector. Follow [the GuardDuty
procedure](../docs/GUARDDUTY.md) for ownership checks, a synthetic sample
finding, triage, and evidence redaction.

## Safe teardown order

Retain required evidence and deployment metadata. Destroy `infra/live` first,
then confirm the live Terraform state is empty before separately reviewing any
backend removal. The state bucket is versioned, encrypted, public-access-blocked,
and protected from routine destruction.
