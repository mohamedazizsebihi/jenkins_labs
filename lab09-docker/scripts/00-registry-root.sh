#!/usr/bin/env bash
# Lab 09 - tâche 2 (côté serveur), variante SANS compte Docker Hub : registre local authentifié.
#     sudo bash scripts/00-registry-root.sh
# 1. génère un jeton aléatoire (jamais affiché) pour l'utilisateur du registre
# 2. démarre registry:2 sur 127.0.0.1:5050 avec authentification htpasswd
# 3. ajoute REGISTRY_USER / REGISTRY_TOKEN à /etc/jenkins/secrets.env
# 4. déploie la config JCasC versionnée (registry-creds) et redémarre Jenkins
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "À lancer avec sudo" >&2; exit 1; }
CASC_SRC="$(cd "$(dirname "$0")/../../jenkins-as-code/casc" && pwd)"
ENV_FILE=/etc/jenkins/secrets.env
REG_USER=jenkins-ci

# Jeton : on garde l'existant (idempotent), sinon on en génère un
REG_TOKEN=$(sed -n 's/^REGISTRY_TOKEN=//p' "$ENV_FILE")
[ -n "$REG_TOKEN" ] || REG_TOKEN=$(openssl rand -hex 24)

set_kv() { sed -i "/^$2=/d" "$1"; printf '%s=%s\n' "$2" "$3" >> "$1"; }
set_kv "$ENV_FILE" REGISTRY_USER  "$REG_USER"
set_kv "$ENV_FILE" REGISTRY_TOKEN "$REG_TOKEN"
echo "OK  $ENV_FILE : $(cut -d= -f1 "$ENV_FILE" | tr '\n' ' ')"

# htpasswd écrit dans un volume Docker (le jeton passe par stdin, jamais en argument)
docker volume create lab09-registry-auth >/dev/null
printf '%s\n' "$REG_TOKEN" | docker run -i --rm -v lab09-registry-auth:/auth httpd:2.4-alpine \
    htpasswd -iBc /auth/htpasswd "$REG_USER" 2>&1 | sed 's/^/    /'

docker rm -f lab09-registry >/dev/null 2>&1 || true
docker run -d --name lab09-registry --restart unless-stopped \
    -p 127.0.0.1:5050:5000 \
    -v lab09-registry-data:/var/lib/registry \
    -v lab09-registry-auth:/auth:ro \
    -e REGISTRY_AUTH=htpasswd \
    -e REGISTRY_AUTH_HTPASSWD_REALM=lab09 \
    -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
    registry:2 >/dev/null
for _ in $(seq 1 20); do
    code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:5050/v2/) && [ "$code" = 401 ] && break
    sleep 1
done
echo "OK  registre lab09-registry : GET /v2/ sans identifiants -> HTTP $code (authentification exigée)"

install -m 640 -o root -g jenkins "$CASC_SRC"/*.yaml /etc/jenkins/casc.d/
echo "OK  /etc/jenkins/casc.d <- $CASC_SRC"

systemctl restart jenkins          # nouvelles variables -> redémarrage complet
for _ in $(seq 1 90); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/login)" = 200 ] && break
    sleep 2
done
echo "jenkins : $(systemctl is-active jenkins)"
