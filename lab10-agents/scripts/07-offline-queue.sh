#!/usr/bin/env bash
# Lab 10 - tâche 7 : agent hors ligne avec motif -> un build qui le demande attend dans la file
set -euo pipefail
cd "$(dirname "$0")/.."
JCLI=./scripts/jcli
URL="${JENKINS_URL:-http://localhost:8080/}"; URL="${URL%/}"
queue() { curl -fsS "$URL/queue/api/json" | jq -r '.items[] | "  file : \(.task.name // "node{} du pipeline \(.url)") | bloqué=\(.blocked) | buildable=\(.buildable) | raison : \(.why)"'; }

echo "== offline-node agent-ssh-1 -m ..."
$JCLI offline-node agent-ssh-1 -m "Maintenance Lab 10 - mise à jour planifiée de l agent"
bash scripts/06-nodes-api.sh
echo "== build 10-ping (demande le label ssh-agent), sans attendre"
$JCLI build 10-ping
sleep 6
echo "== API /queue/api/json"
queue
echo "== online-node agent-ssh-1"
$JCLI online-node agent-ssh-1
$JCLI wait-node-online agent-ssh-1
for _ in $(seq 1 30); do [ "$(curl -fsS "$URL/queue/api/json" | jq '.items | length')" = 0 ] && break; sleep 1; done
echo "== file après remise en ligne"; queue; echo "  (vide)"
N=$(curl -fsS "$URL/job/10-ping/lastBuild/buildNumber")
$JCLI console 10-ping "$N" -f >/dev/null || true
echo "== build 10-ping #$N : $(curl -fsS "$URL/job/10-ping/$N/api/json" | jq -r .result)"
$JCLI console 10-ping "$N" | sed -E 's/\x1b\[8mha:[^\x1b]*\x1b\[0m//g' | grep -E 'Waiting|Running on|Exécuté sur|Finished'
