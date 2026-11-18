#!/usr/bin/env bash
# Lab 10 - tâches 9 et 10 : valide (declarative-linter) puis crée/met à jour les jobs du lab
set -euo pipefail
cd "$(dirname "$0")/.."
JCLI=./scripts/jcli

job_xml() { # $1 = Jenkinsfile
    cat <<XML
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition>
  <description>Lab 10 - généré depuis $1</description>
  <keepDependencies>false</keepDependencies>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition">
    <script>
XML
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$1"
    cat <<'XML'
</script>
    <sandbox>true</sandbox>
  </definition>
  <disabled>false</disabled>
</flow-definition>
XML
}

deploy() { # $1 = job, $2 = Jenkinsfile
    printf '%-16s jlint : %s\n' "$1" "$($JCLI declarative-linter < "$2")"
    if $JCLI get-job "$1" >/dev/null 2>&1; then
        job_xml "$2" | $JCLI update-job "$1"; echo "                 job mis à jour"
    else
        job_xml "$2" | $JCLI create-job "$1"; echo "                 job créé"
    fi
}

deploy 10-distribue  ci/lab10.Jenkinsfile
deploy 10-sequentiel ci/lab10-sequentiel.Jenkinsfile
deploy 10-ping       ci/lab10-ping.Jenkinsfile
deploy 10-any        ci/lab10-any.Jenkinsfile
