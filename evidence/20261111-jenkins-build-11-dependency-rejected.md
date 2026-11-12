# Jenkins build 11: injected vulnerable dependency rejected

Read-only verification on 2026-11-11 of operator-started build `mod9-secure-ecs/11`.

- Injected source commit: `e01d1aa16af5c4f3e44460f00bd640bb13496735`.
- Historical Jest 29.7.0 manifests intentionally restored the vulnerable dependency path.
- Archived Snyk report: HIGH `SNYK-JS-BRACES-19963945`, package `braces@3.0.3`.
- Jenkins console explicitly marks image build, image scan/SBOM, ECR publication and ECS deployment skipped due to earlier failure. Final result FAILURE.
- This was a scan-only run: publication and deployment approvals were false. The observed failure occurred at the dependency gate; the trial did not authorize a release.
- Before/after ECS service reads show identical task revision `mod9-ecs-app:3` and deployment IDs, desired/running count 1. The same baseline task remained RUNNING/HEALTHY with digest `sha256:3039df6513879f725a50238c5bf68ed974b454a0c75037722d8e506b17e51aec`.

The dependency remediation restores the exact previously passing Jest 30.3.0 manifests. A subsequent successful Jenkins release still needs operator execution and verification. No vulnerable fixture image was built or deployed.
