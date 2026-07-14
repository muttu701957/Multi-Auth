pipeline {

    agent any

    environment {

        AWS_ACCESS_KEY_ID     = credentials('AWS_ACCESS_KEY_ID')
        AWS_SECRET_ACCESS_KEY = credentials('AWS_SECRET_ACCESS_KEY')

        AWS_REGION            = credentials('AWS_REGION')
        AWS_ACCOUNT_ID        = credentials('AWS_ACCOUNT_ID')

        EC2_USER              = credentials('EC2_USER')
        EC2_PUBLIC_IP         = credentials('EC2_PUBLIC_IP')

        multi_auth_repo       = credentials('multi_auth_repo')

        
        // Rollback / health-check trigger logic — explicit, no magic numbers
      
        HEALTH_CHECK_ENDPOINT   = '/'     // root endpoint, checked for health
        HEALTH_CHECK_STATUS     = '200'   // expected HTTP status for a healthy app
        HEALTH_CHECK_RETRIES    = '10'    // max probe attempts before declaring unhealthy
        HEALTH_CHECK_INTERVAL   = '5'     // seconds between retries
        // Total wait time = RETRIES * INTERVAL = 50s

        BACKEND_PORT             = '5000'
    }

    stages {

        stage('Checkout') {
            steps {
                git(
                    branch: 'main',
                    url: 'https://github.com/muttu701957/Multi-Auth.git',
                    credentialsId: 'github-token'
                )
            }
        }

        // Repo root IS the backend service — no subfolder to cd into.
        stage('Install Dependencies') {
            steps {
                sh '''
                npm install --legacy-peer-deps
                '''
            }
        }

        stage('AWS Login') {

            steps {
                script {

                    env.ECR_REGISTRY = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

                    sh '''
                    aws configure set AWS_ACCESS_KEY_ID $AWS_ACCESS_KEY_ID
                    aws configure set AWS_SECRET_ACCESS_KEY $AWS_SECRET_ACCESS_KEY
                    aws configure set default.region $AWS_REGION

                    aws ecr get-login-password --region $AWS_REGION | \
                    docker login \
                    --username AWS \
                    --password-stdin \
                    $ECR_REGISTRY
                    '''

                }
            }

        }

        stage('Build Backend Image') {

            steps {
                script {

                    env.BACKEND_IMAGE_LATEST = "${ECR_REGISTRY}/${multi_auth_repo}:backend-latest"
                    env.BACKEND_IMAGE        = "${ECR_REGISTRY}/${multi_auth_repo}:backend-${BUILD_NUMBER}"

                    sh """
                    docker build \
                    -f Dockerfile \
                    -t ${BACKEND_IMAGE} \
                    -t ${BACKEND_IMAGE_LATEST} \
                    .

                    docker push ${BACKEND_IMAGE}
                    docker push ${BACKEND_IMAGE_LATEST}
                    """

                }
            }

        }

        stage('Deploy Backend') {

            steps {
                withCredentials([
                    string(credentialsId: 'EC2_SSH_KEY_B64', variable: 'EC2_SSH_KEY_B64')
                ]) {

                    sh """
mkdir -p ~/.ssh
echo "\$EC2_SSH_KEY_B64" | base64 -d > ~/.ssh/id_rsa
chmod 600 ~/.ssh/id_rsa

ssh -i ~/.ssh/id_rsa \
-o StrictHostKeyChecking=no \
${EC2_USER}@${EC2_PUBLIC_IP} << 'REMOTE'

set -e

DEPLOY_DIR=/home/ubuntu/Multi-Auth
mkdir -p \$DEPLOY_DIR
STATE_FILE=\$DEPLOY_DIR/.deployed_tag
NEW_TAG="${BACKEND_IMAGE}"
PREV_TAG=\$(cat "\$STATE_FILE" 2>/dev/null || echo "")

aws ecr get-login-password --region ${AWS_REGION} | \
docker login --username AWS --password-stdin ${ECR_REGISTRY}

docker pull "\$NEW_TAG"

docker stop multi-auth-back || true
docker rm multi-auth-back || true

docker run -dit \
--name multi-auth-back \
--restart unless-stopped \
-p ${BACKEND_PORT}:${BACKEND_PORT} \
--env-file \$DEPLOY_DIR/.env \
"\$NEW_TAG"

HEALTHY=false
for i in \$(seq 1 ${HEALTH_CHECK_RETRIES}); do
  CODE=\$(curl -s -o /dev/null -w "%{http_code}" \
          http://localhost:${BACKEND_PORT}${HEALTH_CHECK_ENDPOINT} || echo "000")
  echo "Health check attempt \$i/${HEALTH_CHECK_RETRIES}: HTTP \$CODE"

  if [ "\$CODE" = "${HEALTH_CHECK_STATUS}" ]; then
    HEALTHY=true
    break
  fi
  sleep ${HEALTH_CHECK_INTERVAL}
done

if [ "\$HEALTHY" = "true" ]; then
  if echo "\$NEW_TAG" > "\$STATE_FILE" 2>/tmp/state_write_err; then
    echo "Backend healthy. Deployed \$NEW_TAG"
  else
    echo "WARNING: Backend is healthy and running \$NEW_TAG, but failed to update state file \$STATE_FILE:"
    cat /tmp/state_write_err
    echo "Fix permissions on \$STATE_FILE before the next deploy, or rollback will not work correctly."
    exit 1
  fi
else
  echo "Backend health check FAILED after ${HEALTH_CHECK_RETRIES} attempts (~\$(( ${HEALTH_CHECK_RETRIES} * ${HEALTH_CHECK_INTERVAL} ))s). Rolling back..."

  if [ -n "\$PREV_TAG" ]; then
    docker pull "\$PREV_TAG"
    docker stop multi-auth-back || true
    docker rm multi-auth-back || true
    docker run -dit \
    --name multi-auth-back \
    --restart unless-stopped \
    -p ${BACKEND_PORT}:${BACKEND_PORT} \
    --env-file \$DEPLOY_DIR/.env \
    "\$PREV_TAG"

    ROLLBACK_CODE=\$(curl -s -o /dev/null -w "%{http_code}" \
                    http://localhost:${BACKEND_PORT}${HEALTH_CHECK_ENDPOINT} || echo "000")

    if [ "\$ROLLBACK_CODE" = "${HEALTH_CHECK_STATUS}" ]; then
      echo "Rolled back to \$PREV_TAG successfully — it is healthy."
    else
      echo "ROLLBACK IMAGE ALSO UNHEALTHY (HTTP \$ROLLBACK_CODE). Manual intervention required."
    fi
  else
    echo "No previous successful deployment recorded in \$STATE_FILE — cannot auto-rollback. Manual intervention required."
  fi

  docker image prune -f
  exit 1
fi

docker image prune -f

REMOTE
"""

                }
            }

        }

    }

    post {

        success {
            echo "Deployment Completed Successfully"
        }

        failure {
            echo "Deployment Failed — check console output above for health-check / rollback details."
        }

        always {
            cleanWs()
        }

    }

}
