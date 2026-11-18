#!/usr/bin/env bash
# Lab 11 - tâche 10 : second déploiement refusé par l'API -> ABORTED, rien ne change sur le serveur
. "$(dirname "$0")/lib.sh"
TAG=${1:-1.1.0}
echo "== version servie avant : $(served)"
N=$(start_build -p EC2_HOST="$EC2_HOST" -p IMAGE_TAG="$TAG" -p ACTION=deploy)
echo "== build #$N lancé (IMAGE_TAG=$TAG) ; input en attente :"
wait_input "$N" | jq -c '.[] | {id, message}'
echo "== admin refuse : POST /job/$JOB/$N/input/DeployProd/abort"
echo "   HTTP $(jpost "$JENKINS_USER_ID" "$JENKINS_API_TOKEN" "/job/$JOB/$N/input/DeployProd/abort")"
echo "   build #$N : $(wait_end "$N")"
console_grep "$N" 'Rejected by|Aborted by|refusé|^Finished' | sed 's/^/   /'
echo "== version servie après : $(served)"
