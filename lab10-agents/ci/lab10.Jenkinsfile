// Lab 10 - Pipeline distribué : labels, parallel (failFast), matrix, stash/unstash.
// Job 10-distribue (généré par scripts/04-create-jobs.sh).
pipeline {
    agent none

    options {
        timestamps()
        skipDefaultCheckout()
        timeout(time: 30, unit: 'MINUTES')
    }

    environment {
        APP_REPO = 'https://github.com/mohamedazizsebihi/jenkins_labs.git'
    }

    stages {
        stage('Build') {
            agent { label 'ssh-agent' }
            steps {
                echo "Nœud : ${env.NODE_NAME}"
                git url: env.APP_REPO, branch: 'main'
                sh '''
                    echo "hôte : $(hostname) | python : $(command -v python3 || echo absent)"
                    mkdir -p dist
                    # git archive produit le .tar.gz sans dépendre de tar sur l'agent
                    git archive --format=tar.gz -o dist/app.tar.gz HEAD app.py requirements.txt Dockerfile
                    cd dist && sha256sum app.tar.gz > checksum.sha256 && cat checksum.sha256
                '''
                stash name: 'dist', includes: 'dist/**'
                stash name: 'src',  excludes: 'dist/**'
            }
        }

        stage('Qualité') {
            failFast true          // une branche en échec interrompt les autres
            parallel {
                stage('Lint') {
                    agent { docker { image 'python:3.12-slim'; label 'docker'
                                     args '-v jenkins-pip-cache:/pip-cache -e PIP_CACHE_DIR=/pip-cache -e HOME=/tmp' } }
                    steps {
                        echo "Nœud : ${env.NODE_NAME}"
                        unstash 'src'
                        sh 'pip install -q --disable-pip-version-check flake8 && python -m flake8 .'
                    }
                }
                stage('Tests') {
                    agent { docker { image 'python:3.12-slim'; label 'docker'
                                     args '-v jenkins-pip-cache:/pip-cache -e PIP_CACHE_DIR=/pip-cache -e HOME=/tmp' } }
                    steps {
                        echo "Nœud : ${env.NODE_NAME}"
                        unstash 'src'
                        sh '''
                            pip install -q --disable-pip-version-check -r requirements-dev.txt
                            mkdir -p reports
                            python -m pytest -q -p no:cacheprovider --junitxml=reports/junit.xml
                        '''
                    }
                    post { always { junit 'reports/junit.xml' } }
                }
                stage('Sécurité') {
                    agent { docker { image 'python:3.12-slim'; label 'docker'
                                     args '-v jenkins-pip-cache:/pip-cache -e PIP_CACHE_DIR=/pip-cache -e HOME=/tmp' } }
                    steps {
                        echo "Nœud : ${env.NODE_NAME}"
                        unstash 'src'
                        sh '''
                            pip install -q --disable-pip-version-check pip-audit
                            python -m pip_audit --progress-spinner off -r requirements.txt
                        '''
                    }
                }
            }
        }

        stage('Compatibilité') {
            matrix {
                axes {
                    axis { name 'PYTHON';  values '3.10', '3.11', '3.12' }
                    axis { name 'VARIANT'; values 'slim', 'alpine' }
                }
                excludes {
                    exclude {
                        axis { name 'PYTHON';  values '3.10' }
                        axis { name 'VARIANT'; values 'alpine' }
                    }
                }
                agent { docker { image "python:${PYTHON}-${VARIANT}"; label 'docker'
                                 args '-v jenkins-pip-cache:/pip-cache -e PIP_CACHE_DIR=/pip-cache -e HOME=/tmp' } }
                stages {
                    stage('pytest') {
                        steps {
                            echo "Nœud : ${env.NODE_NAME} | python:${PYTHON}-${VARIANT}"
                            unstash 'src'
                            sh '''
                                python --version
                                pip install -q --disable-pip-version-check -r requirements-dev.txt
                                python -m pytest -q -p no:cacheprovider
                            '''
                        }
                    }
                }
            }
        }

        stage('Vérification') {
            agent { label 'ssh-agent' }
            steps {
                echo "Nœud : ${env.NODE_NAME}"
                deleteDir()                 // on repart d'un workspace vide : seul le stash apporte dist/
                unstash 'dist'
                sh 'cd dist && sha256sum -c checksum.sha256'
            }
        }
    }
}
