#!/usr/bin/env bash
# Lab 07 - tâche 5 : cycle de vie d'un credential en CLI (create / list / delete)
set -euo pipefail
cd "$(dirname "$0")/.."
JCLI=./scripts/jcli
STORE=system::system::jenkins   # store "System" de Jenkins
DOMAIN=_                        # "_" = domaine global

export CRED_ID=demo-api-token-cli
# Secret généré à la volée : il n'existe que dans la mémoire de ce script
CRED_SECRET="$(openssl rand -hex 16)"; export CRED_SECRET

echo "== create-credentials-by-xml $CRED_ID"
envsubst '${CRED_ID} ${CRED_SECRET}' < credentials/demo-api-token-cli.xml.tpl \
    | $JCLI create-credentials-by-xml "$STORE" "$DOMAIN"

echo "== list-credentials"
$JCLI list-credentials "$STORE"

echo "== get-credentials-as-xml (Jenkins masque le secret)"
$JCLI get-credentials-as-xml "$STORE" "$DOMAIN" "$CRED_ID"; echo

echo "== delete-credentials $CRED_ID"
$JCLI delete-credentials "$STORE" "$DOMAIN" "$CRED_ID"

echo "== list-credentials (après suppression)"
$JCLI list-credentials "$STORE"
