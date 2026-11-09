# Security bootstrap: read-only live verification

Operator-run setup inspected over SSH on 2026-11-09. The assistant performed no remote configuration changes.

- Jenkins is active.
- SonarQube service logs show version `26.11.0.134175` becoming operational, followed by an operator-playbook shutdown.
- Sanitized bootstrap metadata records creation of the administrator password, private project `mod9-jenkins-webapp`, analysis user, project permissions, managed quality gate and analysis token.
- Gate `mod9-strict-security` uses `software_quality_security_rating`.
- `CI_SONAR_TOKEN` and `CI_SNYK_TOKEN` exist with mode `0640`, owner `root`, group `jenkins`; their values were not read.
- PostgreSQL is inactive and both scanner service units are disabled at boot.
- SonarQube's shutdown completed in its application logs, but its attached Docker process returned 130, leaving systemd's unit state `failed`. This was observed during shutdown, after successful bootstrap; it requires lifecycle follow-up.
- The SCM job definition remains disabled and targets `feature/secure-ecs-ec2`.
- Available host memory: approximately 1268 MiB; swap used: 45 MiB of 6 GiB; root filesystem: 12 GiB used of 40 GiB.

This verifies bootstrap results only. Repeat-run convergence, Jenkins credential loading, actual scanner authentication, analysis, gate enforcement, and shared-host analysis memory reliability remain unverified. No image publication or ECS deployment occurred in this inspection.

## Follow-up verification

The operator applied the service exit-status fix and reran security setup successfully: `ok=30 changed=4 failed=0 rescued=0`. Only the four service lifecycle tasks reported changes; scanner installation, credential files and SonarQube API configuration converged. The final authenticated Jenkins verification passed.

Read-only SSH inspection then confirmed Jenkins active, both SonarQube and PostgreSQL inactive with `Result=success`, and bootstrap metadata `changed=false`, `changes=[]`. Repeat-run configuration convergence and the corrected shutdown lifecycle are now verified. Actual SCA/SAST scans and enforcement remain pending.
