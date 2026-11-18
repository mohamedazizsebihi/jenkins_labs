#!/usr/bin/env bash
# Lab 09 - tâche 5 : commandes docker générées par Jenkins (agent docker) relevées dans la console
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD=${1:-lastBuild}
./scripts/jcli console 09-docker "$BUILD" \
  | sed -E 's/\x1b\[8mha:[^\x1b]*\x1b\[0m//g; s/\x1b\[[0-9;]*m//g' \
  | grep -E '\$ docker |docker (run|exec|stop|rm|top|inspect)|Jenkins (does not seem|seems)' \
  | sed -E 's/^\[[0-9TZ:.-]+\] //'
