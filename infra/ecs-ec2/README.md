# ECS on EC2 lab

This separate Terraform root prepares an isolated VPC, ECR, an ALB, an ECS cluster with an EC2 Auto Scaling group and capacity provider, IAM roles, and CloudWatch logging. It does not reuse or modify the previous Terraform root or state. The app service and task definition are omitted until `release_image` is set to an approved digest from this root's ECR repository. No resources have been provisioned by writing this configuration.

## Design and limits

- Default region: `eu-north-1`. Confirm the account and budget before any plan or apply.
- Two public subnets in separate availability zones satisfy the internet-facing ALB requirement. ALB HTTP access is restricted to explicitly supplied client CIDRs; HTTP is unencrypted and is for the lab only. Add TLS before using sensitive traffic.
- A public-addressed ECS host uses HTTPS egress to reach AWS services. `awsvpc` tasks have separate ENIs, receive no public IP and have no outbound internet route/access; the application has no outbound dependency. ALB traffic reaches port 3000 on the task security group. The host exposes no SSH port; Systems Manager is installed through the ECS-optimized AMI and EC2 role.
- The Auto Scaling group starts empty. After its capacity provider is attached, ECS managed scaling launches `t3.small` x86_64 hosts when the service needs capacity. The group can scale from zero to two instances; initial scale-out may launch two, so budget for both. The service requests one task and is not highly available. Verify CPU, memory and ENI capacity for a second task during a 100%/200% rolling deployment; this configuration alone does not guarantee zero downtime or multi-AZ failover.
- The host role uses AWS-managed ECS instance and SSM policies; the execution role uses the AWS-managed task execution policy. The app has no task role. IMDSv2 is required, and ECS task access to instance metadata is blocked. ECR pull permissions are on the EC2 instance role; the execution role and agent override support CloudWatch logging.
- ECR tags are immutable. The lifecycle rule expires only images explicitly marked with a `retired-demo-` tag, one day after image push. General untagged expiry remains disabled by default; never mark an active, bootstrap or rollback digest for retirement. Lifecycle rules do not check whether ECS references an image. Review a lifecycle preview and preserve active/rollback images before enabling cleanup in a real environment. The operator removed the two reviewed broken-demo image digests after reference checks; see the cleanup runbook.
- The stack uses local Terraform state by default for an isolated lab. State is ignored by Git but is sensitive: protect and back it up. Decide on an independently configured remote backend before collaboration or deployment from a second machine; do not point it at the old stack's state key.
- The lab creates billable EC2, EBS, public IPv4, ALB, ECR, and CloudWatch resources. An AWS budget/spending limit and cleanup plan are still required. There is no automatic teardown.

## Local validation

```bash
terraform -chdir=infra/ecs-ec2 init -backend=false
terraform -chdir=infra/ecs-ec2 fmt -check -recursive
terraform -chdir=infra/ecs-ec2 validate
```

`init -backend=false` installs the provider locally; `validate` does not create AWS resources. Never commit `.terraform`, state, actual tfvars, tokens, or saved plans.

To render registration JSON locally once the real ECR digest, execution role ARN, and log group are known:

```bash
scripts/render-ecs-task.py \
  --family mod9-ecs-app \
  --image "$RELEASE_IMAGE_DIGEST" \
  --execution-role-arn "$TASK_EXECUTION_ROLE_ARN" \
  --log-group /ecs/mod9-ecs \
  --region eu-north-1 > task-definition.rendered.json
```

Review and sanitize generated output before including it in evidence. Rendering does not register a task definition or update the ECS service.

## Future provisioning and baseline deployment

These steps are an operational outline, not permission to make cloud changes. First resolve the account, client CIDR, network, cost limit, and scanner validation on the fresh installation. Obtain the user's explicit permission for each cloud-changing action, including creating resources, pushing an image, registering a revision, updating a service, or destroying resources. Review the exact plan and resource scope before any apply.

1. Configure AWS CLI access outside this repository; verify account and `eu-north-1` with read-only checks. Copy `terraform.tfvars.example` to the ignored `terraform.tfvars` and replace every placeholder. Confirm the VPC CIDR does not conflict with networks that may later be connected.
2. With `release_image` unset, review a saved Terraform plan for foundations. After explicit permission, apply only that reviewed plan. Confirm the empty Auto Scaling group and capacity provider are attached to the cluster, and inspect ECR, roles, load balancer and log group. No host is expected yet. Do not assume a plan is valid across changes to state or configuration.
3. Build the app once, run every required Phase 3 gate and generate its SBOM. After explicit permission, tag and push the same approved image to this ECR repository. Retrieve and record its ECR digest. Jenkins defaults to scan-only; its manual release path is described in [the pipeline runbook](../../docs/SECURE_ECS_PIPELINE.md) with live build 12 evidence in the submission index.
4. Set `release_image` to that repository URL followed by `@sha256:<digest>`. Review a new saved plan; it must create the task definition and ECS service with the expected image and no unrelated changes. After explicit permission, apply that exact plan.
5. Confirm ECS managed scaling starts capacity and the instances register with the capacity provider. Verify host outbound connectivity, ECS service events and task revision, task placement, image digest, ALB target health, `/health`, and the corresponding CloudWatch log stream. Save sanitized task definition input, registered revision, and service evidence.

Terraform owns the initial task definition and service. Future release automation can register revisions and update the service; `ignore_changes = [task_definition]` prevents infrastructure applies from reverting that release. Terraform retains old bootstrap task revisions on replacement or destroy (`skip_destroy`); explicitly verify active and rollback usage before any later deregistration. Keep the original `release_image` value unchanged and non-null after bootstrapping: setting it back to null plans destruction of the service, and changing it would replace the Terraform-managed bootstrap revision without updating the service. Perform later releases through the release workflow. Before any apply, check the plan and the currently active revision. The later pipeline must wait for the intended revision and fail if ECS rolls back to a previous one.

For teardown, first capture evidence and inspect the exact plan. Preserve shared/unowned resources, active/rollback artifacts and the state until no longer required. ECR is configured with `force_delete = false`, so nonempty repositories need separately reviewed image cleanup. An apply or destroy requires explicit permission.
