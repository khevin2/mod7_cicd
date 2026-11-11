# ECS release automation prepared locally

Prepared on 2026-11-11 after verifying the baseline service. The assistant performed read-only AWS checks, local edits/tests, and saved-plan preparation only; no policy attachment, build, publication or deployment was executed.

## Prepared operator actions

- Ignored inputs were generated from existing Terraform outputs and read-only service/account identity checks. They bind the release to `mod9-ecs-service`, task family `mod9-ecs-app`, and its deployed execution role in account `447558491229`, region `eu-north-1`.
- `infra/ci/ecs-release.tfplan` contains one create: `aws_iam_role_policy.ecs_release[0]`. No other resource update, replacement or deletion is planned.
- The Ansible release wrapper explicitly requests publication and deployment for one new build. Default scan and publish-only invocations retain their prior approval defaults.
- JCasC receives six generated non-secret release settings and preserves the SonarQube/Snyk file-secret bindings. Configuration stays in Ansible; no manual Jenkins environment editing is required.

## Validation

- Seven generator tests passed: correct scoped derivation and rejection of foreign account/role, wrong service/family, inactive service, and unapproved health endpoint.
- Five existing deployment/publishing checks passed, including rollback despite waiter success, wrong running image digest, unhealthy target, and changed-image rejection before publication.
- Ansible syntax checks passed for the release wrapper and foundation/security playbooks. The optional inventory/default variable-file fallback was checked before and after generating the inventory file.
- Rendered JCasC parsed as YAML with all release settings and both unchanged file-secret credential references.
- AWS Access Analyzer `validate-policy` returned no findings for the compiled policy.
- AWS IAM custom-policy simulation permitted updating the intended service, registering its task family, and passing its execution role; corresponding unrelated resources returned `implicitDeny`.
- Pinned local Trivy `0.73.0` source misconfiguration scanning exited 0 under the documented demo policy. This is local evidence, not the next Jenkins build result.

Registration is restricted to the application task-definition family; service mutation is limited to the named service and that family. `iam:PassRole` is limited to the one execution role and ECS tasks service. Cluster task listing and regional ELB health inspection use the scope supported by AWS's action authorization model. This role has no permissions to create/delete services or mutate networking/host capacity/IAM.

The operator must apply the reviewed IAM plan, commit/push the source, and run the release playbook. The live requested revision, image digest, target health and artifacts remain to be verified after that build. Webhook triggering and subsequent monitoring/rollback/cleanup acceptance remain outstanding.
