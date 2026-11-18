#!/usr/bin/env bash
# Lab 09 - tâche 6 : tags publiés, lus par l'API Docker Hub (sans navigateur)
#   bash scripts/06-dockerhub-tags.sh <utilisateur_dockerhub>
set -euo pipefail
U=${1:?utilisateur Docker Hub}
REPO="$U/jenkins-demo-app"
echo "GET https://hub.docker.com/v2/repositories/$REPO/tags/"
curl -fsS "https://hub.docker.com/v2/repositories/$REPO/tags/?page_size=100&ordering=last_updated" \
  | jq -r '["TAG","DIGEST","MIS À JOUR"], (.results[] | [.name, (.digest // "-")[0:19], .last_updated[0:19]]) | @tsv' \
  | column -t
