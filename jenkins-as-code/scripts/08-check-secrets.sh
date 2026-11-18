#!/usr/bin/env bash
# Lab 07 - tâche 8 : prouve qu'aucun secret n'apparaît en clair (consoles Jenkins + dépôt Git).
# Les valeurs à rechercher sont saisies au clavier (ou passées sur stdin, une par ligne).
set -euo pipefail
cd "$(dirname "$0")/.."
JCLI=./scripts/jcli
JOB=07-params-credentials
URL="${JENKINS_URL:-http://localhost:8080/}"; URL="${URL%/}"

patterns=$(mktemp); trap 'rm -f "$patterns"' EXIT
for name in DEMO_API_TOKEN HTTPBIN_PASSWORD DB_PASSWORD; do
    read -rsp "Valeur de $name à rechercher : " v; echo
    [ -n "$v" ] || { echo "valeur vide : abandon (grep trouverait tout)" >&2; exit 1; }
    printf '%s\n' "$v" >> "$patterns"
done

fail=0
last=$(curl -fsS "$URL/job/$JOB/lastBuild/buildNumber")
echo "== Consoles du job $JOB (#1 à #$last)"
for n in $(seq 1 "$last"); do
    out=$($JCLI console "$JOB" "$n" 2>/dev/null) || continue
    clair=$(grep -cFf "$patterns" <<<"$out" || true)
    masque=$(grep -cF '****' <<<"$out" || true)
    printf '  build #%-3s secrets en clair : %s   lignes masquées (****) : %s\n' "$n" "$clair" "$masque"
    [ "$clair" -eq 0 ] || fail=1
done

echo "== Dépôt Git"
if git grep -nFf "$patterns" -- . ; then fail=1; else echo "  git grep (fichiers) : rien"; fi
hist=$(git log --all -p 2>/dev/null | grep -cFf "$patterns" || true)
echo "  historique git : $hist occurrence(s)"; [ "$hist" -eq 0 ] || fail=1

[ "$fail" -eq 0 ] && echo "VALIDÉ : aucun secret en clair" || { echo "ÉCHEC : secret trouvé"; exit 1; }
