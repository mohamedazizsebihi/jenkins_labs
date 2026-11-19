#!/usr/bin/env bash
# Lab 14 - tâches 2-3 : configuration de SonarQube UNIQUEMENT par son API REST. Idempotent.
#   mot de passe admin, projet, Quality Gate « Isoset » (couverture >= 80 %), webhook signé vers Jenkins
#   (adresses privées autorisées : sonar.validateWebhooks=false),
#   utilisateur technique jenkins-ci + jeton d'analyse. Secrets -> ~/.sonar-lab.env (0600, hors Git)
set -euo pipefail
SONAR=${SONAR_URL:-http://localhost:9000}
STATE=$HOME/.sonar-lab.env
PROJECT=jenkins-demo-app; GATE=Isoset; CI_USER=jenkins-ci; TOKEN_NAME=jenkins
WEBHOOK_URL=${WEBHOOK_URL:-http://jenkins-relay:8080/sonarqube-webhook/}
umask 077
[ -f "$STATE" ] && . "$STATE"
save() { cat > "$STATE" <<EOS
# SonarQube du Lab 14 (généré par sonar-setup.sh) - ne jamais versionner
SONAR_URL=$SONAR
SONAR_ADMIN_PASSWORD=${SONAR_ADMIN_PASSWORD:-}
SONAR_CI_PASSWORD=${SONAR_CI_PASSWORD:-}
SONAR_WEBHOOK_SECRET=${SONAR_WEBHOOK_SECRET:-}
SONAR_TOKEN=${SONAR_TOKEN:-}
EOS
}
pw()   { printf '%sAa1!' "$(openssl rand -base64 30 | tr -d '/+=' | cut -c1-20)"; }   # politique de complexité Sonar
auth() { printf 'user = "%s:%s"\n' "$1" "$2"; }                                       # identifiants via stdin (-K -)
api()  { local m=$1 p=$2; shift 2; auth admin "$SONAR_ADMIN_PASSWORD" | curl -K - -fsS -X "$m" "$SONAR$p" "$@"; }
valid(){ auth "$1" "$2" | curl -K - -fsS "$SONAR/api/authentication/validate" | jq -r .valid; }
step() { printf '%-50s' "$1"; }

step "SonarQube"; curl -fsS "$SONAR/api/system/status" | jq -r '"\(.status) (version \(.version))"'

step "1. mot de passe admin"
if [ -n "${SONAR_ADMIN_PASSWORD:-}" ] && [ "$(valid admin "$SONAR_ADMIN_PASSWORD")" = true ]; then
  echo "déjà changé (inchangé)"
elif [ "$(valid admin admin)" = true ]; then
  NEW=$(pw)
  auth admin admin | curl -K - -fsS -X POST "$SONAR/api/users/change_password" \
       --data-urlencode login=admin --data-urlencode previousPassword=admin --data-urlencode "password=$NEW"
  SONAR_ADMIN_PASSWORD=$NEW; save; echo "changé (mot de passe aléatoire -> $STATE)"
else
  echo "ÉCHEC : mot de passe admin inconnu" >&2; exit 1
fi

step "2. projet $PROJECT"
if [ "$(api GET "/api/projects/search?projects=$PROJECT" | jq '.paging.total')" -gt 0 ]; then echo "existe déjà"
else api POST /api/projects/create --data-urlencode "project=$PROJECT" --data-urlencode "name=$PROJECT" \
       --data-urlencode mainBranch=main >/dev/null; echo "créé"; fi

step "3. Quality Gate $GATE"
if api GET "/api/qualitygates/show?name=$GATE" >/dev/null 2>&1; then echo "existe déjà"
else api POST /api/qualitygates/create --data-urlencode "name=$GATE" >/dev/null; echo "créée"; fi
step "   condition couverture < 80 % = échec"
COND=$(api GET "/api/qualitygates/show?name=$GATE" | jq -c '[.conditions[]? | select(.metric=="coverage")][0] // empty')
if [ -z "$COND" ]; then
  api POST /api/qualitygates/create_condition --data-urlencode "gateName=$GATE" --data-urlencode metric=coverage \
      --data-urlencode op=LT --data-urlencode error=80 >/dev/null; echo "ajoutée"
elif [ "$(echo "$COND" | jq -r .error)" != 80 ]; then
  api POST /api/qualitygates/update_condition --data-urlencode "id=$(echo "$COND" | jq -r .id)" \
      --data-urlencode metric=coverage --data-urlencode op=LT --data-urlencode error=80 >/dev/null; echo "corrigée (80)"
else echo "déjà présente"; fi
step "   autres conditions retirées"
# SonarQube 26 ajoute d'office les conditions « Clean as you Code » (new_coverage, new_violations...) :
# la Quality Gate Isoset ne garde que la couverture globale, comme demandé.
EXTRA=$(api GET "/api/qualitygates/show?name=$GATE" | jq -r '.conditions[]? | select(.metric!="coverage") | .id')
if [ -z "$EXTRA" ]; then echo "aucune"
else for id in $EXTRA; do api POST /api/qualitygates/delete_condition --data-urlencode "id=$id"; done
     echo "$(echo "$EXTRA" | wc -l) retirée(s)"; fi
step "   associée au projet"
api POST /api/qualitygates/select --data-urlencode "gateName=$GATE" --data-urlencode "projectKey=$PROJECT"
api GET "/api/qualitygates/get_by_project?project=$PROJECT" | jq -r '.qualityGate.name'

step "4. webhooks vers le réseau privé autorisés"
# Protection SSRF de SonarQube : les webhooks vers des adresses privées (ici le réseau Docker 172.x du relais)
# sont refusés par défaut. Compromis assumé pour un Jenkins interne : SonarQube n'écoute que sur 127.0.0.1
# et le webhook est signé (HMAC). En production : exposer Jenkins derrière un reverse proxy à nom public.
if [ "$(api GET "/api/settings/values?keys=sonar.validateWebhooks" | jq -r '.settings[0].value')" = false ]; then
  echo "déjà fait (sonar.validateWebhooks=false)"
else
  api POST /api/settings/set --data-urlencode key=sonar.validateWebhooks --data-urlencode value=false
  echo "sonar.validateWebhooks=false"
fi

step "5. webhook -> Jenkins (signé)"
[ -n "${SONAR_WEBHOOK_SECRET:-}" ] || { SONAR_WEBHOOK_SECRET=$(openssl rand -hex 32); save; }
WH=$(api GET "/api/webhooks/list?project=$PROJECT" | jq -r '.webhooks[]? | select(.name=="jenkins") | .key')
if [ -z "$WH" ]; then
  api POST /api/webhooks/create --data-urlencode name=jenkins --data-urlencode "url=$WEBHOOK_URL" \
      --data-urlencode "project=$PROJECT" --data-urlencode "secret=$SONAR_WEBHOOK_SECRET" >/dev/null; echo "créé"
else
  api POST /api/webhooks/update --data-urlencode "webhook=$WH" --data-urlencode name=jenkins \
      --data-urlencode "url=$WEBHOOK_URL" --data-urlencode "secret=$SONAR_WEBHOOK_SECRET"; echo "existe déjà (url/secret réalignés)"
fi

step "6. utilisateur technique $CI_USER"
if [ "$(api GET "/api/users/search?q=$CI_USER" | jq --arg u "$CI_USER" '[.users[] | select(.login==$u)] | length')" -gt 0 ]; then
  echo "existe déjà"
else
  SONAR_CI_PASSWORD=$(pw); save
  api POST /api/users/create --data-urlencode "login=$CI_USER" --data-urlencode "name=Jenkins CI" \
      --data-urlencode "password=$SONAR_CI_PASSWORD" --data-urlencode local=true >/dev/null; echo "créé"
fi
step "   droits sur le projet (user, codeviewer, scan)"
for perm in user codeviewer scan; do
  api POST /api/permissions/add_user --data-urlencode "login=$CI_USER" --data-urlencode "projectKey=$PROJECT" \
      --data-urlencode "permission=$perm"
done; echo "OK"

step "7. jeton d'analyse"
if [ -n "${SONAR_TOKEN:-}" ] && [ "$(valid "$SONAR_TOKEN" "")" = true ]; then
  echo "déjà valide (conservé)"
else
  api POST /api/user_tokens/revoke --data-urlencode "login=$CI_USER" --data-urlencode "name=$TOKEN_NAME" >/dev/null 2>&1 || true
  SONAR_TOKEN=$(api POST /api/user_tokens/generate --data-urlencode "login=$CI_USER" \
                --data-urlencode "name=$TOKEN_NAME" --data-urlencode type=USER_TOKEN | jq -r .token)
  save; echo "généré pour $CI_USER (-> $STATE)"
fi

echo
echo "== Vérification par l'API"
api GET "/api/qualitygates/show?name=$GATE" | jq -c '{qualityGate: .name, conditions: [.conditions[] | {metric, op, error}]}'
api GET "/api/webhooks/list?project=$PROJECT" | jq -c '.webhooks[] | {name, url, secretConfigured: (.hasSecret // .secret != null)}'
api GET "/api/user_tokens/search?login=$CI_USER" | jq -c '{login, tokens: [.userTokens[] | {name, type}]}'
echo "état local : $STATE ($(stat -c %A "$STATE"))"
