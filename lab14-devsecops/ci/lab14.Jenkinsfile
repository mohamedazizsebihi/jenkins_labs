// Lab 14 - DevSecOps : tests + couverture, SonarQube (Quality Gate bloquante), Trivy (code et image), rapports.
// Job 14-devsecops (généré par scripts/05-create-job.sh).
pipeline {
    agent none

    options {
        timestamps()
        skipDefaultCheckout()
        timeout(time: 40, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '15'))
    }

    parameters {
        string(name: 'REPO_URL', defaultValue: 'https://github.com/mohamedazizsebihi/jenkins_labs.git',
               description: 'Dépôt de l application (git://127.0.0.1/... pour les branches de test locales)')
        string(name: 'BRANCH', defaultValue: 'main', description: 'Branche à analyser')
    }

    environment {
        TRIVY_IMAGE = 'aquasec/trivy:0.76.2'
        IMAGE       = "jenkins-demo-app:lab14-${env.BUILD_NUMBER}"
    }

    stages {
        stage('Checkout') {
            agent { label 'docker' }
            steps {
                git url: params.REPO_URL, branch: params.BRANCH
                stash name: 'src', excludes: 'reports/**'
            }
        }

        stage('Tests + couverture') {
            agent { docker { image 'python:3.12-slim'; label 'docker'
                             args '-v jenkins-pip-cache:/pip-cache -e PIP_CACHE_DIR=/pip-cache -e HOME=/tmp' } }
            steps {
                unstash 'src'
                sh '''
                    pip install -q --disable-pip-version-check -r requirements-dev.txt
                    mkdir -p reports
                    python -m pytest -q -p no:cacheprovider --junitxml=reports/junit.xml \
                        --cov=app --cov-report=xml:reports/coverage.xml --cov-report=term
                '''
                stash name: 'tests', includes: 'reports/**'
            }
            post { always { junit 'reports/junit.xml' } }
        }

        stage('Analyse SonarQube') {
            agent { label 'docker' }
            steps {
                unstash 'src'
                unstash 'tests'
                withSonarQubeEnv('sonarqube') {
                    sh "\"${tool 'sonar-scanner'}/bin/sonar-scanner\" -Dsonar.projectVersion=${env.BUILD_NUMBER}"
                }
            }
        }

        stage('Quality Gate') {
            // Sans agent : l'attente du webhook SonarQube n'occupe aucun exécuteur
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Trivy FS') {
            agent { label 'docker' }
            steps {
                unstash 'src'
                sh '''
                    mkdir -p reports
                    docker volume create jenkins-trivy-cache >/dev/null
                    docker run --rm -u 0 --entrypoint chown -v jenkins-trivy-cache:/cache "$TRIVY_IMAGE" -R "$(id -u):$(id -g)" /cache
                    trivy() { docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e TRIVY_CACHE_DIR=/cache \
                                -v jenkins-trivy-cache:/cache -v "$PWD":/src -w /src "$TRIVY_IMAGE" "$@"; }
                    trivy fs --quiet --scanners vuln,secret --severity HIGH,CRITICAL --skip-dirs .git,reports \
                          --format json -o reports/trivy-fs.json .
                    trivy convert --quiet --format template --template @/contrib/html.tpl -o reports/trivy-fs.html reports/trivy-fs.json
                    trivy convert --quiet --format table reports/trivy-fs.json
                    N=$(jq '[.Results[]? | (.Vulnerabilities // [])[], (.Secrets // [])[]] | length' reports/trivy-fs.json)
                    echo "Trivy FS : $N problème(s) HIGH/CRITICAL (vulnérabilités + secrets)"
                    [ "$N" -eq 0 ]
                '''
            }
            post { always { archiveArtifacts artifacts: 'reports/trivy-fs.*', allowEmptyArchive: true } }
        }

        stage('Build image') {
            agent { label 'docker' }
            steps {
                unstash 'src'
                sh 'docker build -q --build-arg APP_VERSION="lab14-$BUILD_NUMBER" -t "$IMAGE" .'
            }
        }

        stage('Trivy image') {
            agent { label 'docker' }
            steps {
                sh '''
                    mkdir -p reports
                    trivy() { docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e TRIVY_CACHE_DIR=/cache \
                                -v jenkins-trivy-cache:/cache -v "$PWD":/src -w /src "$TRIVY_IMAGE" "$@"; }
                    # image exportée en archive : Trivy n'a pas besoin du socket Docker
                    docker save "$IMAGE" -o image.tar
                    trivy image --quiet --input image.tar --format json -o reports/trivy-image.json
                    rm -f image.tar
                    trivy convert --quiet --format template --template @/contrib/html.tpl -o reports/trivy-image.html reports/trivy-image.json
                    trivy convert --quiet --format table --severity HIGH,CRITICAL reports/trivy-image.json | tail -n +1
                    C=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL" and (.FixedVersion // "") != "")] | length' reports/trivy-image.json)
                    echo "Trivy image : $C vulnérabilité(s) CRITICAL corrigeable(s)"
                    [ "$C" -eq 0 ]
                '''
            }
            post { always { archiveArtifacts artifacts: 'reports/trivy-image.*', allowEmptyArchive: true } }
        }
    }

    post {
        always {
            script {
                node('docker') {
                    sh 'docker rmi "$IMAGE" >/dev/null 2>&1 || true; rm -f image.tar'
                }
            }
        }
    }
}
