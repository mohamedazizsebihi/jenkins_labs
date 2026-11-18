#!/usr/bin/env bash
# Lab 11 - tâche 9 : validation par admin via l'API, suivi du build, vérification de l'application
. "$(dirname "$0")/lib.sh"
N=${1:-$(cat "$LAB_DIR/.last-build")}
echo "== 9. admin valide : POST /job/$JOB/$N/input/DeployProd/proceedEmpty"
echo "   HTTP $(jpost "$JENKINS_USER_ID" "$JENKINS_API_TOKEN" "/job/$JOB/$N/input/DeployProd/proceedEmpty")"
echo "   build #$N : $(wait_end "$N")"
echo "== console du build #$N (valideur, Ansible, smoke test)"
console_grep "$N" 'Approved by|validé par|demo-app .* servie|PLAY RECAP|ok=[0-9]|Version servie|^Finished' | sed 's/^/   /'
echo "== curl http://$EC2_HOST/"
served
