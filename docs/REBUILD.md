# Rebuild the lab with one command

`scripts/lab.sh` coordinates the existing Terraform, Ansible and Jenkins workflows. It provisions the CI host, configures Jenkins/SonarQube/scanners, creates ECS/ECR foundations, publishes a scanned bootstrap image, creates the initial service, configures scoped release access, and runs a complete Jenkins release. It then verifies the requested ECS revision, running image digest, task health, matching ALB targets and application response.

This first version supports the existing account `447558491229`, region `eu-north-1`, repository `khevin2/mod7_cicd`, branch `feature/secure-ecs-ec2` and application resource names. These values are also embedded in existing infrastructure and pipeline code. Configuration for another account/region is rejected. It uses the existing Terraform roots and their state; it does not create a parallel stack or adopt arbitrary existing deployments.

## Prepare once

Use a Linux controller with Python 3, AWS CLI, Terraform 1.10–1.x, Git, OpenSSH and the pinned Ansible controller:

```bash
python3 -m venv .venv-ci
. .venv-ci/bin/activate
python3 -m pip install -r ansible/requirements-ci.txt
cp lab.example.json lab.local.json
```

Edit ignored `lab.local.json`:

- Set `owner`, the AWS CLI profile and your actual public IPv4 `/32` as `admin_cidr`.
- Replace the example HTTP client CIDRs. The script also allows the administrator and new Jenkins host `/32` through the ALB so both can verify application health.
- Provide an existing Ed25519 private key, its matching `.pub` file, an encrypted Ansible Vault file and a private Vault-password file. Relative paths resolve from the repository root; absolute paths are accepted. These files must remain available outside the resources being destroyed. Private files must have owner-only permissions.
- Populate Vault with all four fields from [the secret input example](../ansible/vars/ci-secrets.yml.example): Jenkins administrator password, distinct SonarQube administrator/analysis passwords, and an authorized Snyk token. The script decrypts/validates inputs locally before creating infrastructure. It cannot establish Snyk service authentication until the real scan runs.

Create missing SSH/Vault files using the [CI setup instructions](../infra/ci/README.md). Keep the Vault password outside the repository and restrict its permissions with `chmod 600`. For a passphrase-protected SSH key, load it into your SSH agent before starting. Do not put secret values in the JSON configuration or command arguments.

Commit and push this implementation and all intended pipeline changes to the configured branch. The script requires a clean checkout whose commit matches the published branch. Jenkins reads that remote source; the orchestrator also configures an expected-commit check so a branch change between preflight and checkout fails before publication/deployment.

## Run

Read-only preflight (apart from local temporary files):

```bash
./scripts/lab.sh check --config lab.local.json
```

Create/configure the lab, publish the scanned bootstrap image and deploy a verified release:

```bash
./scripts/lab.sh up --config lab.local.json --yes
```

`up --yes` explicitly authorizes all these operations. Without `--yes`, the command asks for rebuild authorization and confirmation of each Terraform plan that changes resources. Terraform plan output is shown in either mode. The script refuses every deletion/replacement plan, even with `--yes`; review and perform such changes separately. There is no automatic destroy, secret rotation, rollback fault injection, cleanup demonstration or notification test in `up`.

The SSH key is checked against the instance's trusted EC2 boot-console fingerprint before being written to the lab's managed `known_hosts`. The command stops if it cannot establish trust; it never disables strict host-key checking.

The bootstrap image is obtained from the successful Jenkins build's archived digest. It stays non-null and unchanged in subsequent infrastructure plans so Terraform retains the service while Jenkins owns later revisions. A final release builds/scans again. Mutable vulnerability databases can reject a later build even when an earlier build passed; the script preserves that failure.

Progress and build IDs are stored under ignored `build-metadata/lab/`, with owner-only file permissions. Terraform state stays in its existing roots. Generated inventory, release settings, plans and inputs remain ignored. Do not commit these files.

## Resume and recover

```bash
./scripts/lab.sh status
./scripts/lab.sh up --config lab.local.json --yes
```

Rerunning refreshes/plans infrastructure, checks CI/ECS identities, verifies SSH trust, skips completed host configuration, and monitors the exact recorded Jenkins queue item/build. A completed workflow queues no new builds and rechecks deployment health. A changed source commit, config, encrypted Vault contents or SSH public key requires an explicit new run; old checkpoints cannot silently authorize changed inputs. An unexpected instance/VPC replacement also stops the workflow.

There is a small unavoidable ambiguity if the controller loses contact after Jenkins accepts a build but before its queue ID is saved. The script stops rather than queuing a duplicate. Inspect Jenkins, identify the exact accepted build and recover it explicitly:

```bash
./scripts/lab.sh up --config lab.local.json --yes --recover-build 7
```

This is also the recovery path if Jenkins expires a recorded queue item before the build number is saved. The recovered build must match the expected publication/deployment choices, source commit and image repository. Failed/cancelled builds are not retried automatically. Resolve the cause, ensure the previous build has stopped, and start a reviewed new run. Do not run provisioning from another terminal or enable competing release jobs while rebuilding.

After intentional teardown, begin with fresh checkpoints:

```bash
./scripts/lab.sh up --config lab.local.json --yes --restart
```

`--restart` archives the old journal/build records and clears its bootstrap digest. It does not delete Terraform state or cloud resources. Terraform refresh handles externally deleted resources when it can determine they are absent. Partial deletion, retained bootstrap task revisions, unmanaged leftovers, name collisions and proposed replacements may require separate review/import/cleanup. Restart is intended for rebuilding after teardown; use the ordinary release playbook to update a running lab to a new source commit.

Preserve Terraform state until teardown is verified. Never delete state to make an apply pass. The script's lock covers this checkout only: local state does not coordinate multiple machines. Preserve state and encrypted/private inputs separately before deleting compute or storage. Existing ECR `force_delete=false` and ECS `skip_destroy` settings still apply during a separate teardown.

## Reliability and validation

The component workflows have archived live evidence, but this orchestrator has **not yet been tested by destroying and rebuilding the AWS environment**. Local tests cover operation ordering, interrupted build recovery, completed-run behavior, checkpoint/configuration changes, concurrent invocation, SSH fingerprint validation and rejection of destructive plans. Ansible syntax validation does not prove remote provisioning or Jenkins API behavior.

Remaining dependencies include AWS quotas/capacity, credentials and permissions, SSH reachability, pinned AMI/package/archive availability, GitHub/Docker Hub/scanner availability, current vulnerability findings and the constrained shared CI host. The documented Trivy infrastructure exceptions expire on 2026-12-10 and require review before a later rebuild. Jenkins history and SonarQube data are recreated, not restored. Existing public webhook and notification limitations remain.

Acceptance requires an authorized rebuild from empty infrastructure, a repeat `up` with no new Jenkins builds, and an interrupted/resumed run. Compare the final revision/digest/health records and confirm the expected resource scope and costs. Until that is demonstrated, treat the script as locally tested rebuild automation, not a guaranteed recovery procedure.
