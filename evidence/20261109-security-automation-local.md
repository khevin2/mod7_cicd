# CI security automation: local preparation and checks

Date: 2026-11-09. No commits or remote configuration changes were made by the assistant. The operator must execute the prepared security playbook before live acceptance can be recorded.

## Live read-only baseline

SSH inspection confirmed Jenkins active with zero recorded systemd restarts, SonarQube/PostgreSQL inactive, Node.js `v24.18.0`, and all installed Jenkins plugin archives matching the lock with no unexpected, disabled or mismatched archives. Host memory was 1913 MiB total with roughly 1134 MiB available; about 6 GiB swap was enabled. AWS CLI `2.38.0` is installed as an AL2023 RPM. The user confirmed a Snyk account and API token are ready; the assistant did not read the token.

## Prepared source

- `configure_ci_security.yml`: validates private inputs, installs fixed scanner artifacts, frees memory by stopping Jenkins during SonarQube bootstrap, configures project/account/gate/token, binds credentials through the JCasC file secret source, and stops SonarQube/restores Jenkins in an always block. The operator supplies private values through the existing encrypted Vault file.
- Fixed scanner artifact versions/checksums and runtime configuration in `ci-security-tools.yml`. Actual installation and version execution on EC2 remain pending the operator run.
- SonarQube API helper: changes the default administrator password, creates the private project and non-admin analysis account, grants project permissions, requires overall security rating A using the configured Standard/MQR mode, verifies the result, persists a 30-day analysis token privately and preserves valid tokens on reruns. Unexpected established gate conditions, privilege drift and API failures block completion.
- Factory conditions on a newly created managed gate are replaced with the declared security-only policy, with a private state marker supporting interrupted initialization. The built-in Sonar way gate is untouched. The policy/rationale and remaining live checks are documented in `docs/CI_SECURITY_SETUP.md`.
- Jenkins credential declarations survive later foundation reruns after the corresponding file secrets exist. The SCM job stays disabled; no scan, publication or ECS release runs during provisioning.

## Executed local checks

- Both Ansible playbooks pass syntax checks; new YAML and Python parse successfully.
- Ten mock API tests pass: first-run convergence, zero API mutations on a second completed run, Standard/MQR metric choice, unknown administrator rejection, non-admin analysis-account requirement, gate drift detection, failed condition creation, interrupted factory cleanup, invalid token replacement, threshold correction and HTTP response-body redaction (some scenarios share tests).
- Fresh disposable local Jenkins cold-start passes with all 77 exact plugins, new scanner credential declarations, synthetic file-secret values, one executor, authentication and disabled SCM job. No build or scanner was run in that instance; temporary credentials/home were removed after success.
- Official JVM-only SonarScanner ZIP downloaded locally, checksum recorded, and executable reports `8.1.0.6389` on the existing Java 21 runtime. This is a version check, not analysis evidence.
- Local Gitleaks `8.30.1` checks on Ansible and test files are clean after metadata normalization. Its initial generic API-key findings were public dependency version values and a signing checksum, not user credentials. Dependency minima now use explicit name/version records, and the public signing digest variable no longer resembles a secret field. No exclusion was added. These checks use a different version from the pinned release gate and do not establish a full-history secret gate pass.
- `git diff --check` passes.

## Unverified acceptance

No live SonarQube startup/API bootstrap, scanner installation on EC2, Snyk authentication/SCA assessment, SAST analysis, image scan, SBOM or security-approved release is claimed. The 2 GiB host's memory reliability still needs live demonstration. API parameters were checked against official server implementations, including `gateName` and factory condition creation; only actual operator-run provisioning/analysis can establish compatibility with the pinned server image. Inspect and sanitize live artifacts before submitting them.
