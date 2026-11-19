#!/usr/bin/env bash
# Lab 14 - tâche 12 : exécute audit-durcissement.groovy par l'API (POST /scriptText), jeton admin
. "$(dirname "$0")/lib.sh"
echo "POST $URL/scriptText  (script=@scripts/audit-durcissement.groovy)"
printf 'user = "%s:%s"\n' "$JENKINS_USER_ID" "$JENKINS_API_TOKEN" \
  | curl -K - -fsS -X POST "$URL/scriptText" --data-urlencode "script@$LAB_DIR/scripts/audit-durcissement.groovy"
