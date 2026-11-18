// Lab 09 - Variante : même chaîne avec l'API Groovy du plugin Docker Pipeline
// (docker.image().inside, docker.build, withRun, withRegistry). Job : 09-docker-plugin.
// Tags "plugin-*" : on n'écrase jamais les tags immuables du job 09-docker ni "latest".
pipeline {
    agent none

    options {
        timestamps()
        skipDefaultCheckout()
        timeout(time: 20, unit: 'MINUTES')
    }

    environment {
        APP_REPO       = 'https://github.com/mohamedazizsebihi/jenkins_labs.git'
        IMAGE_NAME     = 'jenkins-demo-app'
        REGISTRY_URL   = 'http://localhost:5050'   // Docker Hub : 'https://index.docker.io/v1/'
        REGISTRY       = 'localhost:5050'
        REGISTRY_CREDS = 'registry-creds'          // Docker Hub : 'dockerhub-creds'
    }

    stages {
        stage('Tests, build, smoke, push (API Groovy)') {
            agent any
            steps {
                git url: env.APP_REPO, branch: 'main'
                script {
                    env.GIT_SHORT = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    withCredentials([usernamePassword(credentialsId: env.REGISTRY_CREDS,
                                                      usernameVariable: 'REG_USER', passwordVariable: 'REG_TOKEN')]) {
                        // nom NON qualifié : withRegistry ajoute lui-même l'hôte du registre au push
                        env.IMAGE_REPO = "${env.REG_USER}/${env.IMAGE_NAME}"
                    }

                    // 1. Lint + tests dans un conteneur éphémère
                    docker.image('python:3.12-slim').inside('-v jenkins-pip-cache:/pip-cache -e PIP_CACHE_DIR=/pip-cache -e HOME=/tmp') {
                        sh '''
                            pip install -q --disable-pip-version-check -r requirements-dev.txt
                            python -m flake8 .
                            python -m pytest -q
                        '''
                    }

                    // 2. Build
                    def img = docker.build("${env.IMAGE_REPO}:plugin-${env.BUILD_NUMBER}",
                                           "--build-arg APP_VERSION=plugin-${env.BUILD_NUMBER} .")

                    // 3. Smoke test : withRun démarre le conteneur et le supprime à la sortie du bloc
                    img.withRun('-p 127.0.0.1::5000') { c ->
                        sh """
                            PORT=\$(docker port ${c.id} 5000/tcp | head -1 | awk -F: '{print \$NF}')
                            for i in \$(seq 1 30); do
                                curl -fsS http://127.0.0.1:\$PORT/health 2>/dev/null && exit 0
                                sleep 1
                            done
                            exit 1
                        """
                    }

                    // 4. Push : withRegistry fait docker login / logout avec le credential
                    docker.withRegistry(env.REGISTRY_URL, env.REGISTRY_CREDS) {
                        img.push()                          // plugin-<n° de build>
                        img.push("plugin-${env.GIT_SHORT}")
                    }
                }
            }
            post {
                always {
                    sh '''
                        for tag in "plugin-$BUILD_NUMBER" "plugin-${GIT_SHORT:-none}"; do
                            docker rmi "$IMAGE_REPO:$tag" "$REGISTRY/$IMAGE_REPO:$tag" 2>/dev/null || true
                        done
                    '''
                }
            }
        }
    }
}
