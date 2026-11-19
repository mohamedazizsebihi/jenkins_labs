#!/usr/bin/env bash
# Lab 14 - tâche 1 : SonarQube + PostgreSQL + relais, attente de l'état UP
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(cat /proc/sys/vm/max_map_count)" -ge 524288 ] || { echo "vm.max_map_count trop bas : sudo bash scripts/00-root-prereq.sh" >&2; exit 1; }
[ -f .env ] || ( umask 077; printf 'SONAR_DB_PASSWORD=%s\n' "$(openssl rand -hex 24)" > .env )
docker compose -f docker-compose.sonar.yml up -d --build --quiet-pull 2>&1 | grep -vE '^\s*$' | tail -6
echo -n "attente de SonarQube "
for _ in $(seq 1 120); do
  s=$(curl -fsS http://localhost:9000/api/system/status 2>/dev/null | jq -r .status 2>/dev/null || true)
  [ "$s" = UP ] && break; echo -n "."; sleep 5
done; echo
curl -fsS http://localhost:9000/api/system/status | jq -c '{status, version}'
docker compose -f docker-compose.sonar.yml ps --format 'table {{.Name}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
