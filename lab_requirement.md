# Project: Advanced observability & distributed tracing (Prometheus + Grafana + Jaeger)

**Objective:** Extend your existing containerized web app to implement end-to-end observability with custom metrics, log correlation, and distributed tracing using OpenTelemetry, Prometheus, and Jaeger. Produce actionable dashboards and alerts that link latency spikes to trace spans and error logs.

---

## Instructions

- Reuse the same app (Node.js/Express or Python/Flask) and ECS/EC2 runtime from previous projects
- Add OpenTelemetry instrumentation for HTTP server, HTTP client, and DB calls (if any), exporting traces to Jaeger
- Add RED metrics (Rate, Errors, Duration) and expose `/metrics` for Prometheus to scrape
- Include `trace_id` and `span_id` in structured JSON logs; ensure CloudWatch (or Loki) captures them
- Create a Grafana dashboard for latency, error rate, CPU/memory, and trace links
- Define alert rules: error rate >5% or latency above 300ms for 10m triggers an alert
- Validate: simulate load and errors, confirm alert → trace → log correlation
- Clean up test routes; retain dashboards and alert configurations

---

## Deliverables

- App code with instrumentation
- Prometheus config
- Grafana dashboard JSON
- Jaeger setup
- Screenshots (Grafana, Jaeger, logs)
- A 2-page report mapping symptom → trace → root cause

---

## Submission requirements

| Item | Format | Contents |
|---|---|---|
| GitHub repo | App code, otel config, `prometheus.yml`, Grafana JSON, Jaeger config, screenshots, 2-page report | All project files |
| Tools evidence | Screenshot or version output | OpenTelemetry SDK, Prometheus, Grafana, Jaeger, CloudWatch/Loki (optional) |
| Correlation evidence | Screenshots | Alert → trace → log correlation showing root cause identification |