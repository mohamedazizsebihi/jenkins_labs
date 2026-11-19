#!/usr/bin/env bash
# Lab 14 - tâche 7 : build sur main, puis statut de la Quality Gate lu par l'API SonarQube
. "$(dirname "$0")/lib.sh"
echo "== jcli build $JOB -s   (main, dépôt GitHub)"
N=$(run_build "$@")
stages "$N"
echo "== console : couverture, Quality Gate, Trivy"
console_grep "$N" 'TOTAL|passed|ANALYSIS SUCCESSFUL|SonarQube task|Quality gate|Checking status|Total: [0-9]|Trivy FS :|Trivy image :|^Finished' | sed 's/^/   /'
echo "== API SonarQube : GET /api/qualitygates/project_status?projectKey=jenkins-demo-app"
qg
echo "== API SonarQube : GET /api/measures/component (couverture, bugs, vulnérabilités, code smells)"
sget "/api/measures/component?component=jenkins-demo-app&metricKeys=coverage,bugs,vulnerabilities,code_smells,ncloc" \
  | jq -r '.component.measures | sort_by(.metric)[] | "   \(.metric) = \(.value)"'
