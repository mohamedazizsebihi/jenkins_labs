#!/usr/bin/env bash
# Lab 07 - tâche 9 : ANTI-PATTERN volontaire. Rejoue le dernier build en passant
# les secrets au shell par interpolation Groovy (guillemets doubles), puis relève l'avertissement.
set -euo pipefail
cd "$(dirname "$0")/.."
JCLI=./scripts/jcli
JOB=07-params-credentials
URL="${JENKINS_URL:-http://localhost:8080/}"; URL="${URL%/}"
SRC=ci/lab07.Jenkinsfile

NEEDLE='-u "$API_USER:$API_PASS"'
NEW='sh "curl -fsS --max-time 15 -u ${API_USER}:${API_PASS} https://httpbin.org/basic-auth/${API_USER}/${API_PASS}"'
grep -qF -- "$NEEDLE" "$SRC" || { echo "ligne curl introuvable dans $SRC" >&2; exit 1; }
script=$(awk -v needle="$NEEDLE" -v new="$NEW" \
    'index($0, needle) { match($0, /^[ \t]*/); print substr($0, 1, RLENGTH) new; next } { print }' "$SRC")

last=$(curl -fsS "$URL/job/$JOB/lastBuild/buildNumber")
next=$((last + 1))
echo "== replay-pipeline du build #$last -> build #$next (ligne modifiée :)"
echo "   $NEW"
printf '%s\n' "$script" | $JCLI replay-pipeline "$JOB" -n "$last"

for _ in $(seq 1 30); do
    curl -fsS -o /dev/null "$URL/job/$JOB/$next/api/json" 2>/dev/null && break
    sleep 1
done
$JCLI console "$JOB" "$next" -f >/dev/null || true

echo "== Avertissement relevé dans la console du build #$next"
$JCLI console "$JOB" "$next" | grep -A3 -i 'Groovy String interpolation' || echo "(aucun avertissement trouvé)"
