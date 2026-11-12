# Secure Jenkins to ECS architecture

Open [architecture-ecs.drawio](architecture-ecs.drawio) in diagrams.net. The older root-level diagram belongs to the previous GHCR/SSH deployment.

1. Jenkins checks out the working branch from GitHub and validates tool versions.
2. Gitleaks, application tests, SonarQube, Snyk and Trivy gate the source and image. Syft generates the SBOM.
3. An approved manual build publishes the scanned image to ECR under an immutable commit/build tag, resolves its digest and verifies image identity.
4. Jenkins uses its scoped EC2 role to register an application task revision and update the existing ECS service.
5. ECS schedules the task on EC2 capacity. The ALB accepts approved client HTTP traffic and forwards port 3000 to the private task ENI. Release verification checks exact revision/digest, task/target health and `/health`.
6. CloudWatch receives task logs through `awslogs`; ALB/ECS metrics feed the dashboard and alarms. Notification actions are not configured.

Jenkins and SonarQube share a small CI host in a separate VPC; sequential scans and stopping SonarQube limit memory pressure. The app has no IAM task role. Instance and execution roles serve their respective capacity, registry and logging needs. The ECS circuit breaker restores a prior completed deployment after a bad release, while Jenkins still reports the failed attempted release.

The drawing uses built-in AWS stencils. ECR and CloudWatch use the skill's generic AWS cloud fallback with explicit labels. It shows logical flow rather than subnet placement for each ENI. Two subnets satisfy ALB placement; one desired app task is not highly available. Native XML validation is performed locally; a draw.io raster export is not available in this environment.
