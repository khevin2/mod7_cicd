#!/usr/bin/env bash
# Requires an explicit per-build release authorization in Jenkins.
set -Eeuo pipefail
: "${AWS_REGION:?}" "${AWS_ACCOUNT_ID:?}" "${ECS_CLUSTER:?}" "${ECS_SERVICE:?}" "${ECS_FAMILY:?}" "${TASK_EXECUTION_ROLE_ARN:?}" "${ECS_LOG_GROUP:?}" "${APP_HEALTH_URL:?}"
mkdir -p build-metadata
image=$(<build-metadata/image-digest.txt)
account=$(aws sts get-caller-identity --query Account --output text --region "$AWS_REGION")
[[ "$account" == "$AWS_ACCOUNT_ID" ]] || { echo 'AWS account mismatch' >&2; exit 1; }
python3 scripts/render-ecs-task.py --family "$ECS_FAMILY" --image "$image" --execution-role-arn "$TASK_EXECUTION_ROLE_ARN" --log-group "$ECS_LOG_GROUP" --region "$AWS_REGION" > build-metadata/task-definition.rendered.json
aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" --region "$AWS_REGION" --output json > build-metadata/service-before.json
jq -e '.failures == [] and (.services | length == 1) and .services[0].status == "ACTIVE"' build-metadata/service-before.json >/dev/null
aws ecs register-task-definition --cli-input-json file://build-metadata/task-definition.rendered.json --region "$AWS_REGION" --output json > build-metadata/task-definition.registered.json
revision=$(jq -er '.taskDefinition.taskDefinitionArn' build-metadata/task-definition.registered.json)
jq -e --arg image "$image" '.taskDefinition.containerDefinitions | any(.name == "app" and .image == $image)' build-metadata/task-definition.registered.json >/dev/null
printf '%s\n' "$revision" > build-metadata/task-definition-arn.txt
aws ecs update-service --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" --task-definition "$revision" --region "$AWS_REGION" --output json > build-metadata/service-update.json
# The waiter may succeed after ECS rolls back; verify the requested revision too.
aws ecs wait services-stable --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" --region "$AWS_REGION"
aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" --region "$AWS_REGION" --output json > build-metadata/service-after.json
jq -e --arg revision "$revision" '.failures == [] and (.services | length == 1) and .services[0].status == "ACTIVE" and .services[0].taskDefinition == $revision and .services[0].desiredCount > 0 and .services[0].runningCount == .services[0].desiredCount and ([.services[0].deployments[] | select(.status == "PRIMARY" and .taskDefinition == $revision and .rolloutState == "COMPLETED")] | length == 1)' build-metadata/service-after.json >/dev/null
target_group=$(jq -er '[.services[0].loadBalancers[] | select(.containerName == "app" and .containerPort == 3000) | .targetGroupArn] | if length == 1 then .[0] else error("Expected one app target group") end' build-metadata/service-after.json)
aws ecs list-tasks --cluster "$ECS_CLUSTER" --service-name "$ECS_SERVICE" --desired-status RUNNING --region "$AWS_REGION" --output json > build-metadata/task-arns.json
mapfile -t tasks < <(jq -r '.taskArns[]' build-metadata/task-arns.json)
expected=$(jq -r '.services[0].desiredCount' build-metadata/service-after.json)
[[ ${#tasks[@]} -eq "$expected" && "$expected" -gt 0 ]]
aws ecs describe-tasks --cluster "$ECS_CLUSTER" --tasks "${tasks[@]}" --region "$AWS_REGION" --output json > build-metadata/running-tasks.json
digest=${image##*@}
jq -e --arg revision "$revision" --arg digest "$digest" --argjson count "$expected" '.failures == [] and (.tasks | length == $count) and all(.tasks[]; .taskDefinitionArn == $revision and .lastStatus == "RUNNING" and .healthStatus == "HEALTHY" and any(.containers[]; .name == "app" and .imageDigest == $digest))' build-metadata/running-tasks.json >/dev/null
aws elbv2 describe-target-health --target-group-arn "$target_group" --region "$AWS_REGION" --output json > build-metadata/target-health.json
jq -e --slurpfile taskdata build-metadata/running-tasks.json --argjson count "$expected" '
  . as $health |
  [$taskdata[0].tasks[].attachments[] | select(.type == "ElasticNetworkInterface") | .details[] | select(.name == "privateIPv4Address") | .value] as $ips |
  ($ips | length) == $count and all($ips[]; . as $ip | any($health.TargetHealthDescriptions[]; .Target.Id == $ip and .Target.Port == 3000 and .TargetHealth.State == "healthy"))
' build-metadata/target-health.json >/dev/null
curl --fail --silent --show-error --max-time 10 "$APP_HEALTH_URL" > build-metadata/health-response.json
jq -e '.service == "jenkins-webapp" and .status == "ok"' build-metadata/health-response.json >/dev/null
