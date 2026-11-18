#!/usr/bin/env bash
# Lab 10 - tâches 1, 2 et 6 (côté serveur). À lancer avec sudo :
#     sudo bash scripts/00-agent-root.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "À lancer avec sudo" >&2; exit 1; }
CASC_SRC="$(cd "$(dirname "$0")/../../jenkins-as-code/casc" && pwd)"
F=/etc/jenkins/files
KEY=$F/jenkins_agent
HOSTKEY=$F/agent-ssh-1.hostkey
NAME=agent-ssh-1

# 1. Clé ed25519 dédiée (générée une seule fois)
if [ ! -f "$KEY" ]; then
    ssh-keygen -q -t ed25519 -N '' -C "jenkins-agent-lab10" -f "$KEY"
fi
chown root:jenkins "$KEY" "$KEY.pub"; chmod 0640 "$KEY"; chmod 0644 "$KEY.pub"
echo "OK  clé : $(ls -l "$KEY" | awk '{print $1, $3":"$4, $NF}')"
echo "    empreinte : $(ssh-keygen -lf "$KEY.pub")"

# 2. Conteneur agent SSH (clé publique injectée, port publié sur la boucle locale)
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --restart unless-stopped \
    -p 127.0.0.1:2222:22 \
    -e "JENKINS_AGENT_SSH_PUBKEY=$(cat "$KEY.pub")" \
    jenkins/ssh-agent:latest-jdk21 >/dev/null
for _ in $(seq 1 30); do ssh-keyscan -p 2222 -t ed25519 localhost >/dev/null 2>&1 && break; sleep 1; done

# Clé d'hôte de l'agent -> vérification stricte côté Jenkins (manuallyProvided)
printf '%s' "$(ssh-keyscan -p 2222 -t ed25519 localhost 2>/dev/null | awk '{print $2" "$3}')" > "$HOSTKEY"
chown root:jenkins "$HOSTKEY"; chmod 0644 "$HOSTKEY"
echo "OK  clé d'hôte de l'agent : $(cut -c1-40 "$HOSTKEY")…"

# Test SSH en tant que jenkins, avec vérification stricte de la clé d'hôte
KH=$(mktemp); printf '[localhost]:2222 %s\n' "$(cat "$HOSTKEY")" > "$KH"; chmod 644 "$KH"
echo "--- test : ssh -i $KEY -p 2222 jenkins@localhost"
sudo -u jenkins ssh -i "$KEY" -p 2222 -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$KH" \
    -o BatchMode=yes jenkins@localhost \
    'echo "connecté à $(hostname) en tant que $(id -un)"; /opt/java/openjdk/bin/java -version 2>&1 | head -1'
rm -f "$KH"

# 3-5. Déploiement JCasC (00-base, 20-credentials, 40-agents) + rechargement à chaud
install -m 640 -o root -g jenkins "$CASC_SRC"/*.yaml /etc/jenkins/casc.d/
echo "OK  /etc/jenkins/casc.d : $(ls /etc/jenkins/casc.d | tr '\n' ' ')"
