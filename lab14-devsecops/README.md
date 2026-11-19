# Lab 14 — DevSecOps : SonarQube, Trivy et durcissement, tout par API et par code

Règle du lab : zéro clic. SonarQube est configuré par son API REST, Jenkins par JCasC, et les vérifications se font par API (Jenkins, SonarQube) et par script.

```
            ┌──────────────── Docker (réseau lab14-sonar) ─────────────────┐
WSL         │  sonarqube:community (127.0.0.1:9000) ── PostgreSQL 17        │
Jenkins ────┼─► jenkins-relay (sshd, 127.0.0.1:2223)                        │
 (8080)     │       ▲ webhook signé : http://jenkins-relay:8080/sonarqube-webhook/
            └───────┼───────────────────────────────────────────────────────┘
                    └── tunnel SSH inverse (service systemd jenkins-sonar-tunnel)
```

## Arborescence

| Fichier | Rôle |
|---|---|
| `docker-compose.sonar.yml` | SonarQube Community + PostgreSQL + relais du webhook |
| `relay/Dockerfile`, `relay/sshd_config` | Relais SSH minimal : uniquement un tunnel inverse `0.0.0.0:8080`, pas de shell |
| `scripts/00-root-prereq.sh` | `vm.max_map_count=524288` (persistant), clé et service systemd du tunnel (root) |
| `scripts/01-sonar-up.sh` | Tâche 1 : démarrage et attente de l'état `UP` |
| `scripts/sonar-setup.sh` | Tâches 2-3 : configuration SonarQube **par API**, idempotente |
| `scripts/03-root-sonar-jenkins.sh` | Tâches 4-5 : `SONAR_TOKEN` et secret du webhook dans `secrets.env`, JCasC, redémarrage (root) |
| `ci/lab14.Jenkinsfile` | Tâche 6 : tests et couverture, SonarQube, Quality Gate bloquante, Trivy FS, build, Trivy image, rapports |
| `scripts/05-create-job.sh` | Tâche 7 : lint et création du job `14-devsecops` |
| `scripts/07-run-main.sh`, `07b-sonar-issues.sh` | Tâche 7 : build sur main, Quality Gate et mesures lues par l'API SonarQube |
| `scripts/08-qg-fail.sh` | Tâche 8 : fonction non testée, Quality Gate en échec |
| `scripts/09-trivy-secret.sh` | Tâche 9 : fausse clé AWS, Trivy FS en échec, puis retrait du fichier |
| `scripts/10-trivy-report.sh` | Tâche 10 : rapport HTML téléchargé par l'API, CRITICAL comptées |
| `scripts/11-root-hardening.sh` | Tâche 11 : déploiement de `casc/90-durcissement.yaml` |
| `scripts/audit-durcissement.groovy`, `12-audit.sh` | Tâche 12 : audit exécuté par `POST /scriptText` |
| `scripts/git-server.sh` | Serveur Git **local** (`git daemon`) pour les branches d'échec : rien n'est publié sur GitHub |
| `../jenkins-as-code/casc/20-credentials.yaml` | + `sonar-token`, `sonar-webhook-secret` |
| `../jenkins-as-code/casc/60-sonarqube.yaml` | Serveur `sonarqube` (webhook signé) et outil `sonar-scanner` 8.4.0.16527 installé automatiquement |
| `../jenkins-as-code/casc/90-durcissement.yaml` | Durcissement du contrôleur |
| `../jenkins-demo-app/sonar-project.properties` | Sources, tests, rapports de couverture et JUnit |

## Déroulé

```bash
sudo bash scripts/00-root-prereq.sh
bash scripts/01-sonar-up.sh && sudo systemctl start jenkins-sonar-tunnel
bash scripts/sonar-setup.sh && bash scripts/sonar-setup.sh      # le 2e passage ne change rien
sudo bash scripts/03-root-sonar-jenkins.sh
bash scripts/05-create-job.sh
bash scripts/07-run-main.sh
bash scripts/08-qg-fail.sh
bash scripts/09-trivy-secret.sh
bash scripts/10-trivy-report.sh
sudo bash scripts/11-root-hardening.sh
bash scripts/12-audit.sh
```

## Résultats

| Build | Source | Résultat | Détail |
|---|---|---|---|
| #1 | GitHub `main` | **SUCCESS** | couverture **94,4 %**, Quality Gate **OK** (webhook reçu), Trivy FS 0, Trivy image 0 CRITICAL / 48 HIGH |
| #2 | branche locale `lab14-qg-echec` | **FAILURE** | fonction non testée : couverture **62,1 %**, `Quality gate is 'ERROR'`, `Pipeline aborted due to quality gate failure` |
| #3 | branche locale `lab14-secret` | **FAILURE** | `config.env` : Trivy FS `CRITICAL: AWS (aws-access-key-id)` + `(aws-secret-access-key)` |
| #4 | même branche, fichier retiré | **SUCCESS** | Trivy FS : 0 problème |

