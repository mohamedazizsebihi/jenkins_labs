#!/usr/bin/env bash
# Lab 10 - tâche 6 : tous les nœuds par l'API (nom, labels, exécuteurs, état)
set -euo pipefail
URL="${JENKINS_URL:-http://localhost:8080/}"; URL="${URL%/}"
curl -fsSg "$URL/computer/api/json?tree=computer[displayName,numExecutors,offline,temporarilyOffline,offlineCauseReason,idle,assignedLabels[name]]" \
  | jq -r '["NŒUD","LABELS","EXÉC.","ÉTAT","MOTIF"],
           (.computer[] | [.displayName,
                           ([.assignedLabels[].name] | join(" ")),
                           (.numExecutors|tostring),
                           (if .offline then "hors ligne" else (if .idle then "en ligne (libre)" else "en ligne (occupé)" end) end),
                           (.offlineCauseReason // "")]) | @tsv' \
  | column -t -s $'\t'
