// Lab 07 - Pipeline paramétré, credentials et conditions.
// Source de vérité : ce fichier. Le job 07-params-credentials est (re)généré
// par scripts/07-create-and-run.sh -> ne jamais le modifier dans l'UI.
pipeline {
    // Pas d'agent global : chaque stage alloue le sien.
    // C'est ce qui permet à "when { beforeAgent true }" d'éviter d'occuper un executor.
    agent none

    options {
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    parameters {
        choice(name: 'TARGET_ENV', choices: ['dev', 'recette', 'prod'], description: 'Environnement cible')
        string(name: 'VERSION', defaultValue: '1.0.0', description: 'Version (ex. 2.0.0 ou 2.0.0-SNAPSHOT)')
        booleanParam(name: 'RUN_TESTS', defaultValue: true, description: 'Exécuter le stage Tests')
        text(name: 'NOTES', defaultValue: '', description: 'Notes de version (multi-lignes)')
    }

    stages {
        stage('Infos') {
            // echo n'a pas besoin d'agent
            steps {
                echo """Build #${env.BUILD_NUMBER}
  TARGET_ENV = ${params.TARGET_ENV}
  VERSION    = ${params.VERSION}
  RUN_TESTS  = ${params.RUN_TESTS}
  NOTES      = ${params.NOTES ?: '(aucune)'}"""
            }
        }

        stage('Tests') {
            when {
                beforeAgent true
                expression { params.RUN_TESTS }
            }
            agent any
            steps {
                // Interpolation Groovy (guillemets doubles) acceptable : aucune donnée secrète
                sh "echo 'Tests de la version ${params.VERSION} : OK'"
            }
        }

        stage('Appel API') {
            agent any
            steps {
                withCredentials([usernamePassword(credentialsId: 'httpbin-creds',
                                                  usernameVariable: 'API_USER',
                                                  passwordVariable: 'API_PASS')]) {
                    // 1 minute au total pour les 3 essais
                    timeout(time: 1, unit: 'MINUTES') {
                        retry(3) {
                            // Guillemets SIMPLES : c'est le shell qui lit $API_USER/$API_PASS, pas Groovy.
                            // L'URL est construite avec les variables : le mot de passe n'est pas écrit dans Git.
                            sh 'curl -fsS --max-time 15 -u "$API_USER:$API_PASS" "https://httpbin.org/basic-auth/$API_USER/$API_PASS"'
                        }
                    }
                }
            }
        }

        stage('Token') {
            agent any
            environment {
                // Secret text -> la variable contient directement la valeur (masquée dans la console)
                TOKEN = credentials('demo-api-token')
            }
            steps {
                sh 'echo "Token reçu : $TOKEN"'
                sh 'echo "Longueur du token : ${#TOKEN} caractères"'
            }
        }

        stage('Config') {
            agent any
            steps {
                // Secret file -> la variable contient le CHEMIN d'un fichier temporaire
                withCredentials([file(credentialsId: 'app-config', variable: 'APP_CONFIG')]) {
                    sh '''
                        # Jenkins lance "sh -xe" : sans "set +x", la trace afficherait
                        # "+ DB_PASSWORD=..." en clair (le masquage ne connaît que le chemin du fichier).
                        set +x
                        set -a; . "$APP_CONFIG"; set +a
                        if [ -n "${DB_PASSWORD:-}" ]; then
                            echo "DB_PASSWORD est définie (${#DB_PASSWORD} caractères) - valeur non affichée"
                        else
                            echo "DB_PASSWORD absente de app.env" >&2
                            exit 1
                        fi
                    '''
                }
            }
        }

        stage('Déploiement prod') {
            when {
                beforeAgent true   // condition évaluée AVANT d'allouer un executor
                allOf {
                    expression { params.TARGET_ENV == 'prod' }
                    not { expression { (params.VERSION ?: '').toUpperCase().contains('SNAPSHOT') } }
                }
            }
            agent any
            steps {
                echo "Déploiement de ${params.VERSION} en PRODUCTION"
                sh "echo 'deploy ${params.VERSION} -> ${params.TARGET_ENV}'"
            }
        }
    }

    post {
        always { echo "Résultat : ${currentBuild.currentResult}" }
    }
}
