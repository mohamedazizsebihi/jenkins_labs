#!/usr/bin/env bash
# Lab 09 - tâche 8 : aucun conteneur smoke-* / d'agent, ni image du build, ne doit rester sur l'hôte
#     bash scripts/08-check-leftovers.sh
set -euo pipefail
fail=0
check() { # check "titre" "résultat"
    echo "== $1"
    if [ -z "$2" ]; then echo "(aucun)"; else echo "$2"; fail=1; fi
}
check "docker ps -a --filter name=smoke-" \
      "$(docker ps -a --filter name=smoke- --format '{{.Names}}  {{.Status}}')"
check "docker ps -a --filter ancestor=python:3.12-slim   (conteneurs d'agent)" \
      "$(docker ps -a --filter ancestor=python:3.12-slim --format '{{.Names}}  {{.Status}}')"
check "docker images | grep jenkins-demo-app" \
      "$(docker images --format '{{.Repository}}:{{.Tag}}  {{.ID}}' | grep jenkins-demo-app || true)"
[ "$fail" -eq 0 ] && echo "VALIDÉ : hôte propre" || { echo "ÉCHEC : il reste des éléments"; exit 1; }
