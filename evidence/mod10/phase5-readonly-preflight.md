# Module 10 Phase 5 Read-Only Preflight

Generated: 2026-09-03T10:31:41Z

## Safety statement

This report was generated only with AWS `get-caller-identity`, `describe-*`,
and CloudWatch `get-metric-statistics` APIs, plus optional HTTP GET health
probes. No cloud resource, deployed runtime, Terraform state, Secrets Manager
value, CloudWatch log event, Jenkins job, container, or Grafana configuration
was changed. Account IDs, ARNs, resource IDs, IP addresses, CIDRs, endpoint
URLs, credentials, and tokens are intentionally omitted.

## Identity and scope

- Region: `eu-north-1`
- Caller credential: reachable; principal type: IAM user
- Resource selector: Project=`jenkins-webapp`, Environment=`lab`

## AWS topology summary

- Tagged VPCs discovered: 2
- Instances: `[{"role":"jenkins-controller-runner","instances":1,"states":[{"state":"running","count":1}],"instance_types":[{"type":"t3.micro","count":1}],"public_addresses_present":true},{"role":"monitoring","instances":1,"states":[{"state":"running","count":1}],"instance_types":[{"type":"t3.small","count":1}],"public_addresses_present":true},{"role":"unclassified","instances":1,"states":[{"state":"running","count":1}],"instance_types":[{"type":"t3.micro","count":1}],"public_addresses_present":true}]`
- VPC peering states: `[{"state":"active","count":1}]`
- Routes that reference a VPC peering connection: 2
- Security-group TCP 4318 summary: `[{"role":"unclassified","ingress_4318":0,"ingress_4318_public":0,"ingress_4318_private_or_sg":0,"egress_4318":0},{"role":"unclassified","ingress_4318":0,"ingress_4318_public":0,"ingress_4318_private_or_sg":0,"egress_4318":0},{"role":"unclassified","ingress_4318":0,"ingress_4318_public":0,"ingress_4318_private_or_sg":0,"egress_4318":0}]`

Interpretation: any non-zero `ingress_4318_public` is unexpected and blocks
rollout. A zero ingress count confirms TCP 4318 is not yet present; a non-zero
private-or-security-group count requires user review against the approved
application-to-monitoring path. Resource identifiers are intentionally not
recorded here.

## Logging and monitoring headroom

- Matching CloudWatch log-group metadata: `[{"retention_days":14,"stored_bytes":13550720},{"retention_days":14,"stored_bytes":12844278},{"retention_days":14,"stored_bytes":4639526}]`
- Monitoring-host CPU (previous hour): `{
  "status": "available",
  "samples": 12,
  "minimum_percent": 2.65,
  "maximum_percent": 2.82,
  "average_percent": 2.7
}`
- Monitoring-host memory/disk: not available from native EC2 metrics; obtain
  through an existing read-only host telemetry view or an already-approved,
  read-only host session. Do not use SSM Run Command.

## Optional HTTP GET probes

- Grafana health: not configured
- Prometheus readiness: not configured
- Application health: not configured

`not configured` means no endpoint was supplied to this script; it is not a
health result. Endpoint values are intentionally omitted from the report.

## Exact user-controlled rollout mutation set

1. Review a Terraform plan that is limited to private TCP 4318 egress from the
   application security boundary and private TCP 4318 ingress on the monitoring
   security boundary, with no public source or public listener.
2. Deploy the reviewed monitoring Compose/Ansible configuration to introduce
   Jaeger, bind its OTLP receiver only to the approved monitoring private
   address, and keep its UI loopback-only.
3. Supply the approved non-secret private OTLP endpoint to the deployment
   workflow and deploy the application image.

The user owns every rollout, rollback, Terraform plan/apply, Ansible action,
container lifecycle action, and Jenkins build. Stop and investigate before
rollout if a tagged resource is missing, a peering is not active, an unexpected
public TCP 4318 rule exists, or unrelated resource drift appears.
