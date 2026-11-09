# Reproducible CI security setup

This stage changes the existing CI EC2 host only when the operator runs Ansible. The assistant prepares/validates local source and reads live state; it does not run host provisioning, mutate AWS or commit. Run one provisioning process at a time, with no active Jenkins builds.

Prerequisite: `configure_ci_demo.yml` completed successfully and the declared Jenkins administrator can authenticate. The pipeline remains disabled. Snyk account/token readiness was confirmed on 2026-11-09; token validity against a real SCA test is still unverified.

## Private inputs

Edit the existing encrypted file; preserve the Jenkins password already in it:

```bash
ansible-vault edit ansible/inventory/ci-secrets.yml
```

Add these fields with your actual private values inside the Vault editor:

```yaml
ci_sonar_admin_password: "REPLACE_WITH_YOUR_SONAR_ADMIN_PASSWORD"
ci_sonar_analysis_password: "REPLACE_WITH_A_DIFFERENT_ANALYSIS_PASSWORD"
ci_snyk_token: "REPLACE_WITH_YOUR_SNYK_API_TOKEN"
```

Both SonarQube passwords must be distinct, at least 16 characters, and contain uppercase, lowercase, a digit and a special character. Keep them different from your Jenkins/Vault passwords. Never paste their values into chat, plain source, command-line extra-vars, logs or evidence. This stage does not change an unknown existing SonarQube administrator password: it accepts the declared password or performs the initial change from `admin`/`admin`; any other existing password fails closed.

To diagnose input validation without provisioning, run:

```bash
ansible-playbook -i ansible/inventory/ci.yml \
  ansible/playbooks/configure_ci_security.yml \
  -e @ansible/inventory/ci-secrets.yml \
  --ask-vault-pass --tags validate_inputs
```

This gathers host facts and checks input format only; it does not authenticate the supplied credentials or change host configuration. Failures name the field and unmet requirement without showing values. Correct those fields with `ansible-vault edit`, then run the full command below.

## Operator command

From the repository root:

```bash
ansible-playbook -i ansible/inventory/ci.yml \
  ansible/playbooks/configure_ci_security.yml \
  -e @ansible/inventory/ci-secrets.yml \
  --ask-vault-pass
```

No Terraform apply is needed for this stage. Download tasks verify pinned hashes and may take time. The playbook first checks your current Jenkins credential, installs tools, stops Jenkins for initial SonarQube setup, starts SonarQube, and configures its API. An `always` block stops SonarQube/PostgreSQL and restores Jenkins even when API configuration fails. The playbook fails if any required step or final verification fails; do not enable the job after a failed run.

## Managed results

- Gitleaks `8.28.0`, Trivy `0.73.0`, Syft `1.38.0`, Snyk `1.1308.4`, SonarScanner CLI `8.1.0.6389` and AWS CLI package `2.38.0` are fixed in `ansible/vars/ci-security-tools.yml`. Gitleaks/Trivy/Syft hashes come from official release metadata; Snyk from its stable release manifest. SonarScanner's SHA256 was computed from the official JVM-only archive. No moving version resolution runs during provisioning.
- Tools use root-owned version-specific installation paths and selected `/usr/local/bin` links. They are checked as the Jenkins user. SonarScanner uses the existing Java and pinned Node installation, disables JRE provisioning, and bounds JavaScript analysis heap at 384 MiB. Java scanner heap is bounded separately by Jenkins' environment.
- SonarQube keeps its existing PostgreSQL volume and generated database password. The default administrator password is changed through the API.
- Private project `mod9-jenkins-webapp` and dedicated local user `jenkins-analysis` are managed. The account is granted project Browse (`user`) and Execute Analysis (`scan`); it is not given administrator permissions. This script does not remove or rewrite global default group permissions, so audit those separately if expanding beyond this dedicated lab instance.
- Quality gate `mod9-strict-security` requires **overall security rating A** (`GT 1` blocks), using Standard or MQR metrics according to the configured server mode. This is stricter than only rejecting High/Critical confirmed security issues. The pipeline also waits for analysis and separately checks whole-project vulnerability issues. Existing source gate commands/API compatibility must still be demonstrated against actual analysis.
- SonarQube creates new gates with factory Clean as You Code conditions. The bootstrap records ownership intent before creation and replaces these factory conditions on its newly created gate with the declared overall security policy. Coverage/duplication/reliability conditions are outside this security gate's scope. It never rewrites the built-in Sonar way gate or silently removes conditions from an established managed gate. Unexpected established gate conditions fail for review. A private non-secret state marker permits interrupted initial creation to resume.
- An account-owned user token is generated with 30-day expiry and stored only at `/etc/jenkins/ci-secrets/CI_SONAR_TOKEN`. A user token is needed for both analysis and gate/issue API reads. A valid existing token belonging to the analysis user is preserved; an invalid/missing token causes only the named managed token to be replaced. The helper does not print tokens, password inputs or HTTP error bodies.
- Snyk's supplied API token is written to `CI_SNYK_TOKEN` in the same protected file secret source. JCasC declares `sonarqube-token` and `snyk-token`, plus expected CLI versions. A later foundation playbook run detects these files and preserves their credential declarations.
- Sanitized bootstrap metadata is written to `/etc/mod9-ci/sonar-bootstrap-status.json`. It records server version, project, gate, metric and change categories without secret values. The root-owned credential files remain available only to root and the Jenkins group as required by JCasC. Jenkins/Docker access remains trusted lab access.

## Read-only checks after provisioning

On EC2, these commands inspect configuration without starting services:

```bash
sudo systemctl --no-pager status jenkins
sudo systemctl show mod9-sonarqube mod9-sonar-db -p ActiveState -p UnitFileState
sudo cat /etc/mod9-ci/sonar-bootstrap-status.json
free -m
swapon --show
df -h /
```

The bootstrap metadata is safe to share after reviewing it. Do not read or share the contents of the file-secret directory or Vault. Inactive SonarQube/database units are expected at completion. The security playbook intentionally changes service state on each run to preserve the memory budget; API configuration/token creation should converge without repeated mutations when inputs and state already match.

## Acceptance still required

Local mock tests and Jenkins cold-start checks are not a live SonarQube analysis or proof of shared-host memory reliability. First validate this operator-run playbook and its repeat behavior. Then execute the actual scan-only baseline, review failed findings rather than weakening gates, test scanner errors and controlled unsafe input, and archive sanitized reports. Keep the SCM job disabled until the correct remote source, scanner APIs, secrets and required tools are ready. No image publication or ECS deployment is authorized by running this setup.

References: [SonarQube Web API](https://docs.sonarsource.com/sonarqube-community-build/extension-guide/web-api), [token behavior](https://docs.sonarsource.com/sonarqube-community-build/user-guide/managing-tokens), [scanner distribution](https://docs.sonarsource.com/sonarqube-community-build/analyzing-source-code/scanners/sonarscanner), [Snyk releases](https://docs.snyk.io/developer-tools/snyk-cli/releases-and-channels-for-the-snyk-cli). The helper uses API parameters checked against SonarSource's server implementations, including `gateName` for gate creation/selection. Live API incompatibility stops the stage rather than bypassing configuration.
