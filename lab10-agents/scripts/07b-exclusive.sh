#!/usr/bin/env bash
# Lab 10 - critère : agent-ssh-1 (EXCLUSIVE) ne prend PAS un build sans label, même s'il est libre.
# On met le contrôleur hors ligne : le job "agent any" doit attendre au lieu d'aller sur l'agent.
set -euo pipefail
cd "$(dirname "$0")/.."
JCLI=./scripts/jcli
URL="${JENKINS_URL:-http://localhost:8080/}"; URL="${URL%/}"
BUILTIN='(built-in)'

echo "== contrôleur hors ligne, agent-ssh-1 en ligne et libre"
$JCLI offline-node "$BUILTIN" -m "Lab 10 - test du mode EXCLUSIVE"
bash scripts/06-nodes-api.sh
echo "== build 10-any (agent any, aucun label)"
$JCLI build 10-any
sleep 8
echo "== API /queue/api/json"
curl -fsS "$URL/queue/api/json" | jq -r '.items[] | "  file : \(.task.name // "node{} du pipeline \(.url)") | raison : \(.why)"'
echo "== contrôleur remis en ligne"
$JCLI online-node "$BUILTIN"
for _ in $(seq 1 30); do [ "$(curl -fsS "$URL/queue/api/json" | jq '.items | length')" = 0 ] && break; sleep 1; done
N=$(curl -fsS "$URL/job/10-any/lastBuild/buildNumber")
$JCLI console 10-any "$N" -f >/dev/null || true
$JCLI console 10-any "$N" | sed -E 's/\x1b\[8mha:[^\x1b]*\x1b\[0m//g' | grep -E 'Running on|Exécuté sur|Finished'
