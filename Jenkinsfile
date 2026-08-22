pipeline {
  agent any
  tools { nodejs 'NodeJS24' }
  options {
    timestamps()
    timeout(time: 30, unit: 'MINUTES')
    disableConcurrentBuilds()
  }
  parameters {
    string(name: 'DEPLOY_HOST', defaultValue: '', trim: true, description: 'Required EC2 host.')
    string(name: 'DEPLOY_USER', defaultValue: 'ec2-user', trim: true, description: 'SSH user.')
    string(name: 'DEPLOY_PORT', defaultValue: '80', trim: true, description: 'Application host port.')
  }
  environment {
    APP_NAME = 'jenkins-webapp'
    APP_CONTAINER_PORT = '3000'
    REGISTRY_HOST = 'ghcr.io'
    IMAGE_REPOSITORY = 'khevin2/jenkins-webapp'
    TRIVY_IMAGE = 'aquasec/trivy:0.73.0@sha256:7cced7cae583819fc7806d4cbc0dbbc7cad18b99f7d3e235192e6da8c091045c'
    TRIVY_DB_REPOSITORY = 'ghcr.io/aquasecurity/trivy-db:2'
  }
  stages {
    stage('Checkout') {
      steps {
        deleteDir()
        checkout scm
        script {
          env.GIT_SHA = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
          env.GIT_SHORT_SHA = sh(script: 'git rev-parse --short=12 HEAD', returnStdout: true).trim()
          env.SOURCE_URL = sh(script: 'git config --get remote.origin.url || true', returnStdout: true).trim()
          env.IMAGE_REF = "${env.REGISTRY_HOST}/${env.IMAGE_REPOSITORY}:${env.GIT_SHA}"
        }
        sh '''#!/usr/bin/env bash
          set -Eeuo pipefail
          mkdir -p build-metadata
          printf '%s\n' "$GIT_SHA" > build-metadata/git-commit.txt
          printf '%s\n' "$GIT_SHORT_SHA" > build-metadata/git-short-commit.txt
          printf '%s\n' "$IMAGE_REF" > build-metadata/image-reference.txt
          printf '%s\n' "$SOURCE_URL" > build-metadata/source-url.txt
        '''
      }
    }
    stage('Install and Validate') {
      steps {
        sh '''#!/usr/bin/env bash
          set -Eeuo pipefail
          npm ci
          npm run check
        '''
      }
    }
    stage('Test') {
      steps {
        sh '''#!/usr/bin/env bash
          set -Eeuo pipefail
          npm test -- --ci --runInBand
        '''
      }
    }
    stage('Trivy Repository Scan') {
      steps {
        sh '''#!/usr/bin/env bash
          set -Eeuo pipefail
          mkdir -p security-reports
          TRIVY_CACHE_VOLUME="${APP_NAME}-trivy-cache-${BUILD_NUMBER}"
          docker volume create "$TRIVY_CACHE_VOLUME" >/dev/null

          # Archive vulnerability and misconfiguration findings without secret
          # matches, which must never be retained as build artifacts.
          docker run --rm \
            --volume "$WORKSPACE:/workspace:ro" \
            --volume "$WORKSPACE/security-reports:/reports" \
            --volume "$TRIVY_CACHE_VOLUME:/root/.cache/trivy" \
            "$TRIVY_IMAGE" fs \
            --db-repository "$TRIVY_DB_REPOSITORY" \
            --scanners vuln,misconfig \
            --severity UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL \
            --format json \
            --output /reports/trivy-repository.json \
            --skip-dirs /workspace/.git \
            --skip-dirs /workspace/node_modules \
            --skip-files '**/*.tfplan' \
            /workspace

          # Block only fixable HIGH/CRITICAL dependency or configuration issues.
          docker run --rm \
            --volume "$WORKSPACE:/workspace:ro" \
            --volume "$TRIVY_CACHE_VOLUME:/root/.cache/trivy" \
            "$TRIVY_IMAGE" fs \
            --db-repository "$TRIVY_DB_REPOSITORY" \
            --scanners vuln,misconfig \
            --severity HIGH,CRITICAL \
            --ignore-unfixed \
            --exit-code 1 \
            --skip-dirs /workspace/.git \
            --skip-dirs /workspace/node_modules \
            --skip-files '**/*.tfplan' \
            /workspace

          # Keep secret matches inside the ephemeral scanner container so a
          # failed scan cannot publish credential material in Jenkins artifacts.
          docker run --rm \
            --volume "$WORKSPACE:/workspace:ro" \
            --volume "$TRIVY_CACHE_VOLUME:/root/.cache/trivy" \
            "$TRIVY_IMAGE" fs \
            --db-repository "$TRIVY_DB_REPOSITORY" \
            --scanners secret \
            --severity HIGH,CRITICAL \
            --exit-code 1 \
            --format json \
            --output /tmp/trivy-secrets.json \
            --skip-dirs /workspace/.git \
            --skip-dirs /workspace/node_modules \
            --skip-files '**/*.tfplan' \
            /workspace
        '''
      }
    }
    stage('Docker Build') {
      steps {
        sh '''#!/usr/bin/env bash
          set -Eeuo pipefail
          docker build --label "org.opencontainers.image.revision=$GIT_SHA" --label "org.opencontainers.image.source=$SOURCE_URL" --tag "$IMAGE_REF" .
        '''
      }
    }
    stage('Trivy Image Scan') {
      steps {
        sh '''#!/usr/bin/env bash
          set -Eeuo pipefail
          TRIVY_CACHE_VOLUME="${APP_NAME}-trivy-cache-${BUILD_NUMBER}"

          docker run --rm \
            --volume /var/run/docker.sock:/var/run/docker.sock \
            --volume "$WORKSPACE/security-reports:/reports" \
            --volume "$TRIVY_CACHE_VOLUME:/root/.cache/trivy" \
            "$TRIVY_IMAGE" image \
            --db-repository "$TRIVY_DB_REPOSITORY" \
            --scanners vuln \
            --severity UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL \
            --format json \
            --output /reports/trivy-image.json \
            "$IMAGE_REF"

          docker run --rm \
            --volume /var/run/docker.sock:/var/run/docker.sock \
            --volume "$TRIVY_CACHE_VOLUME:/root/.cache/trivy" \
            "$TRIVY_IMAGE" image \
            --db-repository "$TRIVY_DB_REPOSITORY" \
            --scanners vuln \
            --severity HIGH,CRITICAL \
            --ignore-unfixed \
            --exit-code 1 \
            "$IMAGE_REF"

          docker run --rm \
            --volume /var/run/docker.sock:/var/run/docker.sock \
            --volume "$TRIVY_CACHE_VOLUME:/root/.cache/trivy" \
            "$TRIVY_IMAGE" image \
            --db-repository "$TRIVY_DB_REPOSITORY" \
            --scanners secret \
            --severity HIGH,CRITICAL \
            --exit-code 1 \
            --format json \
            --output /tmp/trivy-image-secrets.json \
            "$IMAGE_REF"
        '''
      }
    }
    stage('Push Image') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'registry_creds', usernameVariable: 'REGISTRY_USERNAME', passwordVariable: 'REGISTRY_TOKEN')]) {
          sh '''#!/usr/bin/env bash
            set -Eeuo pipefail
            trap 'docker logout "$REGISTRY_HOST" >/dev/null 2>&1 || true' EXIT
            printf '%s' "$REGISTRY_TOKEN" | docker login "$REGISTRY_HOST" --username "$REGISTRY_USERNAME" --password-stdin
            docker push "$IMAGE_REF"
            IMAGE_DIGEST="$(docker image inspect --format='{{index .RepoDigests 0}}' "$IMAGE_REF")"
            [[ "$IMAGE_DIGEST" == "${REGISTRY_HOST}/${IMAGE_REPOSITORY}@sha256:"* ]]
            printf '%s\n' "$IMAGE_DIGEST" > build-metadata/image-digest.txt
          '''
        }
      }
    }
    stage('Deploy') {
      steps {
        script { if (!params.DEPLOY_HOST?.trim()) { error('DEPLOY_HOST is required before deployment.') } }
        withCredentials([usernamePassword(credentialsId: 'registry_creds', usernameVariable: 'REGISTRY_USERNAME', passwordVariable: 'REGISTRY_TOKEN')]) {
          sshagent(credentials: ['ec2_ssh']) {
            sh '''#!/usr/bin/env bash
              set -Eeuo pipefail
              DEPLOY_IMAGE_REF="$(< build-metadata/image-digest.txt)"
              remote_command=$(printf 'REGISTRY_HOST=%q DEPLOY_IMAGE_REF=%q APP_NAME=%q DEPLOY_PORT=%q APP_CONTAINER_PORT=%q bash -c %q' "$REGISTRY_HOST" "$DEPLOY_IMAGE_REF" "$APP_NAME" "$DEPLOY_PORT" "$APP_CONTAINER_PORT" 'IFS= read -r REGISTRY_USERNAME; IFS= read -r REGISTRY_TOKEN; export REGISTRY_USERNAME REGISTRY_TOKEN; exec bash -s')
              {
                printf '%s\n%s\n' "$REGISTRY_USERNAME" "$REGISTRY_TOKEN"
                cat <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
candidate="${APP_NAME}-candidate"
previous=''
rollback=false
cleanup() { docker rm -f "$candidate" >/dev/null 2>&1 || true; docker logout "$REGISTRY_HOST" >/dev/null 2>&1 || true; unset REGISTRY_TOKEN; }
recover() {
  status="$1"
  if [[ "$rollback" == true && -n "$previous" ]]; then
    echo "Deployment failed; rolling back to ${previous}."
    docker rm -f "$APP_NAME" >/dev/null 2>&1 || true
    docker run -d --name "$APP_NAME" --restart unless-stopped -p "${DEPLOY_PORT}:${APP_CONTAINER_PORT}" "$previous" >/dev/null
  elif [[ "$rollback" == true ]]; then docker rm -f "$APP_NAME" >/dev/null 2>&1 || true; fi
  cleanup
  exit "$status"
}
trap 'status=$?; if (( status != 0 )); then recover "$status"; else cleanup; fi' EXIT
printf '%s' "$REGISTRY_TOKEN" | docker login "$REGISTRY_HOST" --username "$REGISTRY_USERNAME" --password-stdin
docker pull "$DEPLOY_IMAGE_REF"
docker rm -f "$candidate" >/dev/null 2>&1 || true
docker run -d --rm --name "$candidate" "$DEPLOY_IMAGE_REF" >/dev/null
for attempt in {1..12}; do
  [[ "$(docker inspect --format='{{.State.Health.Status}}' "$candidate")" == healthy ]] && break
  sleep 5
done
[[ "$(docker inspect --format='{{.State.Health.Status}}' "$candidate")" == healthy ]]
docker rm -f "$candidate" >/dev/null
if docker container inspect "$APP_NAME" >/dev/null 2>&1; then previous="$(docker inspect --format='{{.Config.Image}}' "$APP_NAME")"; echo "Rollback command: docker run -d --name ${APP_NAME} --restart unless-stopped -p ${DEPLOY_PORT}:${APP_CONTAINER_PORT} ${previous}"; fi
rollback=true
docker rm -f "$APP_NAME" >/dev/null 2>&1 || true
docker run -d --name "$APP_NAME" --restart unless-stopped -p "${DEPLOY_PORT}:${APP_CONTAINER_PORT}" "$DEPLOY_IMAGE_REF" >/dev/null
for attempt in {1..12}; do
  if curl --fail --silent --show-error --max-time 3 "http://127.0.0.1:${DEPLOY_PORT}/health" >/dev/null; then rollback=false; exit 0; fi
  sleep 5
done
exit 1
REMOTE
              } | ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$HOME/.ssh/known_hosts" "${DEPLOY_USER}@${DEPLOY_HOST}" "$remote_command"
            '''
          }
        }
      }
    }
    stage('Runtime Cleanup') {
      steps {
        script { if (!params.DEPLOY_HOST?.trim()) { error('DEPLOY_HOST is required before runtime cleanup.') } }
        sshagent(credentials: ['ec2_ssh']) {
          sh '''#!/usr/bin/env bash
            set -Eeuo pipefail
            remote_command=$(printf 'REGISTRY_HOST=%q APP_NAME=%q DEPLOY_PORT=%q bash -s' "$REGISTRY_HOST" "$APP_NAME" "$DEPLOY_PORT")
            ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$HOME/.ssh/known_hosts" "${DEPLOY_USER}@${DEPLOY_HOST}" "$remote_command" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
candidate="${APP_NAME}-candidate"

# The approved host-retention policy is intentionally narrow: remove only the
# deployment candidate and dangling layers. Immutable, tagged images are left
# in place so the active image and its previous known-good rollback image stay
# available. Do not replace this with a broad image/container prune.
docker rm -f "$candidate" >/dev/null 2>&1 || true
docker image prune --force
docker logout "$REGISTRY_HOST" >/dev/null 2>&1 || true

running_count="$(docker ps --filter "name=^/${APP_NAME}$" --filter 'status=running' --format '{{.ID}}' | wc -l | tr -d '[:space:]')"
[[ "$running_count" == '1' ]]
[[ "$(docker inspect --format='{{.State.Health.Status}}' "$APP_NAME")" == 'healthy' ]]
curl --fail --silent --show-error --max-time 10 "http://127.0.0.1:${DEPLOY_PORT}/health"
df -h /
REMOTE
          '''
        }
      }
    }
  }
  post {
    always {
      junit allowEmptyResults: true, testResults: 'test-results/*.xml'
      archiveArtifacts allowEmptyArchive: true, artifacts: 'build-metadata/*,security-reports/*.json'
      sh '''#!/usr/bin/env bash
        set -Eeuo pipefail
        [[ -z "${IMAGE_REF:-}" ]] || docker image rm -f "$IMAGE_REF" >/dev/null 2>&1 || true
        docker volume rm -f "${APP_NAME}-trivy-cache-${BUILD_NUMBER}" >/dev/null 2>&1 || true
        docker image rm -f "$TRIVY_IMAGE" >/dev/null 2>&1 || true
      '''
      deleteDir()
    }
  }
}
