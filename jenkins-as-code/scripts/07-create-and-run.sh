#!/usr/bin/env bash
# Lab 07 - tâche 7 : crée (ou met à jour) le job depuis ci/lab07.Jenkinsfile, puis lance les builds
set -euo pipefail
cd "$(dirname "$0")/.."
JCLI=./scripts/jcli
JOB=07-params-credentials
SRC=ci/lab07.Jenkinsfile

job_xml() { # Jenkinsfile échappé pour XML dans un job Pipeline
    cat <<'XML'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition>
  <description>Lab 07 - généré depuis ci/lab07.Jenkinsfile (ne pas modifier dans l'UI)</description>
  <keepDependencies>false</keepDependencies>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition">
    <script>
XML
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$SRC"
    cat <<'XML'
</script>
    <sandbox>true</sandbox>
  </definition>
  <disabled>false</disabled>
</flow-definition>
XML
}

if $JCLI get-job "$JOB" >/dev/null 2>&1; then
    job_xml | $JCLI update-job "$JOB"; echo "Job $JOB mis à jour"
else
    job_xml | $JCLI create-job "$JOB"; echo "Job $JOB créé"
fi

run() {
    echo; echo "================ build $JOB $* ================"
    $JCLI build "$JOB" -s -v "$@" || echo ">>> build en échec (code $?)"
}

# 1er build sans paramètre : Jenkins enregistre la définition des paramètres
run
run -p TARGET_ENV=dev  -p RUN_TESTS=false
run -p TARGET_ENV=prod -p VERSION=2.0.0-SNAPSHOT
run -p TARGET_ENV=prod -p VERSION=2.0.0
