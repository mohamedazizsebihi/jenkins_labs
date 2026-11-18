#!/usr/bin/env bash
# Lab 09 - tâche 7 : tire l'image PUBLIÉE depuis le registre, la lance et vérifie que /
# renvoie le n° du build Jenkins. Identifiants lus dans /etc/jenkins/secrets.env -> sudo.
#     sudo bash scripts/07-run-published.sh [n° de build]
set -euo pipefail
REGISTRY=localhost:5050
U=$(sed -n 's/^REGISTRY_USER=//p' /etc/jenkins/secrets.env)
T=$(sed -n 's/^REGISTRY_TOKEN=//p' /etc/jenkins/secrets.env)
BUILD=${1:-$(curl -fsS http://localhost:8080/job/09-docker/lastSuccessfulBuild/buildNumber)}
IMG="$REGISTRY/$U/jenkins-demo-app:$BUILD"
NAME=verif-lab09
export DOCKER_CONFIG="$(mktemp -d)"
trap 'docker rm -f "$NAME" >/dev/null 2>&1; docker rmi "$IMG" >/dev/null 2>&1; docker logout "$REGISTRY" >/dev/null; rm -rf "$DOCKER_CONFIG"' EXIT

printf '%s' "$T" | docker login "$REGISTRY" -u "$U" --password-stdin
docker pull -q "$IMG"
docker run -d --name "$NAME" -p 127.0.0.1::5000 "$IMG" >/dev/null
PORT=$(docker port "$NAME" 5000/tcp | head -1 | awk -F: '{print $NF}')
for _ in $(seq 1 30); do curl -fsS -o /dev/null "http://127.0.0.1:$PORT/health" 2>/dev/null && break; sleep 1; done
echo "GET http://127.0.0.1:$PORT/"
BODY=$(curl -fsS "http://127.0.0.1:$PORT/"); echo "$BODY" | jq .
V=$(echo "$BODY" | jq -r .version)
[ "$V" = "$BUILD" ] && echo "VALIDÉ : version $V = build Jenkins #$BUILD" || { echo "ÉCHEC : $V != $BUILD"; exit 1; }
