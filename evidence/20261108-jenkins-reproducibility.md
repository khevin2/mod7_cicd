# Reproducible Jenkins bootstrap: local verification

Date: 2026-11-08. No commit was created. The assistant made no EC2 or other cloud configuration changes. The operator must run the revised Ansible playbook to deploy this version.

## Declared inputs

- CI AMI fixed to the running host's `ami-0c0427b4be074f058`; Terraform AWS provider fixed to `6.72.0` with lockfile hashes.
- AL2023 snapshot `2023.12.20261102`; exact installed Jenkins `2.580.2`, Java 21 and Docker RPM versions recorded in Ansible.
- Jenkins repository definition managed by Ansible; signing-key bytes SHA256-pinned.
- Node.js `24.18.0` archive SHA256-pinned and installed by Ansible. JCasC declares its `NodeJS24` tool path.
- Nine requested plugin roots expand to 77 direct/mandatory dependency plugins. Every artifact version, SHA256, required core, and minimum dependency version is recorded in `ansible/vars/ci-jenkins-plugins.json`. Provisioning does not resolve moving versions. Public Jenkins archive URLs avoid a redirect mirror that returned HTTP 403 during testing.
- JCasC declares the local administrator, disabled signup/anonymous access, one executor, lifecycle environment, URL, and disabled branch-specific SCM job. Administrator secret comes from a local ignored Ansible Vault file and is deployed through the file secret source with restricted permissions and suppressed diffs/logs. No live secret was added to source.
- Unmanaged/disabled plugin archives cause a clear failure rather than silent deletion. Archive mismatch triggers a controlled stop/download/restart; every plugin must load at its pinned version for Ansible to succeed.

## Executed verification

- Read-only live Terraform plan against the existing CI stack returned **no changes** after the AMI/provider pins. Saved local plan: `/tmp/mod9-ci-reproducibility.tfplan`; not applied.
- Ansible syntax validation passed, including imported tasks and pinned variable files.
- Local resolver checks passed: mandatory dependency closure, optional-dependency exclusion, incompatible core rejection, full lock closure.
- Local archive audit checks passed: missing/corrupt archives and unmanaged/disabled drift detected without deletion.
- All 77 public plugin archives downloaded into `/tmp` and checksum verified.
- Jenkins `2.580.2` WAR downloaded from the official artifact repository and SHA256 verified (`d98032d2401c540a35613a82ed358921fcf3166d5e6eaaaf60a7941845be3251`).
- `scripts/check-jenkins-bootstrap.py` cold-started a disposable loopback-only Jenkins with a 384 MiB heap, the exact locked plugins, rendered JCasC and random temporary credentials. No build, SCM clone or release was run.
- Cold-start result: **PASS**. All 77 plugins active/enabled at exact versions; administrator login through the file secret source succeeded; one executor and security enabled; anonymous API denied; managed SCM job disabled. Temporary Jenkins process was stopped and its home/credentials removed after success.
- Repository whitespace and Terraform formatting checks passed.

## Limits

This cold-start test ran locally, not on the shared 2 GiB EC2 host. It does not establish live Ansible convergence, a second-run zero-change result, SonarQube analysis, scanner readiness, or demo memory reliability. Those require operator-run provisioning and subsequent read-only verification. SonarQube project/token automation, Snyk onboarding, scanner tooling, webhook/TLS, release IAM and ECS deployment remain outstanding. Version pins do not guarantee upstream artifact availability forever or freeze advisory databases. Durable reconstruction also requires privately retained secrets, state and any application evidence/history.
