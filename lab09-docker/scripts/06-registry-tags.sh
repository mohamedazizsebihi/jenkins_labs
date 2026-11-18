#!/usr/bin/env bash
# Lab 09 - tâche 6 : tags publiés, lus par l'API du registre (Registry HTTP API v2), sans navigateur.
# Lit les identifiants dans /etc/jenkins/secrets.env -> sudo.
#     sudo bash scripts/06-registry-tags.sh
# (Docker Hub : curl https://hub.docker.com/v2/repositories/<user>/jenkins-demo-app/tags/)
set -euo pipefail
REG=http://127.0.0.1:5050
U=$(sed -n 's/^REGISTRY_USER=//p' /etc/jenkins/secrets.env)
T=$(sed -n 's/^REGISTRY_TOKEN=//p' /etc/jenkins/secrets.env)
REPO="$U/jenkins-demo-app"
# identifiants passés à curl par stdin (-K -) : invisibles dans "ps"
api() { printf 'user = "%s:%s"\n' "$U" "$T" | curl -K - -fsS "$@"; }

echo "GET $REG/v2/_catalog"
api "$REG/v2/_catalog" | jq -c .
echo "GET $REG/v2/$REPO/tags/list"
api "$REG/v2/$REPO/tags/list" | jq -c .
echo
ACCEPT='application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'
printf '%-22s %s\n' TAG "DIGEST (HEAD /v2/$REPO/manifests/<tag>)"
for tag in $(api "$REG/v2/$REPO/tags/list" | jq -r '.tags[]' | sort -V); do
    d=$(api -I -H "Accept: $ACCEPT" "$REG/v2/$REPO/manifests/$tag" | tr -d '\r' | sed -n 's/^[Dd]ocker-[Cc]ontent-[Dd]igest: //p')
    printf '%-22s %s\n' "$tag" "$d"
done
