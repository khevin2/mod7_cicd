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

`modules/monitoring_secrets` defines two encrypted, tagged Secrets Manager
containers and the exact runtime read/decrypt policy: one container for the Slack
incoming webhook and one for the Cloudflare DNS token. It intentionally defines
no secret versions or values. A later monitoring root will compose this module
with its customer-managed KMS key and EC2 role during Phase 4.

After an approved apply creates those empty containers, set each `SecretString`
out of band. Do not pass a value through Terraform variables, plans, or state.
The ignored Ansible inventory stores only the returned ARNs.

## Safe teardown order

Retain required evidence and deployment metadata. Destroy `infra/live` first,
then confirm the live Terraform state is empty before separately reviewing any
backend removal. The state bucket is versioned, encrypted, public-access-blocked,
and protected from routine destruction.
