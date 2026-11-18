// Lab 10 - Même travail que lab10.Jenkinsfile, mais tout en séquence (comparaison des durées).
// Job 10-sequentiel.
pipeline {
    agent none

    options {
        timestamps()
        skipDefaultCheckout()
        timeout(time: 45, unit: 'MINUTES')
    }

    environment {
        APP_REPO = 'https://github.com/mohamedazizsebihi/jenkins_labs.git'
    }

    stages {
        stage('Build') {
            agent { label 'ssh-agent' }
            steps {
                git url: env.APP_REPO, branch: 'main'
                sh '''
                    mkdir -p dist
                    git archive --format=tar.gz -o dist/app.tar.gz HEAD app.py requirements.txt Dockerfile
                    cd dist && sha256sum app.tar.gz > checksum.sha256
                '''
                stash name: 'dist', includes: 'dist/**'
                stash name: 'src',  excludes: 'dist/**'
            }
        }

        stage('Qualité + compatibilité (séquentiel)') {
            agent { label 'docker' }
            steps {
                unstash 'src'
                script {
                    def args = '-v jenkins-pip-cache:/pip-cache -e PIP_CACHE_DIR=/pip-cache -e HOME=/tmp'
                    docker.image('python:3.12-slim').inside(args) {
                        sh 'pip install -q --disable-pip-version-check flake8 && python -m flake8 .'
                    }
                    docker.image('python:3.12-slim').inside(args) {
                        sh 'pip install -q --disable-pip-version-check -r requirements-dev.txt && python -m pytest -q -p no:cacheprovider'
                    }
                    docker.image('python:3.12-slim').inside(args) {
                        sh 'pip install -q --disable-pip-version-check pip-audit && python -m pip_audit --progress-spinner off -r requirements.txt'
                    }
                    for (img in ['3.10-slim', '3.11-slim', '3.11-alpine', '3.12-slim', '3.12-alpine']) {
                        docker.image("python:${img}").inside(args) {
                            sh 'python --version && pip install -q --disable-pip-version-check -r requirements-dev.txt && python -m pytest -q -p no:cacheprovider'
                        }
                    }
                }
            }
        }

        stage('Vérification') {
            agent { label 'ssh-agent' }
            steps {
                deleteDir()
                unstash 'dist'
                sh 'cd dist && sha256sum -c checksum.sha256'
            }
        }
    }
}
