// Lab 11 - Déploiement continu sur AWS EC2 avec Ansible ; approbation manuelle traitée par l'API REST.
// Job 11-deploy-aws (généré par scripts/05-create-job.sh).
pipeline {
    agent none

    options {
        disableConcurrentBuilds()          // jamais deux déploiements simultanés sur la même cible
        timestamps()
        skipDefaultCheckout()
        timeout(time: 45, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    parameters {
        string(name: 'EC2_HOST',  defaultValue: '',       description: 'IP publique (ou DNS) de l instance EC2 cible')
        string(name: 'IMAGE_TAG', defaultValue: 'latest', description: 'Tag de l image demo-app a deployer')
        choice(name: 'ACTION', choices: ['deploy', 'rollback'],
               description: 'deploy = IMAGE_TAG ; rollback = version precedente memorisee sur le serveur')
    }

    environment {
        APP_REPO   = 'https://github.com/mohamedazizsebihi/jenkins_labs.git'
        IMAGE_REPO = 'lab11/jenkins-demo-app'
        // ECR_REGISTRY : variable globale fournie par JCasC (00-base.yaml) depuis secrets.env, hors de Git
        ANSIBLE_SSH_ARGS    = '-o StrictHostKeyChecking=accept-new -o ControlMaster=auto -o ControlPersist=60s'
        ANSIBLE_FORCE_COLOR = 'false'
    }

    stages {
        stage('Contrôles') {
            agent { label 'docker' }
            steps {
                script {
                    if (!params.EC2_HOST?.trim()) {
                        error 'Paramètre EC2_HOST obligatoire (IP publique de l instance EC2)'
                    }
                    if (!env.ECR_REGISTRY?.trim()) {
                        error 'Variable globale ECR_REGISTRY absente (JCasC 00-base.yaml)'
                    }
                }
                git url: env.APP_REPO, branch: 'main'
                sh 'ansible-playbook --syntax-check -i "$EC2_HOST," ansible/deploy.yml'
                // La clé privée reste dans l'agent SSH du build : jamais écrite dans le workspace
                sshagent(credentials: ['ec2-ssh-key']) {
                    sh 'ansible all -i "$EC2_HOST," -u ubuntu -m ping'
                }
                stash name: 'ansible', includes: 'ansible/**'
            }
        }

        stage('Approbation') {
            // Aucun agent : l'attente humaine n'occupe aucun exécuteur
            options { timeout(time: 15, unit: 'MINUTES') }
            steps {
                script {
                    def cible = params.ACTION == 'rollback' ? 'la version précédente' : params.IMAGE_TAG
                    env.APPROVER = input(id: 'DeployProd',
                                         message: "Déployer ${cible} sur ${params.EC2_HOST} ?",
                                         ok: 'Déployer',
                                         submitter: 'admin',
                                         submitterParameter: 'APPROVER')
                }
                echo "Déploiement validé par : ${env.APPROVER}"
            }
        }

        stage('Déploiement') {
            agent { label 'docker' }
            steps {
                unstash 'ansible'
                sshagent(credentials: ['ec2-ssh-key']) {
                    sh '''
                        ROLLBACK=false; [ "$ACTION" = rollback ] && ROLLBACK=true
                        ansible-playbook -i "$EC2_HOST," -u ubuntu ansible/deploy.yml \
                            -e image_name="$ECR_REGISTRY/$IMAGE_REPO" \
                            -e image_tag="$IMAGE_TAG" \
                            -e rollback=$ROLLBACK
                    '''
                }
            }
        }

        stage('Smoke test') {
            agent { label 'docker' }
            steps {
                retry(5) {
                    sleep 3
                    sh 'curl -fsS --max-time 5 "http://$EC2_HOST/health"'
                }
                sh 'echo "Version servie par http://$EC2_HOST/ : $(curl -fsS "http://$EC2_HOST/" | jq -r .version)"'
            }
        }
    }

    post {
        success { echo "OK : ${params.ACTION} sur ${params.EC2_HOST}, validé par ${env.APPROVER}" }
        aborted { echo "Déploiement refusé ou expiré : rien n'a été modifié sur ${params.EC2_HOST}" }
    }
}
