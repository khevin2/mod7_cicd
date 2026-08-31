# Phase 11 live verification — 2026-08-30

All times below are UTC. This record intentionally contains no public addresses,
credentials, AWS account identifiers, secret ARNs, or raw application payloads.

## Controlled alert lifecycle

The deployed immutable application digest used for the test and restored normal
deployment was:

`ghcr.io/khevin2/jenkins-webapp@sha256:048693ed99d7b4ff3e52b207e8daae0d690fdc7b443be520a79758cc806524a4`

| Event | Timestamp | Result |
| --- | --- | --- |
| Controlled traffic started | 14:04:28 | Normal and deliberate fault requests were sent every five seconds. |
| Alert Pending | 14:04:55 | `JenkinsWebappHighErrorRate` entered Pending. |
| Alert Firing | 14:10:48 | The high-error rule fired after the five-minute threshold window. |
| Traffic stopped | 14:11:00 | No further controlled requests were generated. |
| Fault controller disabled | 14:12:14 | The internal controller was disabled; the fault route returned HTTP 404. |
| Alert Resolved | 14:15:52 | Prometheus returned no active `JenkinsWebappHighErrorRate` alerts. |
| Normal container restored | after recovery | `FAULT_INJECTION_ENABLED` absent; health check healthy. |

The test container did not publish port 9465. The normal restored container is
non-root (`10001:10001`), read-only, uses `unless-stopped`, and writes through
the `awslogs` driver. Its health endpoint returned HTTP 200 and its fault route
returned HTTP 404 after restoration.

## Metrics and log correlation

Prometheus reported all expected targets as `up` after restoration:

- application
- application-node
- monitoring-node
- prometheus

A CloudWatch Logs Insights query over 14:00–14:20 found 156 application log
events matching the controlled fault/HTTP 500 filter, from 14:04:28.862 through
14:10:55.089. This brackets the traffic generation and correlates with the
Pending and Firing alert timestamps above.

## Reused security evidence

Phase 11 reuses the existing encrypted CloudTrail proof from
`20260828-phase6-live-verification.txt` and the GuardDuty detector/sample
finding evidence from `20260828-phase7-guardduty-detector.txt` and
`20260828-phase7-sample-finding.txt`. The application image remains correlated
to its Jenkins build digest; the duplicate live Trivy rescan was intentionally
excluded from the lean Phase 11 acceptance scope.
