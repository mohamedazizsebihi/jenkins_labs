#!/usr/bin/env bash
# Lab 11 - tâche 5 : lint, création du job 11-deploy-aws, premier build (échec voulu : EC2_HOST vide)
. "$(dirname "$0")/lib.sh"
SRC="$LAB_DIR/ci/lab11.Jenkinsfile"
job_xml() {
  cat <<'XML'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition>
  <description>Lab 11 - généré depuis ci/lab11.Jenkinsfile</description>
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
echo "== jlint : $("$JCLI" declarative-linter < "$SRC")"
if "$JCLI" get-job "$JOB" >/dev/null 2>&1; then job_xml | "$JCLI" update-job "$JOB"; echo "== job $JOB mis à jour"
else job_xml | "$JCLI" create-job "$JOB"; echo "== job $JOB créé"; fi
echo "== 1er build sans paramètre (enregistre les paramètres ; doit échouer sur EC2_HOST vide)"
"$JCLI" build "$JOB" -s >/dev/null 2>&1 || true
N=$(last_build)
echo "   build #$N : $(result "$N")"
console_grep "$N" 'ERROR|obligatoire|Finished'
echo "== paramètres enregistrés"
jget "/job/$JOB/api/json?tree=property[parameterDefinitions[name,type,defaultParameterValue[value]]]" \
  | jq -r '.property[].parameterDefinitions[]? | "   \(.name) (\(.type | sub("ParameterDefinition";""))) défaut=\(.defaultParameterValue.value // "")"'
