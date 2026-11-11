# Jenkins build 8: successful secure ECS release

Read-only verification on 2026-11-11 confirmed the operator-started `mod9-secure-ecs/8` build completed with `SUCCESS`.

| Release identifier | Verified value |
| --- | --- |
| Source commit | `b1002f65df139c3c812de894fdcdf4c994a2e356` |
| Scanned local image | `sha256:e993e82eeacc34bf5aa3d49ef323f69e5b8544537a6bc73a0d5d04e55063e3a6` |
| Published/deployed image | `447558491229.dkr.ecr.eu-north-1.amazonaws.com/mod9-ecs@sha256:3039df6513879f725a50238c5bf68ed974b454a0c75037722d8e506b17e51aec` |
| Previous task revision | `mod9-ecs-app:2` |
| Requested/completed revision | `mod9-ecs-app:3` |
| Service | `mod9-ecs-service`, desired/running 1/1 |
| Archived CycloneDX SBOM | 242 components |
| Archived application health | `{"service":"jenkins-webapp","status":"ok"}` |

The before/after snapshots archived by this build show a completed PRIMARY deployment on revision 2 before the update and revision 3 after it. The successful deployment script also required the running task to use the requested revision and published digest, the corresponding target to be healthy, and the application's health response to match the expected service.

Independent read-only AWS inspection confirmed the live service uses `mod9-ecs-app:3`, PRIMARY rollout `COMPLETED`, desired/running 1/1. A fresh HTTP health request returned the expected `status=ok` response. The metadata and SBOM quoted above were read from build 8's archived artifacts.

This verifies a manually approved Jenkins scan/build/publish/deploy/verify path. It does not establish webhook delivery, an actual rollback recovery, live scanner-error/secret rejection, alarm notification delivery or cleanup safety. The assistant performed no remote mutations, commits or pushes.
