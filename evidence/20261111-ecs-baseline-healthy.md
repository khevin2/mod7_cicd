# Baseline ECS deployment verified

Read-only verification on 2026-11-11 after the operator applied the saved bootstrap service plan:

- Cluster: `mod9-ecs-cluster`.
- Service: `mod9-ecs-service`, `ACTIVE`, desired/running 1, pending 0.
- Primary deployment: `COMPLETED`, zero failed tasks, revision `mod9-ecs-app:1`.
- Running task: `35a89a1966ea478db78c89a1f2246534`, `RUNNING`, `HEALTHY`.
- Image: `447558491229.dkr.ecr.eu-north-1.amazonaws.com/mod9-ecs@sha256:d9c9bd62ced94aa14ac1618d92ca713c5ac2de2b8005c3381cd7f5eccff5a4c2`.
- ECS container `imageDigest` exactly matches Jenkins build 6's archived ECR digest.
- Task host: EC2 `i-02a755beca76f55fc`, container instance `4a361abd00cc45ab91ed19d5ea6a01f3`, connected ECS agent.
- Second registered host: EC2 `i-0ae6b427e601f04ac`, container instance `e52a129fb9ee48e2a8fefde54e29ca11`, connected agent, zero running tasks at inspection.
- Task ENI address: `10.90.1.158`. Matching ALB target `10.90.1.158:3000` is `healthy`.
- `http://mod9-ecs-alb-705673590.eu-north-1.elb.amazonaws.com/health` returned `{"service":"jenkins-webapp","status":"ok"}`.
- CloudWatch stream `/ecs/mod9-ecs`, `app/app/35a89a1966ea478db78c89a1f2246534` contains `Server listening on http://0.0.0.0:3000`.
- Registered task definition captured in `20261111-baseline-task-definition.json`.

## Deployed resource relationships

The cluster groups the two registered EC2 container instances. The task definition `mod9-ecs-app:1` specifies the immutable image, non-root container user, resource limits, explicit health check and CloudWatch logging. The service maintains one running task using this revision; ECS placed that task on one EC2 host and attached its own `awsvpc` ENI. The ALB forwards approved client traffic to the task ENI on port 3000. The ASG capacity provider manages host count independently from the service's desired task count.

This verifies initial image pull, startup logging, task placement and baseline health. It does not prove a Jenkins-driven ECS update, rolling overlap under load, rollback recovery, webhook triggering, alarm notification delivery, host replacement or cleanup safety. One application task is not highly available despite two registered hosts. No runtime change was made by the assistant.
