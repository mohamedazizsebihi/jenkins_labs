#!/usr/bin/env bash
# Lab 11 - tâche 1 + sécurité Jenkins (côté serveur). À lancer avec sudo après 01-aws-provision.sh :
#     sudo bash scripts/00-root.sh
# - clé EC2 -> /etc/jenkins/files/ec2.pem (0640 root:jenkins), credential ec2-ssh-key par JCasC
# - Jenkins sécurisé par JCasC : utilisateurs admin / dev1 (mots de passe aléatoires), matrice de droits
# - ECR_REGISTRY fourni aux builds comme variable globale (pas dans Git)
# - jetons d'API générés pour admin et dev1 -> ~bihi/.jenkins-lab.env (0600)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "À lancer avec sudo" >&2; exit 1; }
LAB="$(cd "$(dirname "$0")/.." && pwd)"
CASC_SRC="$(cd "$LAB/../jenkins-as-code/casc" && pwd)"
OWNER=$(stat -c %U "$LAB"); OWNER_HOME=$(getent passwd "$OWNER" | cut -d: -f6)
. "$LAB/.aws-state.env"
ENV_FILE=/etc/jenkins/secrets.env
URL=http://localhost:8080

install -m 0640 -o root -g jenkins "$PEM" /etc/jenkins/files/ec2.pem
echo "OK  clé EC2 : $(ls -l /etc/jenkins/files/ec2.pem | awk '{print $1, $3":"$4, $NF}')"
install -d -m 700 -o jenkins -g jenkins /var/lib/jenkins/.ssh     # known_hosts de jenkins (accept-new)

getv() { sed -n "s/^$1=//p" "$ENV_FILE"; }
set_kv() { sed -i "/^$2=/d" "$1"; printf '%s=%s\n' "$2" "$3" >> "$1"; }
gen() { openssl rand -base64 24 | tr -d '/+=' | cut -c1-20; }
ADMIN_PW=$(getv JENKINS_ADMIN_PASSWORD); [ -n "$ADMIN_PW" ] || ADMIN_PW=$(gen)
DEV1_PW=$(getv JENKINS_DEV1_PASSWORD);  [ -n "$DEV1_PW" ]  || DEV1_PW=$(gen)
set_kv "$ENV_FILE" JENKINS_ADMIN_PASSWORD "$ADMIN_PW"
set_kv "$ENV_FILE" JENKINS_DEV1_PASSWORD  "$DEV1_PW"
set_kv "$ENV_FILE" ECR_REGISTRY           "$ECR_REGISTRY"
echo "OK  $ENV_FILE : $(cut -d= -f1 "$ENV_FILE" | tr '\n' ' ')"

install -m 640 -o root -g jenkins "$CASC_SRC"/*.yaml /etc/jenkins/casc.d/
echo "OK  /etc/jenkins/casc.d : $(ls /etc/jenkins/casc.d | tr '\n' ' ')"

systemctl restart jenkins
for _ in $(seq 1 90); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' $URL/login)" = 200 ] && break; sleep 2
done
echo "OK  jenkins : $(systemctl is-active jenkins) | accès anonyme à l'API : HTTP $(curl -s -o /dev/null -w '%{http_code}' $URL/api/json)"

# Jeton d'API : mot de passe + crumb (CSRF), identifiants passés à curl par stdin (-K -)
token() { # $1 user, $2 password
  local jar crumb; jar=$(mktemp)
  crumb=$(printf 'user = "%s:%s"\n' "$1" "$2" | curl -K - -fsS -c "$jar" "$URL/crumbIssuer/api/json" | jq -r '.crumbRequestField+":"+.crumb')
  printf 'user = "%s:%s"\n' "$1" "$2" | curl -K - -fsS -b "$jar" -H "$crumb" -X POST \
     "$URL/user/$1/descriptorByName/jenkins.security.ApiTokenProperty/generateNewToken" \
     --data "newTokenName=lab11-cli-$(date +%s)" | jq -r .data.tokenValue
  rm -f "$jar"
}
ADMIN_TOKEN=$(token admin "$ADMIN_PW")
DEV1_TOKEN=$(token dev1 "$DEV1_PW")
umask 077
cat > "$OWNER_HOME/.jenkins-lab.env" <<EOS
# Accès API/CLI Jenkins (généré par lab11 00-root.sh) - ne jamais versionner
export JENKINS_URL=$URL/
export JENKINS_USER_ID=admin
export JENKINS_API_TOKEN=$ADMIN_TOKEN
export DEV1_USER_ID=dev1
export DEV1_API_TOKEN=$DEV1_TOKEN
EOS
printf '%s\n' "$ADMIN_PW" > "$OWNER_HOME/.jenkins-admin-password"
chown "$OWNER:$OWNER" "$OWNER_HOME/.jenkins-lab.env" "$OWNER_HOME/.jenkins-admin-password"
echo "OK  jetons d'API admin et dev1 -> $OWNER_HOME/.jenkins-lab.env ($(stat -c %A "$OWNER_HOME/.jenkins-lab.env"))"
echo "OK  mot de passe admin (interface web) -> $OWNER_HOME/.jenkins-admin-password"
