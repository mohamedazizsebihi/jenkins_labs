#!/usr/bin/env bash
# Lab 11 - tâche 11 : déploiement d'un autre tag puis rollback (versions mémorisées sur le serveur)
. "$(dirname "$0")/lib.sh"
TAG=${1:-1.1.0}
approve() { # $1 tag, $2 action
  local n; n=$(start_build -p EC2_HOST="$EC2_HOST" -p IMAGE_TAG="$1" -p ACTION="$2")
  wait_input "$n" >/dev/null
  echo "   build #$n ($2 $1) : validation admin HTTP $(jpost "$JENKINS_USER_ID" "$JENKINS_API_TOKEN" "/job/$JOB/$n/input/DeployProd/proceedEmpty") -> $(wait_end "$n")"
  console_grep "$n" 'validé par|demo-app .* servie|Version servie' | sed 's/^/     /'
}
echo "== version servie au départ : $(served)"
echo "== déploiement de $TAG"
approve "$TAG" deploy
echo "   curl : $(served)"
echo "== rollback (ACTION=rollback)"
approve "$TAG" rollback
echo "   curl : $(served)"
echo "== état mémorisé sur le serveur"
ssh -i "$PEM" -o BatchMode=yes ubuntu@"$EC2_HOST" 'sudo cat /opt/demo-app/versions.json; echo; sudo docker ps --format "{{.Names}}  {{.Image}}  {{.Status}}"'
