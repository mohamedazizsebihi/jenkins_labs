#!/usr/bin/env bash
# Lab 10 - tâche 9 : chaque stage, son état, sa durée et le nœud d'exécution, par l'API wfapi.
# Le champ execNode de wfapi reste vide ici : le nœud est lu dans les steps du stage
# (/execution/node/<id>/wfapi/describe -> step "Print Message" = "Nœud : <nom>").
#     bash scripts/09-wfapi.sh [job] [n° de build]
set -euo pipefail
URL="${JENKINS_URL:-http://localhost:8080/}"; URL="${URL%/}"
JOB=${1:-10-distribue}
N=${2:-$(curl -fsS "$URL/job/$JOB/lastBuild/buildNumber")}
B="$URL/job/$JOB/$N"
echo "GET $B/wfapi/describe  (+ /execution/node/<id>/wfapi/describe par stage)"
D=$(curl -fsS "$B/wfapi/describe")
echo "$D" | jq -r '"build #\(.id) : \(.status) en \(.durationMillis/1000 | floor) s"'
echo
{
  printf 'STAGE\tÉTAT\tDURÉE\tNŒUD (lu dans les steps)\n'
  echo "$D" | jq -r '.stages[] | [.id, .name, .status, (.durationMillis/100 | floor / 10 | tostring) + " s"] | @tsv' |
  while IFS=$'\t' read -r id name status dur; do
      node=$(curl -fsS "$B/execution/node/$id/wfapi/describe" |
             jq -r '[.stageFlowNodes[]? | select(.name=="Print Message") | .parameterDescription // ""
                     | select(startswith("Nœud :")) | sub("^Nœud : "; "")][0] // "-"')
      printf '%s\t%s\t%s\t%s\n' "$name" "$status" "$dur" "$node"
  done
} | column -t -s $'\t'
