// Lab 09 - Docker dans Jenkins : agents conteneurisés, build, smoke test et push.
// Source de vérité du job 09-docker (généré par scripts/04-lint-and-create-jobs.sh).
pipeline {
    // Aucun agent global : chaque stage choisit le sien (conteneur éphémère ou hôte Docker)
    agent none

    options {
        timestamps()
        skipDefaultCheckout()
        timeout(time: 20, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    environment {
        APP_REPO   = 'https://github.com/mohamedazizsebihi/jenkins_labs.git'
        IMAGE_NAME = 'jenkins-demo-app'
        PIP_VOLUME = 'jenkins-pip-cache'
        REGISTRY       = 'localhost:5050'   // Docker Hub : 'docker.io'
        REGISTRY_CREDS = 'registry-creds'   // Docker Hub : 'dockerhub-creds'
    }

    stages {
        stage('Préparation') {
            agent any
            steps {
                git url: env.APP_REPO, branch: 'main'
                script {
                    env.GIT_SHORT   = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    env.APP_VERSION = env.BUILD_NUMBER
                }
                withCredentials([usernamePassword(credentialsId: env.REGISTRY_CREDS,
                                                  usernameVariable: 'REG_USER', passwordVariable: 'REG_TOKEN')]) {
                    script { env.IMAGE = "${env.REGISTRY}/${env.REG_USER}/${env.IMAGE_NAME}" }
                }
                // Volume nommé du cache pip : créé par le démon (root) -> on le donne à l'UID de jenkins,
                // sinon le conteneur lancé avec "-u <uid jenkins>" ne peut pas y écrire.
                sh '''
                    docker volume create "$PIP_VOLUME" >/dev/null
                    docker run --rm -v "$PIP_VOLUME":/cache python:3.12-slim chown -R "$(id -u):$(id -g)" /cache
                '''
                stash name: 'src'
                echo "Image ${env.IMAGE} | tags : ${env.BUILD_NUMBER}, ${env.GIT_SHORT}, latest | APP_VERSION=${env.APP_VERSION}"
            }
        }

        stage('Lint') {
            agent {
                docker {
                    image 'python:3.12-slim'
                    args '-v jenkins-pip-cache:/pip-cache -e PIP_CACHE_DIR=/pip-cache -e HOME=/tmp'
                }
            }
            steps {
                unstash 'src'
                sh '''
                    echo "Python utilisé : $(command -v python) - $(python --version) - hôte du conteneur : $(hostname)"
                    echo "Cache pip avant : $(du -sh /pip-cache | cut -f1)"
                    pip install -q --disable-pip-version-check -r requirements-dev.txt
                    python -m flake8 .
                '''
            }
        }

        stage('Tests') {
            agent {
                docker {
                    image 'python:3.12-slim'
                    args '-v jenkins-pip-cache:/pip-cache -e PIP_CACHE_DIR=/pip-cache -e HOME=/tmp'
                }
            }
            steps {
                unstash 'src'
                sh '''
                    echo "Cache pip avant : $(du -sh /pip-cache | cut -f1) (réutilisé : pas de re-téléchargement)"
                    pip install -q --disable-pip-version-check -r requirements-dev.txt
                    mkdir -p reports
                    python -m pytest -v --junitxml=reports/junit.xml
                '''
            }
            post {
                always { junit testResults: 'reports/junit.xml', allowEmptyResults: false }
            }
        }

        stage('Build image') {
            agent any
            steps {
                unstash 'src'
                sh '''
                    docker build --pull \
                        --build-arg APP_VERSION="$APP_VERSION" \
                        --label org.opencontainers.image.revision="$GIT_SHORT" \
                        -t "$IMAGE:$BUILD_NUMBER" -t "$IMAGE:$GIT_SHORT" -t "$IMAGE:latest" .
                    docker image ls "$IMAGE"
                '''
            }
        }

        stage('Smoke test') {
            agent any
            steps {
                sh '''
                    NAME="smoke-$BUILD_TAG"
                    # 127.0.0.1::5000 -> Docker choisit lui-même un port libre de l'hôte
                    docker run -d --name "$NAME" -p 127.0.0.1::5000 "$IMAGE:$BUILD_NUMBER"
                    PORT=$(docker port "$NAME" 5000/tcp | head -1 | awk -F: '{print $NF}')
                    echo "Port libre attribué : $PORT"
                    for i in $(seq 1 30); do
                        curl -fsS "http://127.0.0.1:$PORT/health" 2>/dev/null && break
                        sleep 1
                    done
                    echo
                    curl -fsS "http://127.0.0.1:$PORT/health" | jq -e '.status == "up"'
                    BODY=$(curl -fsS "http://127.0.0.1:$PORT/")
                    echo "GET / -> $BODY"
                    [ "$(echo "$BODY" | jq -r .version)" = "$APP_VERSION" ]
                '''
            }
            post {
                // toujours supprimer le conteneur, même si le test échoue
                always { sh 'docker rm -f "smoke-$BUILD_TAG"' }
            }
        }

        stage('Push') {
            agent any
            steps {
                withCredentials([usernamePassword(credentialsId: env.REGISTRY_CREDS,
                                                  usernameVariable: 'REG_USER', passwordVariable: 'REG_TOKEN')]) {
                    sh '''
                        # Config Docker jetable : le jeton n'est jamais écrit dans ~jenkins/.docker
                        export DOCKER_CONFIG="$(mktemp -d)"
                        trap 'docker logout "$REGISTRY"; rm -rf "$DOCKER_CONFIG"' EXIT
                        printf '%s' "$REG_TOKEN" | docker login "$REGISTRY" -u "$REG_USER" --password-stdin
                        for tag in "$BUILD_NUMBER" "$GIT_SHORT" latest; do
                            docker push "$IMAGE:$tag"
                        done
                    '''
                }
            }
        }
    }

    post {
        always {
            script {
                node {
                    // Ménage : aucun conteneur ni image du build ne doit rester sur l'hôte
                    sh '''
                        docker rm -f "smoke-$BUILD_TAG" 2>/dev/null || true
                        if [ -n "${IMAGE:-}" ]; then
                            for tag in "$BUILD_NUMBER" "${GIT_SHORT:-none}" latest; do
                                docker rmi "$IMAGE:$tag" 2>/dev/null || true
                            done
                        fi
                    '''
                }
            }
        }
        success { echo "Publié : ${env.IMAGE}:${env.BUILD_NUMBER}, :${env.GIT_SHORT}, :latest" }
    }
}
