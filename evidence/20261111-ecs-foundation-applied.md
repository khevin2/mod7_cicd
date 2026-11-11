# Operator-applied ECS foundations

The operator reported `36 added, 0 changed, 0 destroyed` for the reviewed foundation plan on 2026-11-11. Subsequent read-only AWS CLI checks using profile `training` confirmed:

- ECS cluster `mod9-ecs-cluster`: `ACTIVE`, zero registered container instances.
- Capacity provider `mod9-ecs-ec2` attached.
- ASG `mod9-ecs-fae4e91e97bc28b0505398a51c`: desired/minimum 0, maximum 2, no instances.

Operator outputs identify ECR `447558491229.dkr.ecr.eu-north-1.amazonaws.com/mod9-ecs`, log group `/ecs/mod9-ecs`, VPC `vpc-016cd893675aaae0c`, and ALB `mod9-ecs-alb-705673590.eu-north-1.elb.amazonaws.com`. No ECS service or task is expected until a security-approved image is published and its digest supplied to Terraform.

## Next prepared plan: CI publisher access

The local ignored `infra/ci/publisher.tfplan` contains three creates (publisher role, inline policy, instance profile) and two in-place updates (attach the profile to the CI EC2 instance; disable subnet-wide automatic public addressing). No resource replacement or deletion is planned. The CI instance explicitly retains its public-address setting.

The publisher role is scoped to the one ECR repository, plus the required registry authentication action. It grants no ECS deployment permissions. The module input defaults to null for other existing callers. Local pinned Trivy configuration scanning passed with no High/Critical findings under the documented demo policy; Ansible syntax validation passed. This IAM plan has not been applied by the assistant, and publication has not yet been verified.
