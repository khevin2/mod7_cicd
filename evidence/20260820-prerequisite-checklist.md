# Phase 0 Prerequisite Checklist

- Evidence date: 2026-08-20
- Time zone: Africa/Kigali
- Status: In progress
- Redaction: AWS account ID and principal name omitted; no secret values captured

## Verified

| Prerequisite | Result | Sanitized evidence |
| --- | --- | --- |
| Git repository | Local `main` tracks `origin/main` at the same initial commit | `git status`, `git log`, and branch-relation checks succeeded; `README.md` is tracked |
| Tracker privacy | `COMPLETION.md` is excluded locally | `.git/info/exclude` contains `COMPLETION.md` |
| Terraform CLI | Available | `Terraform v1.15.8` on `linux_amd64` |
| AWS CLI | Available | `aws-cli/2.35.23` |
| Git CLI | Available | `git version 2.43.0` |
| SSH client | Available | `OpenSSH_9.6p1` |
| AWS authentication | Active credentials accepted by AWS STS | `aws sts get-caller-identity` succeeded; identity details redacted |
| AWS Region | Selected and reachable | Regional EC2 API returned `eu-north-1` |
| AWS EC2 read access | Authorized in the selected Region | Sanitized VPC discovery succeeded; identifiers and counts omitted |
| GitHub access | Active CLI authentication over HTTPS | Authenticated namespace is `khevin2`; token value omitted |
| GitHub remote | Public `khevin2/mod7_cicd` repository with default branch `main` | `origin` uses HTTPS, `git ls-remote` succeeded, and authenticated permission is `ADMIN` |
| Jenkins controller | Reachable on this machine | `http://localhost:8080/login` returned HTTP 200 and Jenkins `2.568.2` LTS |
| GitHub and GHCR network paths | Reachable from the Jenkins machine | GitHub returned HTTP 200; GHCR returned the expected anonymous HTTP 401 authentication challenge |
| Jenkins SSH source | Current public IPv4 observed | Exact `/32` is kept only in the local tracker; evidence value redacted |
| SSH public key | An Ed25519 public key is available outside the repository | 256-bit key; fingerprint `SHA256:L71uWQ7EHQXhQXRGit8gEbVkZkbuUMjItps2ro43NG4` |
| Repository key-file check | No private-key, public-key, or `.tfvars` files found | Filename scan returned no matches |
| Secret marker check | No common credential or private-key markers found | Sanitized recursive content scan returned no matches |
| Evidence naming | Established | `YYYYMMDD-purpose.ext` |
| Image naming | Established | `ghcr.io/khevin2/jenkins-webapp:<git-commit-sha>` |

The successful STS and read-only EC2 requests confirm authentication and read access only. They do not confirm authorization to create the Phase 3 resources.

## Pending Decisions or Evidence

| Prerequisite | Current result | Required next input or check |
| --- | --- | --- |
| Application stack | Recommended baseline recorded, not owner-confirmed | Confirm Node.js LTS and Express |
| Jenkins build agent | Controller is reachable; agent OS and Docker/SSH execution context are not verified | Confirm the node that will execute the pipeline and its Docker access |
| GHCR push authorization | Registry and image path selected; no package-scoped Jenkins credential verified | Add a classic PAT with `write:packages` as a masked Jenkins username/password credential |
| EC2 security group | Target will be created later by Terraform | Verify HTTP and restricted SSH rules after the reviewed apply |
| Administrator SSH source | CIDR is not recorded | Provide the approved administrator public IPv4 `/32` |
| Jenkins-to-EC2 connectivity | Target does not exist yet | Test EC2 TCP 22 from the Jenkins execution node after provisioning |
| Terraform compatibility | CLI version recorded; implementation constraints do not exist yet | Confirm against the implemented Terraform and provider constraints in Phase 3 |

## Commands Executed

The following read-only checks were run from the lab environment:

```text
git status --short --branch
git remote -v
git log -1
git ls-files
git ls-remote --symref origin HEAD
gh repo view --json nameWithOwner,url,visibility,viewerPermission,defaultBranchRef
gh auth status
gh api user --jq .login
terraform version
aws --version
aws configure get region
aws sts get-caller-identity
aws ec2 describe-regions --region eu-north-1
aws ec2 describe-vpcs --region eu-north-1
git --version
ssh -V
ssh-keygen -lf <public-key-path>
find <repository> <key-and-tfvars-filename-filters>
curl <local-jenkins-login-endpoint>
curl <github-and-ghcr-endpoints>
curl <public-ip-check-endpoint>
```

Command output containing identity details was redacted rather than stored verbatim.
