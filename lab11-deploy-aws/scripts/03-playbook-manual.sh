#!/usr/bin/env bash
# Lab 11 - tâche 3 : le playbook lancé À LA MAIN depuis WSL (avant tout pipeline)
set -euo pipefail
cd "$(dirname "$0")/.."
. ./.aws-state.env
export ANSIBLE_SSH_ARGS='-o StrictHostKeyChecking=accept-new' ANSIBLE_FORCE_COLOR=false
ansible-playbook -i "$EC2_HOST," -u ubuntu --private-key "$PEM" ../jenkins-demo-app/ansible/deploy.yml \
    -e image_name="$ECR_REGISTRY/$ECR_REPO" -e image_tag=1.0.0
echo "== curl http://$EC2_HOST/"
curl -fsS "http://$EC2_HOST/" | jq .
