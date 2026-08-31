# Project 6: Full observability & security solution

**Objective:** Extend the existing containerized web application to implement a complete observability and security stack using Prometheus, Grafana, and AWS services (CloudWatch, CloudTrail, and GuardDuty).

---

## Instructions

- Use the existing containerized app from Project – CI/CD, ensuring it exposes metrics at `/metrics`
- Provision Prometheus on a new EC2 instance or container. Configure to scrape metrics from the app and Node Exporter
- Deploy Grafana connected to Prometheus, create dashboards for latency, requests per second, and error rates
- Configure alerts for high error rates (>5%) using Grafana or Prometheus rules
- Enable CloudWatch Logs and configure Docker to stream container logs to CloudWatch
- Enable AWS CloudTrail and GuardDuty for account activity and threat detection
- Store CloudTrail logs in an S3 bucket with encryption and lifecycle policies
- Verify monitoring, alerts, and security detections are working
- Clean up monitoring EC2 instances and AWS resources after verification

---

## Deliverables

- Prometheus and Grafana configurations
- Screenshots of dashboards and alerts
- CloudWatch and GuardDuty outputs
- A 2-page report summarizing insights

---

## Submission requirements

| Item | Format | Contents |
|---|---|---|
| GitHub repo | `prometheus.yml`, Grafana dashboard JSON, screenshots, 2-page report | All project files |
| Tools evidence | Screenshot or version output | Prometheus, Grafana, AWS CloudWatch, CloudTrail, GuardDuty |
| Monitoring evidence | Screenshots | Functional dashboards, alerts triggered, AWS logs and events recorded |