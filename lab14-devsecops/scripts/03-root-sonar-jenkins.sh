#!/usr/bin/env bash
# Lab 14 - tâches 4-5 (root) : SONAR_TOKEN et SONAR_WEBHOOK_SECRET -> secrets.env, JCasC (20 + 60), redémarrage
#     sudo bash scripts/03-root-sonar-jenkins.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "À lancer avec sudo" >&2; exit 1; }
LAB="$(cd "$(dirname "$0")/.." && pwd)"; OWNER=$(stat -c %U "$LAB"); OWNER_HOME=$(getent passwd "$OWNER" | cut -d: -f6)
CASC_SRC="$(cd "$LAB/../jenkins-as-code/casc" && pwd)"
ENV_FILE=/etc/jenkins/secrets.env
. "$OWNER_HOME/.sonar-lab.env"
set_kv() { sed -i "/^$2=/d" "$1"; printf '%s=%s\n' "$2" "$3" >> "$1"; }
set_kv "$ENV_FILE" SONAR_TOKEN          "$SONAR_TOKEN"
set_kv "$ENV_FILE" SONAR_WEBHOOK_SECRET "$SONAR_WEBHOOK_SECRET"
echo "OK  $ENV_FILE : $(cut -d= -f1 "$ENV_FILE" | tr '\n' ' ')"
install -m 640 -o root -g jenkins "$CASC_SRC"/*.yaml /etc/jenkins/casc.d/
echo "OK  /etc/jenkins/casc.d : $(ls /etc/jenkins/casc.d | tr '\n' ' ')"
systemctl restart jenkins
for _ in $(seq 1 90); do [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/login)" = 200 ] && break; sleep 2; done
echo "OK  jenkins : $(systemctl is-active jenkins) | tunnel : $(systemctl is-active jenkins-sonar-tunnel)"
