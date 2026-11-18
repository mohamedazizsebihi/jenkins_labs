# Fonctions communes Lab 11 (sourcé par les scripts de la partie C)
set -euo pipefail
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$HOME/.jenkins-lab.env" ] && . "$HOME/.jenkins-lab.env"
[ -f "$LAB_DIR/.aws-state.env" ] && . "$LAB_DIR/.aws-state.env"
URL="${JENKINS_URL:-http://localhost:8080/}"; URL="${URL%/}"
JOB=11-deploy-aws
JCLI="$LAB_DIR/scripts/jcli"
# curl authentifié ; identifiants passés par stdin (-K -) : invisibles dans "ps"
jget()  { printf 'user = "%s:%s"\n' "$JENKINS_USER_ID" "$JENKINS_API_TOKEN" | curl -K - -fsSg "$URL$1"; }
jpost() { # $1 user, $2 jeton, $3 chemin -> code HTTP
  printf 'user = "%s:%s"\n' "$1" "$2" | curl -K - -s -o /dev/null -w '%{http_code}' -X POST "$URL$3"; }
last_build() { jget "/job/$JOB/lastBuild/buildNumber" 2>/dev/null || echo 0; }
start_build() { # paramètres -p ... -> lance SANS attendre (pas de -s) et renvoie le n° du build
  local before n; before=$(last_build)
  "$JCLI" build "$JOB" "$@" >/dev/null
  for _ in $(seq 1 60); do n=$(last_build); [ "$n" != "$before" ] && { echo "$n"; return 0; }; sleep 1; done
  return 1; }
wait_input() { # $1 build -> attend puis affiche les inputs en attente (wfapi)
  local r
  for _ in $(seq 1 150); do
    r=$(jget "/job/$JOB/$1/wfapi/pendingInputActions" 2>/dev/null || echo '[]')
    [ "$(echo "$r" | jq length)" -gt 0 ] && { echo "$r"; return 0; }
    sleep 2
  done; return 1; }
result() { jget "/job/$JOB/$1/api/json?tree=result,building" | jq -r 'if .building then "EN COURS" else .result end'; }
wait_end() { for _ in $(seq 1 400); do [ "$(result "$1")" != "EN COURS" ] && break; sleep 3; done; result "$1"; }
console_grep() { "$JCLI" console "$JOB" "$1" | sed -E 's/\x1b\[8mha:[^\x1b]*\x1b\[0m//g; s/\x1b\[[0-9;]*m//g; s/^\[[0-9TZ:.-]+\] //' | grep -E "$2"; }
served() { curl -fsS --max-time 5 "http://$EC2_HOST/" | jq -c .; }
