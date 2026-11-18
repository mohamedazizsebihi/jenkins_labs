#!/usr/bin/env bash
# Lab 07 - Partie A, tâches 1, 2 et 4 (côté serveur). À lancer UNE fois :
#     sudo bash scripts/00-setup-root.sh
# Les secrets sont saisis au clavier : jamais écrits dans Git ni dans l'historique du shell.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "À lancer avec sudo" >&2; exit 1; }

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ETC=/etc/jenkins
ENV_FILE=$ETC/secrets.env
APP_ENV=$ETC/files/app.env
CASC_DIR=$ETC/casc.d
DROPIN=/etc/systemd/system/jenkins.service.d/casc.conf

ask() { # ask NOM_VARIABLE
    local v
    read -rsp "Valeur de $1 (voir l'énoncé) : " v; echo
    [ -n "$v" ] || { echo "Valeur vide pour $1" >&2; exit 1; }
    printf -v "$1" '%s' "$v"
}
set_kv() { # set_kv fichier CLE valeur  (remplace ou ajoute)
    sed -i "/^$2=/d" "$1"
    printf '%s=%s\n' "$2" "$3" >> "$1"
}

ask DEMO_API_TOKEN
ask HTTPBIN_PASSWORD
ask DB_PASSWORD

# Arborescence : jenkins peut lire, personne d'autre
install -d -m 750 -o root -g jenkins "$ETC" "$ETC/files" "$CASC_DIR"

# 1. secrets.env : lu par systemd (root) AVANT de démarrer Jenkins -> root only
touch "$ENV_FILE"; chown root:root "$ENV_FILE"; chmod 600 "$ENV_FILE"
set_kv "$ENV_FILE" DEMO_API_TOKEN "$DEMO_API_TOKEN"
set_kv "$ENV_FILE" HTTPBIN_PASSWORD "$HTTPBIN_PASSWORD"
echo "OK  $ENV_FILE"

# 2. app.env : lisible uniquement par jenkins (lu par JCasC via readFileBase64)
printf 'DB_PASSWORD=%s\n' "$DB_PASSWORD" > "$APP_ENV"
chown jenkins:jenkins "$APP_ENV"; chmod 600 "$APP_ENV"
echo "OK  $APP_ENV"

# 3. Déploiement de la configuration JCasC versionnée
install -m 640 -o root -g jenkins "$REPO_DIR"/casc/*.yaml "$CASC_DIR"/
echo "OK  $CASC_DIR : $(ls "$CASC_DIR" | tr '\n' ' ')"

# Raccordement systemd : variables + emplacement JCasC
install -d /etc/systemd/system/jenkins.service.d
cat > "$DROPIN" <<'UNIT'
[Service]
EnvironmentFile=/etc/jenkins/secrets.env
Environment="CASC_JENKINS_CONFIG=/etc/jenkins/casc.d"
UNIT
echo "OK  $DROPIN"

# 4. Redémarrage COMPLET (un restart depuis Jenkins ne relirait pas l'environnement)
systemctl daemon-reload
systemctl restart jenkins
for _ in $(seq 1 90); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/login)" = 200 ] && break
    sleep 2
done
systemctl is-active jenkins
echo "Jenkins redémarré. Vérifie : ./scripts/jcli list-credentials system::system::jenkins"
