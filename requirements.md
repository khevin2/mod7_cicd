# Project: Complete CI/CD pipeline (Jenkins)

**Objective:** Design and implement an end-to-end CI/CD pipeline in Jenkins that builds, tests, containerizes a simple web service, pushes the image to a registry, and deploys it to an EC2 host.

---

## Instructions

- Create a simple app (Node.js/Express or Python/Flask) with unit tests and a Dockerfile
- Install required Jenkins plugins: Pipeline, Git, Credentials Binding, Docker, SSH Agent
- Create Jenkins credentials: `git_credentials` (optional), `registry_creds`, `ec2_ssh`
- Pipeline stages: Checkout → Install/Build → Test → Docker Build → Push Image → Deploy (SSH to EC2)
- Verify successful pipeline run and application accessibility via EC2 public DNS/IP
- Clean up residual containers/images after deployment

---

## Submission requirements

| Item | Format | Contents |
|---|---|---|
| GitHub repo | App source, tests, Dockerfile, Jenkinsfile, runbook, screenshots/logs | All project files |
| Tools evidence | Screenshot or version output | Jenkins LTS, Docker, GitHub, EC2 (Amazon Linux 2) |
| Pipeline evidence | Screenshots | Successful pipeline run (build → test → push → deploy) and accessible app |