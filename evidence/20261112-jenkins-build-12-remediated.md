# Build 12: remediation and successful release

Read-only inspection on 2026-11-12 confirms Jenkins build 12 finished SUCCESS from source `4956b190cac4ec232802b492d7a17a35fcd6a2a9`. This follows the intentionally rejected vulnerable dependency in build 11.

The fixed manifests restore Jest 30.3.0. The archived release metadata records revision `mod9-ecs-app:6`, running count 1, and image `447558491229.dkr.ecr.eu-north-1.amazonaws.com/mod9-ecs@sha256:606ea7f71ad7b64019eed5814953af2d6bf5359cbc79f79fe26fbece19e1be1b`. Jenkins archived the rendered/registered task definition, service before/update/after snapshots, running tasks, target health and application health response. The release verifier requires exact revision and digest, healthy matching targets and application health before SUCCESS.

A subsequent read-only cleanup inventory independently found a single completed stable deployment at revision 6. The failed vulnerability gate and passing remediation release satisfy the assignment's injection/fix demonstration. Cleanup remains operator work until after evidence is captured.
