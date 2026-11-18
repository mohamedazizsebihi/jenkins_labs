#!/usr/bin/env bash
# Lab 11 - tâches 6 à 8 : build lancé en arrière-plan, input listé par l'API, tentative de validation par dev1
. "$(dirname "$0")/lib.sh"
TAG=${1:-1.0.0}
echo "== 6. jcli build $JOB -p EC2_HOST=$EC2_HOST -p IMAGE_TAG=$TAG -p ACTION=deploy   (sans -s)"
N=$(start_build -p EC2_HOST="$EC2_HOST" -p IMAGE_TAG="$TAG" -p ACTION=deploy)
echo "$N" > "$LAB_DIR/.last-build"
echo "   build #$N lancé en arrière-plan"
echo "== 7. GET /job/$JOB/$N/wfapi/pendingInputActions"
wait_input "$N" | jq '[.[] | {id, message, proceedText, proceedUrl, abortUrl}]'
echo "== 8. dev1 tente de valider : POST /job/$JOB/$N/input/DeployProd/proceedEmpty"
echo "   HTTP $(jpost "$DEV1_USER_ID" "$DEV1_API_TOKEN" "/job/$JOB/$N/input/DeployProd/proceedEmpty")"
echo "   motif : $(printf 'user = "%s:%s"\n' "$DEV1_USER_ID" "$DEV1_API_TOKEN" | curl -K - -s -X POST "$URL/job/$JOB/$N/input/DeployProd/proceedEmpty" | sed -e 's/<[^>]*>/ /g' | tr -s ' \n' | grep -oE 'You need to be [^ ]+ to submit this' | head -1)"
echo "   (dev1 peut lire le job : GET -> HTTP $(printf 'user = "%s:%s"\n' "$DEV1_USER_ID" "$DEV1_API_TOKEN" | curl -K - -s -o /dev/null -w '%{http_code}' "$URL/job/$JOB/api/json"))"
echo "   input toujours en attente : $(jget "/job/$JOB/$N/wfapi/pendingInputActions" | jq -r '.[0].id // "aucun"')"
echo "   état du build #$N : $(result "$N")"
