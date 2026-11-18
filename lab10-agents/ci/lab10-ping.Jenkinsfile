// Lab 10 - Job minimal qui DEMANDE le label ssh-agent (tâche 7 : file d'attente quand l'agent est hors ligne)
pipeline {
    agent { label 'ssh-agent' }
    options { timestamps() }
    stages {
        stage('Ping') {
            steps { sh 'echo "Exécuté sur $NODE_NAME ($(hostname))"' }
        }
    }
}
