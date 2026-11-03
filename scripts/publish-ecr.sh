#!/usr/bin/env bash
# Publish only the local image that was scanned in this build.
set -Eeuo pipefail
: "${AWS_REGION:?}" "${AWS_ACCOUNT_ID:?}" "${ECR_REPOSITORY:?}" "${IMAGE_REF:?}" "${GIT_SHA:?}" "${BUILD_NUMBER:?}"
[[ "$AWS_ACCOUNT_ID" =~ ^[0-9]{12}$ && "$GIT_SHA" =~ ^[0-9a-f]{40}$ && "$BUILD_NUMBER" =~ ^[0-9]+$ ]]
[[ "$ECR_REPOSITORY" =~ ^[a-z0-9]+([._/-][a-z0-9]+)*$ ]]
registry="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
repo="${registry}/${ECR_REPOSITORY}"
tag="${GIT_SHA}-${BUILD_NUMBER}"
mkdir -p build-metadata
expected_id=$(<build-metadata/scanned-image-id.txt)
[[ "$expected_id" == "$(docker image inspect --format '{{.Id}}' "$IMAGE_REF")" ]]
account=$(aws sts get-caller-identity --query Account --output text --region "$AWS_REGION")
[[ "$account" == "$AWS_ACCOUNT_ID" ]] || { echo 'AWS account mismatch' >&2; exit 1; }
export DOCKER_CONFIG
DOCKER_CONFIG=$(mktemp -d)
cleanup() {
  docker image rm "${repo}:${tag}" >/dev/null 2>&1 || true
  rm -rf "$DOCKER_CONFIG"
}
trap cleanup EXIT
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$registry"
docker tag "$IMAGE_REF" "${repo}:${tag}"
docker push "${repo}:${tag}"
digest=$(aws ecr describe-images --repository-name "$ECR_REPOSITORY" --image-ids "imageTag=$tag" --query 'imageDetails[0].imageDigest' --output text --region "$AWS_REGION")
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]
ref="${repo}@${digest}"
docker pull "$ref" >/dev/null
[[ "$expected_id" == "$(docker image inspect --format '{{.Id}}' "$ref")" ]] || { echo 'Pushed image differs from scanned image' >&2; exit 1; }
printf '%s\n' "$ref" > build-metadata/image-digest.txt
printf '%s\n' "${repo}:${tag}" > build-metadata/image-tag.txt
