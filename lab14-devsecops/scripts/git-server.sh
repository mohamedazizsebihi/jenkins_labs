#!/usr/bin/env bash
# Lab 14 - serveur Git LOCAL (git daemon, 127.0.0.1:9418) pour les branches d'échec des tâches 8 et 9.
# Rien n'est publié sur GitHub (en particulier la fausse clé AWS de la tâche 9).
#   bash scripts/git-server.sh start | stop
set -euo pipefail
cd "$(dirname "$0")/.."
BASE=$PWD/.git-server; PID=$BASE/daemon.pid
case "${1:-}" in
  start)
    mkdir -p "$BASE"
    [ -d "$BASE/jenkins-demo-app.git" ] || git clone -q --bare ../jenkins-demo-app "$BASE/jenkins-demo-app.git"
    git -C "$BASE/jenkins-demo-app.git" fetch -q ../../../jenkins-demo-app main:main
    if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then echo "git daemon déjà actif"; exit 0; fi
    setsid git daemon --reuseaddr --listen=127.0.0.1 --port=9418 --base-path="$BASE" --export-all \
        --pid-file="$PID" --detach "$BASE"
    sleep 1; echo "git daemon actif : git://127.0.0.1/jenkins-demo-app.git (pid $(cat "$PID"))" ;;
  stop)
    [ -f "$PID" ] && kill "$(cat "$PID")" 2>/dev/null && echo "git daemon arrêté" || echo "git daemon non actif"
    rm -f "$PID" ;;
  *) echo "usage : $0 start|stop" >&2; exit 1 ;;
esac
