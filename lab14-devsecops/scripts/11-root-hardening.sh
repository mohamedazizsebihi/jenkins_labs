#!/usr/bin/env bash
# Lab 14 - tâche 11 (root) : déploiement de casc/90-durcissement.yaml et rechargement à chaud
#     sudo bash scripts/11-root-hardening.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "À lancer avec sudo" >&2; exit 1; }
LAB="$(cd "$(dirname "$0")/.." && pwd)"; OWNER=$(stat -c %U "$LAB")
install -m 640 -o root -g jenkins "$LAB/../jenkins-as-code/casc/"*.yaml /etc/jenkins/casc.d/
echo "OK  /etc/jenkins/casc.d : $(ls /etc/jenkins/casc.d | tr '\n' ' ')"
sudo -u "$OWNER" "$LAB/scripts/jcli" reload-jcasc-configuration && echo "OK  reload-jcasc-configuration"
