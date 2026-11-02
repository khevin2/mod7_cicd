# **Project: Secure CI/CD Pipeline (ECS + SAST/SCA)**

## **Task Definition**

Harden the CI/CD workflow for the existing containerized app by integrating SAST, SCA, container image scanning, SBOM, and secret scanning, and deploying to an Amazon ECS cluster (Fargate or EC2). Ensure quality gates block deployment when critical findings are detected.

---

## **Instructions:**

- Use the same app from Project – Complete CI/CD Pipeline with tests and a Dockerfile; store images in Amazon ECR.

- Integrate security scans: SAST (SonarQube/CodeQL), SCA (Snyk/OWASP DC), image scan (Trivy/Grype), secret scan (Gitleaks), and SBOM generation (Syft/CycloneDX).

- Fail pipeline if any Critical/High vulnerabilities or secrets are detected; archive reports.

- Build and push versioned image tags to ECR.

- Render and register a new ECS task definition revision using the new image tag.

- Update the ECS service to use the new task definition (rolling or blue/green via CodeDeploy).

- Ensure logs are sent to CloudWatch via ECS log driver and alarms from Project-Monitoring reflect the new deployment.

- Test by injecting a vulnerable dependency (pipeline should block) and verifying success after fix.

- Clean up old images (ECR lifecycle) and ECS revisions post-validation.

---

## **Deliverables:**

Jenkinsfile (or CI config), ECS task definition template and revision JSON, security reports, SBOM file, and evidence of ECS service update.

---

## **Submission Requirements**

| **Item** | **Description** |
| --- | --- |
| Format | GitHub Repo |
| Contents | CI pipeline config, ECS task definition template + rendered JSON, SBOM, reports, screenshots/logs and all associated documentation |
| Tools | SonarQube/CodeQL, Snyk/OWASP DC, Trivy/Grype, Gitleaks, Syft, AWS CLI, ECR, ECS, (Optional) CodeDeploy |
| Evidence | Failing gate on injected vuln; passing gate after fix; ECS service updated successfully and all associated documentation |
