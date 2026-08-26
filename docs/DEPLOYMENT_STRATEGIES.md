# Deployment strategy comparison

## Current deployment

The Jenkins pipeline validates an unexposed candidate container, removes the
single active container, and starts the new immutable image on port 80. It
attempts to restore the previous digest if the post-cutover health check fails.

This candidate-then-replace workflow is appropriate for the current one-host
scope, but it causes brief downtime and is neither blue-green nor canary.

## Blue-green and canary

| Dimension | Blue-green | Canary |
| --- | --- | --- |
| Release model | Maintain two complete environments; one serves production while the other receives the release. | Run old and new versions together and send a small, increasing traffic percentage to the new version. |
| Traffic control | Switch an ALB listener, target group, proxy route, or DNS record from blue to green. | Use weighted ALB target groups, a service mesh, or a deployment platform with traffic weights. |
| Validation | Exercise the full green environment before the production switch. | Evaluate the new version under real traffic at each percentage step. |
| Rollback | Switch traffic back to the unchanged blue environment. | Set the new-version weight to zero and return all traffic to the stable version. |
| Failure exposure | A bad switch can affect all users immediately, although rollback is fast. | Only the canary percentage is initially exposed, limiting impact. |
| Infrastructure cost | Highest during deployment because two complete environments run concurrently. | Lower when only a small additional capacity slice is required, but both versions still run. |
| Operational complexity | Moderate: duplicate environments, health checks, state compatibility, and one traffic switch. | High: weighted routing, progressive automation, metrics, thresholds, and automatic rollback. |
| Observability requirement | Environment health and post-switch service metrics. | Version-specific errors, latency, saturation, and business metrics at every traffic step. |
| Best fit | Releases needing deterministic cutover and rapid full rollback. | High-traffic services that need gradual risk exposure and reliable automated telemetry. |

## Applying the strategies to this service

A production blue-green design would place blue and green EC2 target groups
behind an Application Load Balancer. Jenkins would deploy the immutable digest
to the inactive target group, verify it, switch the listener, and retain the old
target group for rollback.

A production canary design would keep both revisions registered behind weighted
routing. Jenkins would progress the new revision through explicit percentages,
for example 5%, 25%, 50%, and 100%, only while version-specific health, error
rate, and latency thresholds remain acceptable.

## Decision

The current single-host replacement remains selected because the project
requires one EC2 deployment host and direct SSH deployment. Blue-green would
require at least a second independently deployable environment plus traffic
switching. Canary would additionally require weighted routing and production
telemetry that are outside the current scope.

The pipeline's candidate health check and immutable-digest rollback reduce risk
without claiming the availability properties of either strategy.
