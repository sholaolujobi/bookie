// Declarative CI/CD pipeline for bookie.
//
// Runs on the Jenkins EC2 instance directly (agent any), using tools
// installed by terraform/templates/jenkins-user-data.sh.tpl: docker,
// aws-cli v2, terraform, jq, trivy, hadolint, gitleaks. Node.js/npm are
// intentionally NOT installed on the host - all npm steps run inside a
// throwaway `node:20-alpine` container so the Jenkins host stays small.
//
// AWS auth is entirely via the EC2 instance's IAM role (see
// terraform/iam.tf, aws_iam_role.jenkins) - no static AWS credentials are
// ever configured here. GitHub auth for the private repo checkout uses a
// Jenkins credential (id "github-bookie-credentials", configured in the
// Jenkins UI, never inlined here).
//
// All `sh` steps use single-quoted Groovy strings (no ${VAR} Groovy
// interpolation) and let bash expand $VAR/${VAR} from its own process
// environment instead. Every variable here - whether declared directly in
// the environment{} block or set dynamically via env.X = ... in a script{}
// block - is exported as a real shell env var either way, so this is both
// simpler and more reliable than Groovy string interpolation, which does
// NOT reliably resolve bare references to env.X-assigned variables inside
// the CPS sandbox (confirmed the hard way: `groovy.lang.MissingPropertyException:
// No such property: IMAGE_TAG` on a stage that referenced ${IMAGE_TAG}
// directly, despite IMAGE_TAG being set via env.IMAGE_TAG = ... earlier in
// the same run).

pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timestamps()
        ansiColor('xterm')
        timeout(time: 45, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    environment {
        AWS_REGION        = 'us-east-1'
        PROJECT_NAME      = 'bookie'
        ENVIRONMENT       = 'dev'
        ECS_CLUSTER       = "${PROJECT_NAME}-${ENVIRONMENT}-cluster"
        FRONTEND_SERVICE  = "${PROJECT_NAME}-${ENVIRONMENT}-frontend"
        BACKEND_SERVICE   = "${PROJECT_NAME}-${ENVIRONMENT}-backend"
        FRONTEND_ECR_REPO = "${PROJECT_NAME}-${ENVIRONMENT}-frontend"
        BACKEND_ECR_REPO  = "${PROJECT_NAME}-${ENVIRONMENT}-backend"
        NPM_DOCKER_IMAGE  = 'node:20-alpine'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(script: 'git rev-parse --short=8 HEAD', returnStdout: true).trim()
                    env.IMAGE_TAG = "${env.GIT_COMMIT_SHORT}-${env.BUILD_NUMBER}"
                    env.ACCOUNT_ID = sh(script: 'aws sts get-caller-identity --query Account --output text', returnStdout: true).trim()
                    env.ECR_REGISTRY = "${env.ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
                    env.ALB_DNS_NAME = sh(
                        script: 'aws elbv2 describe-load-balancers --region "$AWS_REGION" --names "${PROJECT_NAME}-${ENVIRONMENT}-alb" --query "LoadBalancers[0].DNSName" --output text',
                        returnStdout: true
                    ).trim()
                    echo "Building ${env.IMAGE_TAG} for account ${env.ACCOUNT_ID}, ALB ${env.ALB_DNS_NAME}"
                }
            }
        }

        stage('Install Dependencies') {
            parallel {
                stage('Frontend deps') {
                    steps {
                        sh '''
                          docker run --rm --user "$(id -u):$(id -g)" \\
                            -e npm_config_cache=/tmp/.npm-cache -v /tmp:/tmp \\
                            -v "$WORKSPACE/frontend:/app" -w /app "$NPM_DOCKER_IMAGE" \\
                            npm ci
                        '''
                    }
                }
                stage('Backend deps') {
                    steps {
                        sh '''
                          docker run --rm --user "$(id -u):$(id -g)" \\
                            -e npm_config_cache=/tmp/.npm-cache -v /tmp:/tmp \\
                            -v "$WORKSPACE/backend:/app" -w /app "$NPM_DOCKER_IMAGE" \\
                            npm ci
                        '''
                    }
                }
            }
        }

        stage('Test') {
            parallel {
                stage('Frontend tests') {
                    steps {
                        sh '''
                          docker run --rm --user "$(id -u):$(id -g)" \\
                            -e CI=true -e npm_config_cache=/tmp/.npm-cache -v /tmp:/tmp \\
                            -v "$WORKSPACE/frontend:/app" -w /app "$NPM_DOCKER_IMAGE" \\
                            npm test
                        '''
                    }
                }
                stage('Backend tests') {
                    steps {
                        sh '''
                          docker run --rm --user "$(id -u):$(id -g)" \\
                            -e npm_config_cache=/tmp/.npm-cache -v /tmp:/tmp \\
                            -v "$WORKSPACE/backend:/app" -w /app "$NPM_DOCKER_IMAGE" \\
                            npm test
                        '''
                    }
                }
            }
        }

        stage('Frontend Production Build') {
            steps {
                sh '''
                  docker run --rm --user "$(id -u):$(id -g)" \\
                    -e npm_config_cache=/tmp/.npm-cache -v /tmp:/tmp \\
                    -v "$WORKSPACE/frontend:/app" -w /app "$NPM_DOCKER_IMAGE" \\
                    npm run build
                '''
            }
        }

        stage('Terraform fmt/validate') {
            steps {
                dir('terraform') {
                    sh '''
                      terraform fmt -check -recursive
                      terraform init -backend=false -input=false
                      terraform validate
                    '''
                }
            }
        }

        stage('Dockerfile Lint') {
            steps {
                sh '''
                  hadolint frontend/Dockerfile
                  hadolint backend/Dockerfile
                '''
            }
        }

        stage('Secret Scan') {
            steps {
                sh 'gitleaks detect --source . --no-git -v --redact'
            }
        }

        stage('Dependency Vulnerability Scan') {
            parallel {
                stage('Frontend audit') {
                    steps {
                        // CRA's own dev-only build tooling carries known,
                        // documented moderate findings (see docs/SECURITY.md);
                        // gate on critical only so those don't block builds.
                        sh '''
                          docker run --rm --user "$(id -u):$(id -g)" \\
                            -e npm_config_cache=/tmp/.npm-cache -v /tmp:/tmp \\
                            -v "$WORKSPACE/frontend:/app" -w /app "$NPM_DOCKER_IMAGE" \\
                            npm audit --audit-level=critical
                        '''
                    }
                }
                stage('Backend audit') {
                    steps {
                        sh '''
                          docker run --rm --user "$(id -u):$(id -g)" \\
                            -e npm_config_cache=/tmp/.npm-cache -v /tmp:/tmp \\
                            -v "$WORKSPACE/backend:/app" -w /app "$NPM_DOCKER_IMAGE" \\
                            npm audit --omit=dev --audit-level=critical
                        '''
                    }
                }
            }
        }

        stage('Build Docker Images') {
            steps {
                sh '''
                  docker build -t "${FRONTEND_ECR_REPO}:${IMAGE_TAG}" ./frontend
                  docker build -t "${BACKEND_ECR_REPO}:${IMAGE_TAG}" ./backend
                '''
            }
        }

        stage('Trivy Image Scan') {
            steps {
                sh '''
                  trivy image --severity HIGH,CRITICAL --exit-code 1 --ignore-unfixed "${FRONTEND_ECR_REPO}:${IMAGE_TAG}"
                  trivy image --severity HIGH,CRITICAL --exit-code 1 --ignore-unfixed "${BACKEND_ECR_REPO}:${IMAGE_TAG}"
                '''
            }
        }

        stage('ECR Auth & Push') {
            steps {
                sh '''
                  aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"

                  docker tag "${FRONTEND_ECR_REPO}:${IMAGE_TAG}" "${ECR_REGISTRY}/${FRONTEND_ECR_REPO}:${IMAGE_TAG}"
                  docker tag "${BACKEND_ECR_REPO}:${IMAGE_TAG}" "${ECR_REGISTRY}/${BACKEND_ECR_REPO}:${IMAGE_TAG}"

                  docker push "${ECR_REGISTRY}/${FRONTEND_ECR_REPO}:${IMAGE_TAG}"
                  docker push "${ECR_REGISTRY}/${BACKEND_ECR_REPO}:${IMAGE_TAG}"

                  docker logout "$ECR_REGISTRY"
                '''
            }
        }

        stage('Record Current Task Definitions') {
            steps {
                script {
                    env.PREV_FRONTEND_TASKDEF = sh(
                        script: 'aws ecs describe-services --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --services "$FRONTEND_SERVICE" --query "services[0].taskDefinition" --output text',
                        returnStdout: true
                    ).trim()
                    env.PREV_BACKEND_TASKDEF = sh(
                        script: 'aws ecs describe-services --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --services "$BACKEND_SERVICE" --query "services[0].taskDefinition" --output text',
                        returnStdout: true
                    ).trim()
                    echo "Rollback targets recorded: frontend=${env.PREV_FRONTEND_TASKDEF} backend=${env.PREV_BACKEND_TASKDEF}"
                }
            }
        }

        stage('Register Task Definitions') {
            steps {
                sh '''
                  set -eu
                  aws ecs describe-task-definition --region "$AWS_REGION" \\
                    --task-definition "${PROJECT_NAME}-${ENVIRONMENT}-frontend" \\
                    --query 'taskDefinition' > frontend-taskdef.json
                  jq --arg IMAGE "${ECR_REGISTRY}/${FRONTEND_ECR_REPO}:${IMAGE_TAG}" \\
                    '.containerDefinitions[0].image = $IMAGE |
                     del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
                         .compatibilities, .registeredAt, .registeredBy)' \\
                    frontend-taskdef.json > frontend-taskdef.new.json
                  aws ecs register-task-definition --region "$AWS_REGION" \\
                    --cli-input-json file://frontend-taskdef.new.json \\
                    --query 'taskDefinition.taskDefinitionArn' --output text > frontend-new-arn.txt
                '''
                sh '''
                  set -eu
                  aws ecs describe-task-definition --region "$AWS_REGION" \\
                    --task-definition "${PROJECT_NAME}-${ENVIRONMENT}-backend" \\
                    --query 'taskDefinition' > backend-taskdef.json
                  jq --arg IMAGE "${ECR_REGISTRY}/${BACKEND_ECR_REPO}:${IMAGE_TAG}" \\
                    '.containerDefinitions[0].image = $IMAGE |
                     del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
                         .compatibilities, .registeredAt, .registeredBy)' \\
                    backend-taskdef.json > backend-taskdef.new.json
                  aws ecs register-task-definition --region "$AWS_REGION" \\
                    --cli-input-json file://backend-taskdef.new.json \\
                    --query 'taskDefinition.taskDefinitionArn' --output text > backend-new-arn.txt
                '''
                script {
                    env.NEW_FRONTEND_TASKDEF = sh(script: 'cat frontend-new-arn.txt', returnStdout: true).trim()
                    env.NEW_BACKEND_TASKDEF = sh(script: 'cat backend-new-arn.txt', returnStdout: true).trim()
                }
            }
        }

        stage('Update ECS Services') {
            steps {
                sh '''
                  aws ecs update-service --region "$AWS_REGION" --cluster "$ECS_CLUSTER" \\
                    --service "$FRONTEND_SERVICE" --task-definition "$NEW_FRONTEND_TASKDEF" >/dev/null
                  aws ecs update-service --region "$AWS_REGION" --cluster "$ECS_CLUSTER" \\
                    --service "$BACKEND_SERVICE" --task-definition "$NEW_BACKEND_TASKDEF" >/dev/null
                '''
            }
        }

        stage('Wait For Stability') {
            steps {
                sh '''
                  aws ecs wait services-stable --region "$AWS_REGION" --cluster "$ECS_CLUSTER" \\
                    --services "$FRONTEND_SERVICE" "$BACKEND_SERVICE"
                '''
            }
        }

        stage('Smoke Test') {
            steps {
                sh '''
                  set -eu
                  echo "Smoke testing backend..."
                  status_body=$(curl -sf "http://${ALB_DNS_NAME}/api/status")
                  echo "$status_body"
                  echo "$status_body" | grep -q '"status":"SUCCESS"'
                  echo "$status_body" | grep -qE '"guid":"[0-9a-f-]{36}"'

                  echo "Smoke testing frontend..."
                  curl -sf -o /dev/null -w '%{http_code}' "http://${ALB_DNS_NAME}/" | grep -q '^200$'
                '''
            }
        }

        stage('Cleanup') {
            steps {
                sh '''
                  docker rmi "${FRONTEND_ECR_REPO}:${IMAGE_TAG}" "${ECR_REGISTRY}/${FRONTEND_ECR_REPO}:${IMAGE_TAG}" || true
                  docker rmi "${BACKEND_ECR_REPO}:${IMAGE_TAG}" "${ECR_REGISTRY}/${BACKEND_ECR_REPO}:${IMAGE_TAG}" || true
                  docker image prune -f || true
                  rm -f frontend-taskdef*.json backend-taskdef*.json frontend-new-arn.txt backend-new-arn.txt
                '''
            }
        }
    }

    post {
        failure {
            script {
                if (env.PREV_FRONTEND_TASKDEF?.trim() && env.PREV_BACKEND_TASKDEF?.trim()) {
                    echo "Deployment failed - rolling back to previous task definitions."
                    sh '''
                      aws ecs update-service --region "$AWS_REGION" --cluster "$ECS_CLUSTER" \\
                        --service "$FRONTEND_SERVICE" --task-definition "$PREV_FRONTEND_TASKDEF" >/dev/null
                      aws ecs update-service --region "$AWS_REGION" --cluster "$ECS_CLUSTER" \\
                        --service "$BACKEND_SERVICE" --task-definition "$PREV_BACKEND_TASKDEF" >/dev/null
                      aws ecs wait services-stable --region "$AWS_REGION" --cluster "$ECS_CLUSTER" \\
                        --services "$FRONTEND_SERVICE" "$BACKEND_SERVICE"
                    '''
                    echo "Rollback complete. Services restored to their previous stable task definitions."
                } else {
                    echo "No previous task definition was recorded (failure occurred before that stage) - nothing to roll back."
                }
            }
        }
        always {
            sh 'docker logout "$ECR_REGISTRY" || true'
            archiveArtifacts artifacts: '**/*.log', allowEmptyArchive: true
        }
    }
}
