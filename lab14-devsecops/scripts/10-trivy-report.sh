#!/usr/bin/env bash
# Lab 14 - tâche 10 : rapport trivy-image.html du dernier build réussi, téléchargé par l'API, CRITICAL comptées
. "$(dirname "$0")/lib.sh"
N=$(jget "/job/$JOB/lastSuccessfulBuild/buildNumber")
OUT="$LAB_DIR/rapport/trivy-image-build$N.html"
echo "== artefacts du build #$N : GET /job/$JOB/$N/api/json?tree=artifacts[relativePath]"
jget "/job/$JOB/$N/api/json?tree=artifacts[relativePath]" | jq -r '.artifacts[].relativePath' | sed 's/^/   /'
echo "== GET /job/$JOB/$N/artifact/reports/trivy-image.html"
jget "/job/$JOB/$N/artifact/reports/trivy-image.html" > "$OUT"
echo "   $(wc -c < "$OUT") octets -> rapport/$(basename "$OUT")"
echo "== vulnérabilités CRITICAL dans le rapport HTML : $(grep -c 'class="severity">CRITICAL<' "$OUT" || true)"
echo "   répartition dans le HTML : $(for s in CRITICAL HIGH MEDIUM LOW UNKNOWN; do printf '%s=%s ' $s "$(grep -c "class=\"severity\">$s<" "$OUT" || true)"; done)"
echo "== contrôle croisé avec le JSON (artifact/reports/trivy-image.json)"
jget "/job/$JOB/$N/artifact/reports/trivy-image.json" | jq -r '
  [.Results[]?.Vulnerabilities[]?] as $v |
  "   total=\($v|length)  CRITICAL=\([$v[]|select(.Severity=="CRITICAL")]|length)  HIGH=\([$v[]|select(.Severity=="HIGH")]|length)  dont corrigeables=\([$v[]|select(.FixedVersion!=null and .FixedVersion!="")]|length)"'
