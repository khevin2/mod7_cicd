# Terraform infrastructure workflow

Phase 3 uses two composition-only roots and three child modules. Only modules
contain AWS resources or data sources; the roots configure providers, call
modules, and re-export operational outputs.

## 1. Bootstrap remote state

Create the ignored `bootstrap/bootstrap.tfvars` with a globally unique,
non-secret `state_bucket_name` and the approved `owner`. Terraform does not
auto-load this filename, so pass it explicitly when creating the saved plan:

```bash
cd infra/bootstrap
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -var-file=bootstrap.tfvars -out=bootstrap.tfplan
# Apply only after the saved plan has been reviewed and explicitly approved.
terraform apply bootstrap.tfplan
```

Use the sanitized `state_bucket_name` and `state_bucket_region` outputs to
copy `live/backend.hcl.example` to the ignored `live/backend.hcl`. Keep
`use_lockfile = true`; it enables S3 native state locking.

## 2. Provision the deployment host

Copy `live/terraform.tfvars.example` to the ignored `live/terraform.tfvars`
and replace its placeholders with the approved Jenkins and administrator public
`/32` CIDRs, owner, and existing Ed25519 public key. Private keys must never be
provided to Terraform.

```bash
cd infra/live
terraform init -reconfigure -backend-config=backend.hcl
terraform fmt -check -recursive
terraform validate
terraform plan -out=live.tfplan
# Review the saved plan and request explicit approval before this command.
terraform apply live.tfplan
```

The network exposes TCP 80 publicly for application verification. SSH on TCP
22 accepts only the two approved public `/32` addresses. Egress is limited to
HTTP/HTTPS, DNS, and NTP required for Amazon Linux 2023 packages, Docker registry
pulls, name resolution, and time synchronization.

## 3. Configure Docker with Ansible

After the instance passes its EC2 status checks and SSH host-key fingerprint is
verified through a trusted channel, copy the ignored inventory template and
replace its placeholders. Keep the private-key path local and do not commit the
resulting inventory.

Before running the playbook, obtain the hosts ED25519 fingerprint through a
trusted channel, such as the EC2 Instance Connect console. Scan the public key
once, compare its SHA256 fingerprint to the trusted value, and copy it to the
dedicated Ansible known-hosts file only when they match.

```bash
cd ../..
cp ansible/inventory/hosts.yml.example ansible/inventory/hosts.yml
ssh-keyscan -t ed25519 <EC2_PUBLIC_DNS_OR_IP> > /tmp/deployment_host_keyscan
ssh-keygen -lf /tmp/deployment_host_keyscan
# Compare this fingerprint with the trusted value before continuing.
install -m 600 /tmp/deployment_host_keyscan ansible/inventory/known_hosts
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/install_docker.yml
```

The playbook is idempotent and intentionally fails on non-Amazon-Linux-2023
hosts. It installs Docker, enables and starts its service, and adds the SSH
deployment user to the `docker` group. Verify `docker version` from a new SSH
login before allowing Jenkins to deploy.

## Safe teardown order

Destroy `infra/live` first after retaining required evidence and confirming
there is no needed deployment state. Confirm the live state is empty before
considering backend removal. The state bucket has versioning, encryption,
public-access blocking, `force_destroy = false`, and Terraform
`prevent_destroy`; removing it requires a deliberate, separately reviewed
change after state versions and backups are handled.
