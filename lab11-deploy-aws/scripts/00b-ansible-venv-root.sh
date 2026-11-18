#!/usr/bin/env bash
# Lab 11 - Ansible pour Jenkins : environnement isolé /opt/ansible (ansible-core 2.17).
# L'Ansible d'Ubuntu 22.04 (apt, 2.10) ne sait pas piloter Python 3.12 (Ubuntu 24.04) :
#   "No module named 'ansible.module_utils.six.moves'". Le PATH des builds est complété par JCasC (PATH+ANSIBLE).
#     sudo bash scripts/00b-ansible-venv-root.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "À lancer avec sudo" >&2; exit 1; }
VERSION=2.17.14
python3 -m venv --help >/dev/null 2>&1 || apt-get install -y -qq python3-venv >/dev/null
[ -x /opt/ansible/bin/ansible ] || python3 -m venv /opt/ansible
/opt/ansible/bin/pip install -q --disable-pip-version-check "ansible-core==$VERSION"
echo "OK  $(/opt/ansible/bin/ansible --version | head -1) dans /opt/ansible"
echo "    jenkins : $(sudo -u jenkins /opt/ansible/bin/ansible --version | head -1)"
echo "    (Ansible système conservé : $(/usr/bin/ansible --version | head -1))"
