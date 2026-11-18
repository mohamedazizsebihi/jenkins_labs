// Lab 06 - CI de l'application demo (à placer à la racine du dépôt jenkins-demo-app)
pipeline {
    agent any

    options {
        timestamps()
        timeout(time: 15, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
        disableConcurrentBuilds()
    }

    triggers {
        pollSCM('H/5 * * * *')
    }

    environment {
        VENV = "${WORKSPACE}/.venv"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_SHORT   = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    env.APP_VERSION = "1.0.${env.BUILD_NUMBER}-${env.GIT_SHORT}"
                    currentBuild.displayName = "#${env.BUILD_NUMBER} (${env.APP_VERSION})"
                }
                echo "Version construite : ${env.APP_VERSION}"
            }
        }

        stage('Install') {
            steps {
                sh '''
                    python3 -m venv "$VENV"
                    . "$VENV/bin/activate"
                    pip install -q --upgrade pip
                    pip install -q -r requirements-dev.txt
                '''
            }
        }

        stage('Lint') {
            steps {
                sh '. "$VENV/bin/activate" && flake8 .'
            }
        }

        stage('Tests') {
            steps {
                // Un test rouge ne doit pas casser le pipeline : junit le marquera UNSTABLE
                catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                    sh '''
                        . "$VENV/bin/activate"
                        mkdir -p reports
                        pytest -v \
                          --junitxml=reports/junit.xml \
                          --cov=app --cov-report=xml:reports/coverage.xml --cov-report=term
                    '''
                }
            }
            post {
                always {
                    // Publie les résultats : tests en échec => build UNSTABLE
                    junit testResults: 'reports/junit.xml', allowEmptyResults: false
                }
            }
        }

        stage('Package') {
            // ne pas packager si les tests ont échoué (build UNSTABLE)
            when { expression { currentBuild.currentResult == 'SUCCESS' } }
            steps {
                sh 'tar czf "app-${APP_VERSION}.tar.gz" app.py requirements.txt Dockerfile'
                archiveArtifacts artifacts: 'app-*.tar.gz, reports/coverage.xml', fingerprint: true
            }
        }
    }

    post {
        success  { echo " ${env.APP_VERSION} prête" }
        unstable { echo '⚠️es tests échouent : build UNSTABLE' }
        failure  { echo ' Échec (lint ou installation ?)' }
        cleanup  { cleanWs() }
    }
}
