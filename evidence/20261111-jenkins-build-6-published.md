# Jenkins build 6: approved image published to ECR

Read-only verification on 2026-11-11 confirmed Jenkins `mod9-secure-ecs/6` completed with `SUCCESS`, `PUBLISH_APPROVED=true`, and `RELEASE_APPROVED=false`.

- Source commit: `0037669d1f00a4308312f586a4c17b5ecc2cbec4`.
- Scanned local image ID: `sha256:a77de1209097af6de1ccf4f86fd4776f44b745276fbb6367c41a90eb3ad482c0`.
- ECR tag: `0037669d1f00a4308312f586a4c17b5ecc2cbec4-6`.
- Published immutable image: `447558491229.dkr.ecr.eu-north-1.amazonaws.com/mod9-ecs@sha256:d9c9bd62ced94aa14ac1618d92ca713c5ac2de2b8005c3381cd7f5eccff5a4c2`.
- ECR `describe-images` independently confirmed the tag/digest association and Docker schema-2 image manifest media type.

The successful pipeline ran its security gates before publication and its publisher verified that pulling the ECR digest resolved to the scanned local image ID. The quoted identifiers came from this build's archived metadata. ECS deployment was disabled for this build. AWS ECR publication was performed by the operator-started Jenkins build, not by the assistant.

The digest is now recorded in ignored `infra/ecs-ec2/terraform.tfvars` for a separate service bootstrap plan. Keep that bootstrap value non-null and unchanged on subsequent infrastructure applies; later Jenkins release integration owns service revision changes. A deployed ECS task and live health/log evidence remain pending.

The saved local `infra/ecs-ec2/bootstrap-service.tfplan` was inspected: exactly two creates (task definition and ECS service), no updates/deletions. It requests one task with UID 10001, the quoted immutable ECR digest, explicit container health checks, `awslogs`, and deployment circuit-breaker rollback. Terraform waits for service steady state. ECS managed scaling may launch up to two application hosts within the existing ASG limit.

The first draft plan attempted to remove ECS's automatically added `AmazonECSManaged` ASG tag. Local `compute.tf` now declares the existing empty-valued, propagated tag, and the regenerated plan leaves the ASG unchanged. This follows the [provider's capacity-provider guidance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_capacity_provider). The assistant did not apply the service plan.
