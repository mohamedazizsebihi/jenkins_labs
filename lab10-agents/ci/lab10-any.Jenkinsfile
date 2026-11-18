// Lab 10 - Job SANS label (agent any) : ne doit jamais tourner sur agent-ssh-1 (mode EXCLUSIVE)
pipeline {
    agent any
    options { timestamps() }
    stages {
        stage('Où ?') {
            steps { sh 'echo "Exécuté sur ${NODE_NAME:-?} ($(hostname))"' }
        }
    }
}