- **SonarQube par API** : mot de passe admin changé (aléatoire), projet, Quality Gate **Isoset** (`coverage < 80` = échec) associée au projet, webhook **signé** vers Jenkins, utilisateur technique `jenkins-ci` (droits limités au projet) avec son jeton d'analyse. Le second passage du script ne modifie rien.
- **Rapport Trivy (build #4)** : 555 Ko téléchargés par `/job/14-devsecops/4/artifact/reports/trivy-image.html`, **0 CRITICAL** (HTML et JSON concordants : 232 vulnérabilités, dont 48 HIGH et 8 corrigeables).
- **Audit du durcissement** : 10 contrôles sur 11 OK. Le seul KO : 4 exécuteurs sur le contrôleur (voir plus bas).

## Choix techniques et pièges rencontrés

1. **Webhook SonarQube vers Jenkins impossible en direct.** Côté Windows, un Apache occupe `0.0.0.0:8080` : depuis un conteneur, `host.docker.internal:8080` arrive sur Apache (`Server: Apache`), et l'IP de WSL n'est pas joignable. Solution sans droits admin Windows : un **tunnel SSH inverse**. Jenkins se connecte (connexion sortante) à un relais dans le réseau Docker de SonarQube et y expose son port 8080. Le relais n'accepte que ce tunnel (`PermitListen 0.0.0.0:8080`, `PermitOpen none`, `ForceCommand /bin/false`, clé dédiée). C'est le schéma classique d'un Jenkins injoignable depuis l'extérieur (webhook d'un SaaS).
2. **Protection SSRF de SonarQube.** Les webhooks vers des adresses privées sont refusés (*loopback, site-local… not allowed for webhooks*). `sonar.validateWebhooks=false` est positionné **par API**. C'est un compromis assumé : SonarQube n'écoute que sur 127.0.0.1 et le webhook est signé (HMAC vérifié par Jenkins grâce à `webhookSecretId`). En production, on exposerait Jenkins derrière un reverse proxy à nom public.
3. **SonarQube 26 ajoute d'office 4 conditions « Clean as you Code »** (`new_coverage`, `new_violations`…) à toute Quality Gate créée. Le script les retire : Isoset ne contient que la couverture, comme demandé.
4. **Une Quality Gate basée uniquement sur la couverture laisse passer des vulnérabilités.** SonarQube relève **2 vulnérabilités** dans `app.py` : `[BLOCKER] python:S8392` (écoute sur toutes les interfaces) et `[CRITICAL] python:S4502` (protection CSRF désactivée). La gate reste verte. En pratique, on ajoute une condition `vulnerabilities > 0` ou une note de sécurité.
5. **Jeton d'analyse non administrateur.** Le jeton appartient à l'utilisateur `jenkins-ci` (droits `user`, `codeviewer`, `scan` sur le seul projet), jamais au compte admin. Les secrets restent dans `~/.sonar-lab.env` (0600), puis dans `/etc/jenkins/secrets.env`.
6. **La clé d'exemple de la documentation AWS (`AKIAIOSFODNN7EXAMPLE`) est ignorée par Trivy** (liste d'autorisation). La fausse clé est donc générée aléatoirement. Les branches d'échec vivent sur un **serveur Git local** (`git://127.0.0.1`) : aucune fausse clé ni code cassé n'est publié sur GitHub. Après `git rm`, le secret reste dans l'**historique** de la branche : une vraie fuite impose la rotation de la clé et la réécriture de l'historique.
7. **Trivy sans socket Docker.** L'image est exportée (`docker save`) et scannée en archive (`trivy image --input`). Trivy tourne avec l'UID de jenkins et un cache dans un volume nommé : aucun fichier root dans le workspace.
8. **Quality Gate sans agent.** Le stage `waitForQualityGate` n'a pas d'`agent` : l'attente du webhook n'occupe aucun exécuteur. Le stage suivant ne tourne que si la gate est OK (`abortPipeline: true`).
9. **`wfapi` et stages sautés.** Après l'échec de la Quality Gate, les stages non exécutés apparaissent en `FAILED 0 s` dans `wfapi` : ils n'ont pas tourné.
10. **Durcissement : SSHD.** Le module `sshd` (CLI par SSH) n'est pas installé : Jenkins n'ouvre aucun port SSH, et la clé JCasC `security.sSHD` n'existe pas. L'audit le vérifie (`module sshd non installé`).
11. **Point ouvert de l'audit : 4 exécuteurs sur le contrôleur.** Les labs 09 à 14 exécutent leurs stages Docker sur le contrôleur (label `docker`). La cible de production est **0 exécuteur sur le contrôleur**, avec un agent dédié portant le label `docker`. Un build sur le contrôleur peut lire `JENKINS_HOME` (secrets, configuration).

## Durcissement appliqué (`casc/90-durcissement.yaml`)

| Réglage | Valeur | Pourquoi |
|---|---|---|
| `disableRememberMe` | `true` | pas de cookie de session longue durée : une session volée ne survit pas |
| `markupFormatter` | `plainText` | descriptions affichées en texte brut : pas de XSS stockée |
| `remotingSecurity.enabled` | `true` | un agent compromis ne peut pas piloter le contrôleur |
| `slaveAgentPort` | `-1` | port TCP inbound fermé : seuls les agents SSH sont utilisés |
| `apiToken.creationOfLegacyTokenEnabled` | `false` | pas de jeton legacy (dérivé du mot de passe, non révocable proprement) |
| `apiToken.tokenGenerationOnCreationEnabled` | `false` | pas de jeton créé d'office pour chaque utilisateur |
| `apiToken.usageStatisticsEnabled` | `true` | dates d'usage : repérer et révoquer les jetons dormants |
| SSHD | module absent | aucun port SSH ouvert par Jenkins |
