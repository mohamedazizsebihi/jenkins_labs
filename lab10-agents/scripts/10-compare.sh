#!/usr/bin/env bash
# Lab 10 - tâche 10 : durée du pipeline distribué vs séquentiel (API Jenkins)
set -euo pipefail
URL="${JENKINS_URL:-http://localhost:8080/}"; URL="${URL%/}"
row() { curl -fsS "$URL/job/$1/lastSuccessfulBuild/api/json?tree=number,duration,result" \
        | jq -r --arg j "$1" '[$j, "#\(.number)", .result, "\(.duration/1000 | floor) s"] | @tsv'; }
D=$(curl -fsS "$URL/job/10-distribue/lastSuccessfulBuild/api/json?tree=duration" | jq .duration)
S=$(curl -fsS "$URL/job/10-sequentiel/lastSuccessfulBuild/api/json?tree=duration" | jq .duration)
{ printf 'JOB\tBUILD\tRÉSULTAT\tDURÉE\n'; row 10-distribue; row 10-sequentiel; } | column -t -s $'\t'
awk -v d="$D" -v s="$S" 'BEGIN { printf "\nGain : %.0f s (%.1fx plus rapide en parallèle)\n", (s-d)/1000, s/d }'
