#!/usr/bin/env bash
# Lab 14 - détail des vulnérabilités et security hotspots relevés par SonarQube (API)
. "$(dirname "$0")/lib.sh"
echo "== GET /api/issues/search?componentKeys=jenkins-demo-app&types=VULNERABILITY"
sget "/api/issues/search?componentKeys=jenkins-demo-app&types=VULNERABILITY&ps=20" \
  | jq -r '.issues[] | "   [\(.severity // .impacts[0].severity)] \(.component | sub("jenkins-demo-app:";"")):\(.line // "-") \(.rule) - \(.message)"'
echo "== GET /api/hotspots/search?project=jenkins-demo-app"
sget "/api/hotspots/search?project=jenkins-demo-app&ps=20" \
  | jq -r '.hotspots[]? | "   [\(.vulnerabilityProbability)] \(.component | sub("jenkins-demo-app:";"")):\(.line // "-") \(.ruleKey) - \(.message)"'
