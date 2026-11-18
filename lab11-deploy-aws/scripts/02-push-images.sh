#!/usr/bin/env bash
# Lab 11 - construit l'image de demo-app (Lab 09) en 2 versions et la pousse sur ECR : 1.0.0, 1.1.0 (= latest)
set -euo pipefail
cd "$(dirname "$0")/.."
. ./.aws-state.env; export AWS_PROFILE AWS_REGION AWS_PAGER=""
IMG="$ECR_REGISTRY/$ECR_REPO"
export DOCKER_CONFIG="$(mktemp -d)"     # config Docker jetable : le jeton ECR n'est conservé nulle part
trap 'docker logout "$ECR_REGISTRY" >/dev/null 2>&1; rm -rf "$DOCKER_CONFIG"' EXIT
aws ecr get-login-password | docker login --username AWS --password-stdin "$ECR_REGISTRY"
for v in 1.0.0 1.1.0; do
  docker build -q --build-arg APP_VERSION=$v -t "$IMG:$v" ../jenkins-demo-app >/dev/null
  echo "construite : $IMG:$v"
done
docker tag "$IMG:1.1.0" "$IMG:latest"
for t in 1.0.0 1.1.0 latest; do docker push -q "$IMG:$t"; done
docker rmi "$IMG:1.0.0" "$IMG:1.1.0" "$IMG:latest" >/dev/null
echo
aws ecr describe-images --repository-name "$ECR_REPO" \
  --query 'sort_by(imageDetails,&imagePushedAt)[].{Tags:join(`,`,imageTags||[`-`]),Digest:imageDigest,Taille_octets:to_string(imageSizeInBytes)}' --output table
