#!/usr/bin/env bash
# Lab 14 - tâche 8 : fonction non testée -> la Quality Gate échoue, le pipeline s'arrête
. "$(dirname "$0")/lib.sh"
BR=lab14-qg-echec
bash "$LAB_DIR/scripts/git-server.sh" start
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
git clone -q "$LAB_DIR/.git-server/jenkins-demo-app.git" "$W/app"
cd "$W/app"; git checkout -q -b "$BR"
cat >> app.py <<'PY'


def rapport_inventaire(stock):
    """Synthèse d'un stock : volontairement NON testée (Lab 14, Quality Gate)."""
    total = 0
    alertes = []
    for article, quantite in stock.items():
        total += quantite
        if quantite < 5:
            alertes.append(article)
        elif quantite > 100:
            alertes.append(f"{article} (surstock)")
    moyenne = total / len(stock) if stock else 0
    return {"total": total, "moyenne": round(moyenne, 2), "alertes": sorted(alertes)}
PY
git -c user.name=lab14 -c user.email=lab14@localhost commit -q -am "Lab 14 : fonction non testée"
git push -q origin "$BR"
echo "== branche $BR poussée sur le serveur Git LOCAL ($LOCAL_REPO) : $(git log -1 --format='%h %s')"
cd "$LAB_DIR"
echo "== jcli build $JOB -s -p REPO_URL=$LOCAL_REPO -p BRANCH=$BR"
N=$(run_build -p REPO_URL="$LOCAL_REPO" -p BRANCH="$BR")
echo "== côté Jenkins : GET /job/$JOB/$N/wfapi/describe"
stages "$N"
console_grep "$N" 'TOTAL|Quality gate|QUALITY GATE|Pipeline aborted|ERROR|^Finished' | sed 's/^/   /'
echo "== côté SonarQube : GET /api/qualitygates/project_status"
qg
