#!/usr/bin/env bash
# Lab 14 - tâche 9 : fausse clé AWS dans config.env -> le stage Trivy FS échoue ; puis on retire le fichier.
# Clé générée aléatoirement (la clé d'exemple de la doc AWS est ignorée par Trivy) ; branche LOCALE uniquement.
. "$(dirname "$0")/lib.sh"
BR=lab14-secret
bash "$LAB_DIR/scripts/git-server.sh" start
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
git clone -q "$LAB_DIR/.git-server/jenkins-demo-app.git" "$W/app"
cd "$W/app"; git checkout -q -b "$BR"
AKID="AKIA$(head -c 64 /dev/urandom | base32 | tr -dc 'A-Z2-7' | head -c 16)"
SKEY="$(head -c 64 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 40)"
printf 'AWS_ACCESS_KEY_ID=%s\nAWS_SECRET_ACCESS_KEY=%s\n' "$AKID" "$SKEY" > config.env
git add config.env
git -c user.name=lab14 -c user.email=lab14@localhost commit -q -m "Lab 14 : config.env avec une (fausse) clé AWS"
git push -q origin "$BR"
echo "== config.env ajouté sur la branche locale $BR (clé factice ${AKID:0:4}****************)"
cd "$LAB_DIR"
N=$(run_build -p REPO_URL="$LOCAL_REPO" -p BRANCH="$BR")
echo "== build #$N avec la fausse clé"
stages "$N"
console_grep "$N" 'CRITICAL: AWS|Total: [0-9]|Trivy FS :|ERROR|^Finished' | sed 's/^/   /'
echo "== on retire le fichier (git rm) et on relance"
cd "$W/app"; git rm -q config.env
git -c user.name=lab14 -c user.email=lab14@localhost commit -q -m "Lab 14 : retrait de config.env"
git push -q origin "$BR"; cd "$LAB_DIR"
N=$(run_build -p REPO_URL="$LOCAL_REPO" -p BRANCH="$BR")
echo "== build #$N sans le fichier"
stages "$N"
console_grep "$N" 'Trivy FS :|^Finished' | sed 's/^/   /'
echo "   (le secret reste dans l'historique de la branche : une vraie fuite impose rotation de la clé + réécriture de l'historique)"
