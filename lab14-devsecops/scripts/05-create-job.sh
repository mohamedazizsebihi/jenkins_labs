#!/usr/bin/env bash
# Lab 14 - tâche 7 : lint, création du job 14-devsecops
. "$(dirname "$0")/lib.sh"
SRC="$LAB_DIR/ci/lab14.Jenkinsfile"
job_xml() {
  cat <<'XML'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition>
  <description>Lab 14 - généré depuis ci/lab14.Jenkinsfile</description>
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
