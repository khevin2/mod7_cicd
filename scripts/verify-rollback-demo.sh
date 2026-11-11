#!/usr/bin/env bash
# Read-only recovery observer. Always fails the attempted Jenkins release,
# including when automatic rollback is verified. Never performs manual rollback.
set -Eeuo pipefail
: "${AWS_REGION:?}" "${ECS_CLUSTER:?}" "${ECS_SERVICE:?}" "${APP_HEALTH_URL:?}"
revision=${1:?Expected attempted task revision}
baseline=$(jq -er '.revision' build-metadata/rollback-baseline.json)
deployment=$(jq -er --arg revision "$revision" '[.service.deployments[] | select(.taskDefinition == $revision)] | if length == 1 then .[0].id else error("Expected one attempted deployment") end' build-metadata/service-update.json)
checks=${ECS_DEMO_MAX_CHECKS:-120}
[[ "$checks" =~ ^[0-9]+$ ]] && ((checks >= 1 && checks <= 120))
failure_seen=false
restored=false
: > build-metadata/rollback-observations.jsonl
for ((attempt=0; attempt<checks; attempt++)); do
  aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" --region "$AWS_REGION" --output json > build-metadata/service-after.json
  jq -e '.failures == [] and (.services | length == 1) and .services[0].status == "ACTIVE"' build-metadata/service-after.json >/dev/null
  jq -c '{service:(.services[0] | {taskDefinition,desiredCount,runningCount,deployments,events})}' build-metadata/service-after.json >> build-metadata/rollback-observations.jsonl
  if jq -e --arg revision "$revision" --arg deployment "$deployment" 'any(.services[0].deployments[]; .taskDefinition == $revision and .rolloutState == "FAILED") or any(.services[0].events[]?; (.message | contains($deployment)) and (.message | test("failed|circuit.breaker|rolling.back";"i")))' build-metadata/service-after.json >/dev/null; then
    failure_seen=true
    cp build-metadata/service-after.json build-metadata/rollback-failure-observed.json
  fi
  if [[ "$failure_seen" == true ]] && jq -e --arg baseline "$baseline" '.services[0] | .taskDefinition == $baseline and .desiredCount > 0 and .runningCount == .desiredCount and any(.deployments[]; .status == "PRIMARY" and .taskDefinition == $baseline and .rolloutState == "COMPLETED")' build-metadata/service-after.json >/dev/null; then
    restored=true
    break
  fi
  sleep 5
done
if [[ "$restored" != true ]]; then
  echo 'Automatic rollback was not fully verified within the observation window. Inspect the archived service snapshots.' >&2
  exit 1
fi
aws ecs list-tasks --cluster "$ECS_CLUSTER" --service-name "$ECS_SERVICE" --desired-status RUNNING --region "$AWS_REGION" --output json > build-metadata/task-arns.json
mapfile -t tasks < <(jq -r '.taskArns[]' build-metadata/task-arns.json)
[[ ${#tasks[@]} -gt 0 ]]
aws ecs describe-tasks --cluster "$ECS_CLUSTER" --tasks "${tasks[@]}" --region "$AWS_REGION" --output json > build-metadata/running-tasks.json
jq -e --arg baseline "$baseline" --slurpfile before build-metadata/rollback-baseline.json --slurpfile service build-metadata/service-after.json '.failures == [] and (.tasks | length) == $service[0].services[0].desiredCount and all(.tasks[]; .taskDefinitionArn == $baseline and .lastStatus == "RUNNING" and .healthStatus == "HEALTHY") and ([.tasks[].containers[] | select(.name == "app") | .imageDigest] | unique) == $before[0].imageDigests' build-metadata/running-tasks.json >/dev/null
group=$(jq -er '[.services[0].loadBalancers[] | select(.containerName == "app" and .containerPort == 3000)] | if length == 1 then .[0].targetGroupArn else error("Expected one app target group") end' build-metadata/service-after.json)
aws elbv2 describe-target-health --target-group-arn "$group" --region "$AWS_REGION" --output json > build-metadata/target-health.json
jq -e --slurpfile tasks build-metadata/running-tasks.json '
  . as $health |
  [$tasks[0].tasks[].attachments[] | select(.type == "ElasticNetworkInterface") | .details[] | select(.name == "privateIPv4Address") | .value] as $ips |
  ($ips | length) == ($tasks[0].tasks | length) and all($ips[]; . as $ip | any($health.TargetHealthDescriptions[]; .Target.Id == $ip and .Target.Port == 3000 and .TargetHealth.State == "healthy"))
' build-metadata/target-health.json >/dev/null
curl --fail --silent --show-error --max-time 10 "$APP_HEALTH_URL" > build-metadata/health-response.json
jq -e '.service == "jenkins-webapp" and .status == "ok"' build-metadata/health-response.json >/dev/null
jq -n --arg attempted "$revision" --slurpfile before build-metadata/rollback-baseline.json '{expectedJenkinsResult:"FAILURE",automaticRollbackVerified:true,imageIdentityVerified:true,targetHealthVerified:true,applicationHealthVerified:true,failedRevision:$attempted,restoredRevision:$before[0].revision,restoredImageDigests:$before[0].imageDigests}' > build-metadata/rollback-demo-result.json
echo 'Expected rollback demonstration: failed revision rejected; baseline revision, image and health automatically restored. Jenkins must report FAILURE.' >&2
exit 1
