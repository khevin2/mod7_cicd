# CloudWatch logging operations

Phase 5 creates exactly three tagged, KMS-encrypted log groups, each retained
for 14 days:

| Group | Sources | Streams |
| --- | --- | --- |
| `/jenkins-webapp/lab/application/containers` | Active and candidate application containers | `active`, `candidate` |
| `/jenkins-webapp/lab/monitoring/containers` | Prometheus, Grafana, Node Exporter, Nginx | one stable stream per service |
| `/jenkins-webapp/lab/monitoring/system` | Selected AL2023 rsyslog/journal output | `<instance-id>/messages`, `<instance-id>/secure` |

Terraform pre-creates the groups and grants each host only
`CreateLogStream`, `DescribeLogStreams`, and `PutLogEvents` for its own group.
Both Docker configurations set `awslogs-create-group=false`; a missing group is
a deployment failure, not an implicit unencrypted/default-retention group.

## Pre-apply checks

Run static validation before a provider-backed Terraform plan:

```bash
./scripts/validate-phase5.sh
cd infra/live
terraform init -reconfigure -backend-config=backend.hcl
terraform validate
terraform plan -out=phase5.tfplan
terraform show -no-color phase5.tfplan
```

Apply only the reviewed saved plan. The plan must create (or retain) the three
groups, the CloudWatch Logs KMS key, and the two scoped instance profiles. It
must not replace or delete existing resources without separate approval.

## Post-apply verification

After the monitoring Ansible playbook and one application deployment, use
read-only commands with the approved Region. Redact account, instance, and
public-address details before saving evidence.

The Phase 5 system-log component is independent of certificate and Slack setup:

```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/install_cloudwatch_logging.yml
```

```bash
aws logs describe-log-groups --region eu-north-1 \
  --log-group-name-prefix /jenkins-webapp/lab/ \
  --query 'logGroups[].{name:logGroupName,retention:retentionInDays,kms:kmsKeyId}'

aws logs describe-log-streams --region eu-north-1 \
  --log-group-name /jenkins-webapp/lab/application/containers \
  --order-by LastEventTime --descending
```

The CloudWatch Agent configuration uses UTC explicitly. Compare the newest
event timestamp with `date -u`; record ingestion delay, confirm the expected
stable stream names, and inspect message boundaries from `/var/log/messages`
and `/var/log/secure`. The agent intentionally does not ingest its own log file
because doing so risks a CloudWatch logging feedback loop; its service state is
captured through selected system journal output instead.

## Logs Insights queries

Set the query time range to the controlled test window and select the relevant
group(s).

Application request/error events:

```text
fields @timestamp, @message
| filter @message like /"event":"http_request_(completed|failed)"/
| sort @timestamp desc
| limit 100
```

5xx request counts from structured completion logs:

```text
fields @timestamp, @message
| filter @message like /"event":"http_request_completed"/
| filter @message like /"status_code":5/
| stats count() as requests_5xx by bin(5m)
```

Monitoring host system/service events:

```text
fields @timestamp, @logStream, @message
| filter @message like /amazon-cloudwatch-agent|docker|rsyslog/
| sort @timestamp desc
| limit 100
```

Do not paste raw events into evidence. Verify the sample contains none of the
prohibited data classes: authorization headers, cookies, request bodies, query
strings, tokens, passwords, or secret values.
