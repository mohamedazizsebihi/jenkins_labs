#!/usr/bin/env bash
# Lab 14 - prérequis côté serveur (root) :
#   1. vm.max_map_count=524288 (SonarQube / Elasticsearch), persistant
#   2. clé dédiée au tunnel du webhook + service systemd « jenkins-sonar-tunnel » (utilisateur jenkins)
#     sudo bash scripts/00-root-prereq.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "À lancer avec sudo" >&2; exit 1; }
LAB="$(cd "$(dirname "$0")/.." && pwd)"; OWNER=$(stat -c %U "$LAB")
KEY=/etc/jenkins/files/sonar_tunnel
UNIT=/etc/systemd/system/jenkins-sonar-tunnel.service

echo "vm.max_map_count=524288" > /etc/sysctl.d/99-sonarqube.conf
sysctl -q -w vm.max_map_count=524288
echo "OK  vm.max_map_count = $(cat /proc/sys/vm/max_map_count) (persistant : /etc/sysctl.d/99-sonarqube.conf)"

[ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N '' -C "jenkins-sonar-tunnel" -f "$KEY"
chown root:jenkins "$KEY" "$KEY.pub"; chmod 0640 "$KEY"; chmod 0644 "$KEY.pub"
install -m 0644 -o "$OWNER" -g "$OWNER" "$KEY.pub" "$LAB/relay/authorized_keys"
echo "OK  clé du tunnel : $(ls -l "$KEY" | awk '{print $1, $3":"$4, $NF}')"

cat > "$UNIT" <<UNITEOF
[Unit]
Description=Lab 14 - tunnel SSH inverse : expose Jenkins au relais du webhook SonarQube
After=network-online.target jenkins.service

[Service]
User=jenkins
ExecStart=/usr/bin/ssh -N -i $KEY -p 2223 \\
  -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \\
  -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/var/lib/jenkins/.ssh/known_hosts_relay \\
  -R 0.0.0.0:8080:127.0.0.1:8080 tunnel@127.0.0.1
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
UNITEOF
systemctl daemon-reload
systemctl enable jenkins-sonar-tunnel >/dev/null 2>&1
echo "OK  service jenkins-sonar-tunnel installé (démarré après le relais)"
