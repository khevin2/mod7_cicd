# Phase 6–7 local implementation evidence

Date: 2026-11-03. This is local-only evidence. The Jenkins job, AWS services, deployment, dashboard, alarms and notifications have not been exercised in their real environments.

## Implemented

- The Jenkins pipeline checks out the intended branch, scans and tests, records the built image ID, and performs image/SBOM gates. Push-triggered builds use the default `RELEASE_APPROVED=false`; the release stages require both an explicitly approved parameter and a manual user build cause. Operators must obtain the user's explicit authorization for the requested cloud changes.
- Release helpers use the approved AWS account, ECR image digest, ECS task revision, service health, running task digest, matching healthy target IPs, and application endpoint as checks. ECS stability alone does not imply the requested release succeeded.
- The Terraform root includes a CloudWatch dashboard and error-rate, latency, unhealthy-target and no-healthy-target alarms. SNS actions default to empty. The application does not expose the previous project's Prometheus metrics; these ALB metrics are an adaptation and must be validated live.

## Local checks

- `python3 test/test_deploy_gate.py -v`: fake AWS CLI tests for a healthy requested revision, successful waiter after rollback, wrong image digest, unhealthy ALB target, and publishing a changed image. These tests perform no cloud actions.
- `npm test -- --ci --runInBand`: existing Jest suite passed (1 suite, 4 tests). The sandboxed attempt failed because opening the local Supertest socket was denied; the successful retry ran outside the sandbox.
- `terraform -chdir=infra/ecs-ec2 validate -no-color`: passed locally using AWS provider 6.61.0. This checks syntax/schema, not AWS acceptance of metric expressions or the state of resources.
- `terraform -chdir=infra/ecs-ec2 fmt -check -recursive`, `bash -n` for release scripts, and `git diff --check`: local checks.
- Review fixes on 2026-11-03: real Trivy 0.73.0 image secret scanning passed on `mod9-openssl-fix:local` with zero findings. A disposable local image containing a synthetic token was blocked; its retained summary contained no token value, and the image was removed. `python3 test/test_security_gates.py -v` covers clean/failing/error scanner results, sanitized SonarQube diagnostics and bounded image cleanup using fake tools.
- The restored real Trivy misconfiguration gate correctly blocked the repository: six High/Critical findings were reported in `infra/ecs-ec2/network.tf` and `infra/ecs-ec2/service.tf` (AWS-0104, AWS-0164, AWS-0052, AWS-0053 and AWS-0054). These findings remain unresolved and must be reviewed before the pipeline can pass. Scanner warnings indicated required Terraform variable values were unavailable, so actual plans and configuration must also be checked.

## Still required

- Verify the full Jenkinsfile against the real Jenkins version, branch/webhook configuration, scanner binaries and credentials, SonarQube quality gate/API, Snyk service, AWS account, IAM, and target environment.
- Complete security, image and SBOM gates with trustworthy tool pins and reviewed artifacts. Test the complete pipeline's failure cases and immutable image handoff against the actual registry/service only after the user explicitly authorizes those actions.
- Review a Terraform plan before any monitoring resource changes; configure SNS only with an approved destination. Validate ALB metrics, alarm transitions/notifications, CloudWatch logs, deployment recovery and host replacement in an authorized lab. The no-healthy-target alarm intentionally breaches while there is no running baseline service.
- The fake deployment test verifies script logic only; it does not prove ECS placement, ALB connectivity, image manifest handling, permissions or a live rollback.
