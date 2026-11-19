# Fonctions communes Lab 14 (sourcé)
set -euo pipefail
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$HOME/.jenkins-lab.env" ] && . "$HOME/.jenkins-lab.env"
[ -f "$HOME/.sonar-lab.env" ] && . "$HOME/.sonar-lab.env"
URL="${JENKINS_URL:-http://localhost:8080/}"; URL="${URL%/}"
SONAR="${SONAR_URL:-http://localhost:9000}"
JOB=14-devsecops
JCLI="$LAB_DIR/scripts/jcli"
LOCAL_REPO=git://127.0.0.1/jenkins-demo-app.git
jget() { printf 'user = "%s:%s"\n' "$JENKINS_USER_ID" "$JENKINS_API_TOKEN" | curl -K - -fsSg "$URL$1"; }
sget() { printf 'user = "%s:"\n' "$SONAR_TOKEN" | curl -K - -fsSg "$SONAR$1"; }      # jeton jenkins-ci
last_build() { jget "/job/$JOB/lastBuild/buildNumber" 2>/dev/null || echo 0; }
result() { jget "/job/$JOB/$1/api/json?tree=result,building" | jq -r 'if .building then "EN COURS" else .result end'; }
run_build() { # paramètres -p ... -> lance, attend, renvoie le n°
  "$JCLI" build "$JOB" -s "$@" >/dev/null 2>&1 || true; last_build; }
console_grep() { "$JCLI" console "$JOB" "$1" | sed -E 's/\x1b\[8mha:[^\x1b]*\x1b\[0m//g; s/\x1b\[[0-9;]*m//g; s/^\[[0-9TZ:.-]+\] //' | grep -E "$2"; }
stages() { # $1 build -> stages et états par wfapi
  jget "/job/$JOB/$1/wfapi/describe" | jq -r '"build #\(.id) : \(.status)", (.stages[] | "   \(.name | . + " " * (22 - length)) \(.status)  \(.durationMillis/1000|floor) s")'; }
qg() { sget "/api/qualitygates/project_status?projectKey=jenkins-demo-app" \
       | jq -r '.projectStatus | "Quality Gate : \(.status)", (.conditions[] | "   \(.metricKey) \(.comparator) \(.errorThreshold) -> valeur \(.actualValue) : \(.status)")'; }
