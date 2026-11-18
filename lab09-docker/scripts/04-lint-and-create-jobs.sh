#!/usr/bin/env bash
# Lab 09 - tâche 4 : valide les Jenkinsfiles (declarative-linter) puis crée/met à jour les jobs
set -euo pipefail
cd "$(dirname "$0")/.."
JCLI=./scripts/jcli

job_xml() { # $1 = Jenkinsfile, $2 = description
    cat <<XML
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition>
  <description>$2</description>
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
    echo "== jlint $2"
    $JCLI declarative-linter < "$2"
    if $JCLI get-job "$1" >/dev/null 2>&1; then
        job_xml "$2" "Lab 09 - généré depuis $2" | $JCLI update-job "$1"; echo "== job $1 mis à jour"
    else
        job_xml "$2" "Lab 09 - généré depuis $2" | $JCLI create-job "$1"; echo "== job $1 créé"
    fi
}

deploy 09-docker        ci/lab09.Jenkinsfile
deploy 09-docker-plugin ci/lab09-plugin.Jenkinsfile
