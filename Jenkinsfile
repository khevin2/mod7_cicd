pipeline {
  agent any
  tools { nodejs 'NodeJS24' }
  options {
    timestamps()
    skipDefaultCheckout()
    buildDiscarder(logRotator(numToKeepStr: '10', artifactNumToKeepStr: '5'))
    timeout(time: 60, unit: 'MINUTES')
    disableConcurrentBuilds()
  }
  triggers { githubPush() }
  parameters {
    booleanParam(name: 'RELEASE_APPROVED', defaultValue: false,
      description: 'For a manually started build only: explicitly authorize this build to publish to ECR and update the ECS service.')
  }
  environment {
    AWS_REGION = 'eu-north-1'
  }
  stages {
    stage('Checkout') {
      steps {
        deleteDir()
        script {
          def source = checkout scm
          env.CHECKED_OUT_BRANCH = env.BRANCH_NAME ?: source.GIT_BRANCH ?: ''
          env.GIT_SHA = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
          env.IMAGE_REF = "mod9-jenkins-webapp:${env.GIT_SHA}-${env.BUILD_NUMBER}"
          if (!(env.CHECKED_OUT_BRANCH in ['feature/secure-ecs-ec2', 'origin/feature/secure-ecs-ec2'])) {
            error("Configure this job to check out feature/secure-ecs-ec2; got ${env.CHECKED_OUT_BRANCH}")
          }
          if (params.RELEASE_APPROVED && currentBuild.getBuildCauses('hudson.model.Cause$UserIdCause').isEmpty()) {
            error('Release authorization is accepted only for a manually started build.')
          }
        }
        sh '''#!/usr/bin/env bash
          set -Eeuo pipefail
          mkdir -p build-metadata security-reports
          printf '%s\n' "$GIT_SHA" > build-metadata/git-commit.txt
          printf '%s\n' "$BUILD_NUMBER" > build-metadata/jenkins-build.txt
          printf '%s\n' "$IMAGE_REF" > build-metadata/local-image-tag.txt
          : "${EXPECTED_SNYK_VERSION:?Set the approved Snyk CLI version in Jenkins}"
          : "${EXPECTED_SONAR_SCANNER_VERSION:?Set the approved SonarScanner CLI version in Jenkins}"
          for tool in gitleaks trivy syft snyk sonar-scanner aws; do
            command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
            version=$("$tool" --version 2>&1)
            printf '%s: %s\n' "$tool" "$version" >> build-metadata/tool-versions.txt
            case "$tool" in
              gitleaks) expected='8.28.0' ;;
              trivy) expected='0.73.0' ;;
              syft) expected='1.38.0' ;;
              snyk) expected="$EXPECTED_SNYK_VERSION" ;;
              sonar-scanner) expected="$EXPECTED_SONAR_SCANNER_VERSION" ;;
              *) continue ;;
            esac
            [[ "$expected" =~ ^[0-9]+([.][0-9]+)+$ ]] || { echo "Invalid version pin for $tool" >&2; exit 1; }
            expected_pattern=${expected//./[.]}
            [[ "$version" =~ (^|[^0-9.])${expected_pattern}([^0-9.]|$) ]] || { echo "Unexpected version for $tool" >&2; exit 1; }
          done
        '''
      }
    }
    stage('Secret scan') {
      steps { sh 'scripts/security-scan.sh secrets' }
    }
    stage('Install and test') {
      steps {
        sh '''#!/usr/bin/env bash
          set -Eeuo pipefail
          npm ci --no-audit --no-fund
          npm run check
          npm test -- --ci --runInBand
        '''
      }
    }
    stage('SAST') {
      steps {
        withCredentials([string(credentialsId: 'sonarqube-token', variable: 'SONAR_TOKEN')]) {
          sh 'scripts/security-scan.sh sast'
        }
      }
    }
    stage('Dependency scan') {
      steps {
        withCredentials([string(credentialsId: 'snyk-token', variable: 'SNYK_TOKEN')]) {
          sh 'scripts/security-scan.sh sca'
        }
        sh 'scripts/security-scan.sh repository'
        sh 'scripts/security-scan.sh misconfig'
      }
    }
    stage('Build image') {
      steps {
        sh '''#!/usr/bin/env bash
          set -Eeuo pipefail
          docker build --label "org.opencontainers.image.revision=$GIT_SHA" --tag "$IMAGE_REF" .
          docker image inspect --format '{{.Id}}' "$IMAGE_REF" > build-metadata/scanned-image-id.txt
        '''
      }
    }
    stage('Image scan and SBOM') {
      steps {
        sh '''#!/usr/bin/env bash
          set -Eeuo pipefail
          scripts/security-scan.sh image
          scripts/security-scan.sh image-secrets
          scripts/security-scan.sh sbom
          [[ "$(docker image inspect --format '{{.Id}}' "$IMAGE_REF")" == "$(<build-metadata/scanned-image-id.txt)" ]]
        '''
      }
    }
    stage('Publish approved image to ECR') {
      when { expression { params.RELEASE_APPROVED } }
      steps { sh 'scripts/publish-ecr.sh' }
    }
    stage('Deploy approved revision to ECS') {
      when { expression { params.RELEASE_APPROVED } }
      steps { sh 'scripts/deploy-ecs.sh' }
    }
  }
  post {
    always {
      script {
        try {
          junit allowEmptyResults: true, testResults: 'test-results/*.xml'
        } finally {
          try {
            // Reports can reveal findings and repository details. Restrict artifact access.
            archiveArtifacts allowEmptyArchive: true, artifacts: 'build-metadata/*,security-reports/*.json'
          } finally {
            def cleanupStatus = sh(script: 'if [ -f scripts/cleanup-build-image.sh ]; then scripts/cleanup-build-image.sh; fi', returnStatus: true)
            if (cleanupStatus != 0) {
              echo 'Could not remove the build-specific local image tag; inspect the agent.'
            }
          }
        }
      }
    }
    success {
      script {
        if (!params.RELEASE_APPROVED) {
          echo 'Validation completed; no release was authorized for this build.'
        }
      }
    }
  }
}
