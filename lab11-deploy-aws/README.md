# Lab 11 — Déploiement continu sur AWS EC2 avec Ansible, validation par API

Règle du lab : zéro clic. AWS est piloté par l'AWS CLI (profil `isoset`), Jenkins par JCasC, `jenkins-cli` et l'API REST.

```
WSL ─ Jenkins (contrôleur, label docker) ── sshagent(ec2-ssh-key) ── ansible-playbook ──► EC2 t3.micro Ubuntu 24.04
         │  input « DeployProd » (submitter admin)                                        │ docker run -p 80:5000
         └─ validé / refusé par curl (API REST)                                           └─ docker pull ECR (rôle IAM)
```

## Arborescence

| Fichier | Rôle |
|---|---|
| `ci/lab11.Jenkinsfile` | Job `11-deploy-aws` : Contrôles → Approbation (sans agent) → Déploiement → Smoke test |
| `../jenkins-demo-app/ansible/deploy.yml` | Playbook : Docker, authentification ECR par rôle IAM, conteneur sur le port 80, `/health`, versions mémorisées pour le rollback |
| `../jenkins-as-code/casc/10-security.yaml` | Fin du mode « Unsecured » : utilisateurs `admin` / `dev1`, matrice de droits |
| `../jenkins-as-code/casc/20-credentials.yaml` | + `ec2-ssh-key` (SSH private key, scope GLOBAL, `${readFile:/etc/jenkins/files/ec2.pem}`) |
| `../jenkins-as-code/casc/00-base.yaml` | + variables globales `ECR_REGISTRY` (hors Git) et `PATH+ANSIBLE` |
| `scripts/01-aws-provision.sh` | « Zéro console AWS » : ECR, rôle IAM, Security Group, key pair, instance (tag `Project=jenkins-lab11`) |
| `scripts/02-push-images.sh` | Images `1.0.0`, `1.1.0` (= `latest`) poussées sur ECR |
| `scripts/00-root.sh` | Tâche 1 + sécurité Jenkins : clé EC2, mots de passe aléatoires, jetons d'API (root) |
| `scripts/00b-ansible-venv-root.sh` | Ansible moderne isolé pour Jenkins (`/opt/ansible`, ansible-core 2.17) |
| `scripts/03-playbook-manual.sh` | Tâche 3 : playbook lancé à la main depuis WSL |
| `scripts/05-create-job.sh` | Tâche 5 : lint, création du job, 1er build (échec voulu) |
| `scripts/06-launch-input.sh` | Tâches 6-8 : build en arrière-plan, `pendingInputActions`, refus pour dev1 |
| `scripts/09-approve.sh` | Tâche 9 : validation admin par l'API, suivi du build, `curl` |
| `scripts/10-refuse.sh` | Tâche 10 : refus par l'API, résultat `ABORTED` |
| `scripts/11-deploy-rollback.sh` | Tâche 11 : déploiement 1.1.0 puis rollback |
| `scripts/12-historique.sh` | Historique des builds par l'API |
| `scripts/99-aws-cleanup.sh` | Suppression de toutes les ressources AWS du lab, avec vérification |

## Déroulé

```bash
bash scripts/01-aws-provision.sh            # ressources AWS (profil isoset, us-east-1)
bash scripts/02-push-images.sh              # images sur ECR
sudo bash scripts/00-root.sh                # tâche 1 + sécurité Jenkins
sudo bash scripts/00b-ansible-venv-root.sh  # Ansible 2.17 pour Jenkins
bash scripts/03-playbook-manual.sh          # tâche 3
bash scripts/05-create-job.sh               # tâches 4-5
bash scripts/06-launch-input.sh             # tâches 6-8
bash scripts/09-approve.sh                  # tâche 9
bash scripts/10-refuse.sh                   # tâche 10
bash scripts/11-deploy-rollback.sh          # tâche 11
bash scripts/99-aws-cleanup.sh              # suppression des ressources AWS
```

## Résultats

| Build | Paramètres | Résultat | Détail |
|---|---|---|---|
| #1 | aucun | FAILURE (voulu) | `Paramètre EC2_HOST obligatoire` : enregistre les paramètres |
| #2 | deploy 1.0.0 | FAILURE | Ansible 2.10 du système incompatible avec Python 3.12 (voir pièges) |
| #3 | deploy 1.0.0 | SUCCESS | dev1 refusé (HTTP 400, *You need to be admin to submit this*), validé par admin (HTTP 200), `Approved by admin` |
| #4 | deploy 1.1.0 | **ABORTED** | refusé par l'API (`input/DeployProd/abort`) : `Rejected by admin`, version servie inchangée |
| #5 | deploy 1.1.0 | SUCCESS | `curl /` renvoie `"version":"1.1.0"` |
| #6 | rollback | SUCCESS | `curl /` renvoie `"version":"1.0.0"` ; serveur : `{"current": "1.0.0", "previous": "1.1.0"}` |

Critères de validation :
- `curl http://<IP>/` renvoie la bonne version : 1.0.0, puis 1.1.0, puis 1.0.0 après le rollback.
- Validation et refus réalisés par curl, valideur visible dans la console (`Approved by admin`, `Déploiement validé par : admin`, `Rejected by admin`).
- Rollback fonctionnel, piloté par l'état mémorisé sur le serveur (`/opt/demo-app/versions.json`).
- Ressources AWS supprimées : 0 instance, 0 SG, 0 key pair, 0 volume ; rôle IAM et dépôt ECR absents. Les autres instances du compte n'ont pas été touchées.

## Pièges rencontrés

1. **Deux Ansible sur la même machine.** `bihi` utilisait ansible-core 2.17 (`pip --user`) et `jenkins` l'Ansible **2.10** d'apt (Ubuntu 22.04). Ansible 2.10 ne pilote pas Python 3.12 (Ubuntu 24.04) : `No module named 'ansible.module_utils.six.moves'`. Correctif : un venv isolé `/opt/ansible` (ansible-core 2.17.14), ajouté au PATH des builds par JCasC (`PATH+ANSIBLE`). Le système reste intact.
2. **Code HTTP du refus pour dev1 : 400, pas 403.** L'étape `input` renvoie une erreur métier (*You need to be admin to submit this*) et non un refus d'autorisation global : dev1 garde le droit de lire le job (HTTP 200). Il faut vérifier le motif, pas seulement le code.
3. **L'image locale (registre du Lab 09) est inaccessible depuis EC2.** Elle est donc publiée sur **ECR**. L'instance s'authentifie par son **rôle IAM** (`amazon-ecr-credential-helper`) : aucun mot de passe n'est déposé sur le serveur.
4. **Le compte AWS ne doit pas finir dans Git.** `ECR_REGISTRY` est fourni par `secrets.env`, puis par JCasC (variable globale). Les logs du rapport masquent le n° de compte et l'IP du poste.
5. **`lock_timeout` sur apt.** Au premier démarrage, `unattended-upgrades` verrouille dpkg : le module `apt` attend au lieu d'échouer.

## Réponses aux questions

**1. Pourquoi `sshagent` plutôt que copier la clé dans le workspace ?**
Avec `sshagent`, la clé est chargée **en mémoire** dans un `ssh-agent` propre au build (`SSH_AUTH_SOCK`), puis l'agent est tué à la fin du bloc (`ssh-agent -k`). La clé n'est **jamais écrite sur disque**. Copiée dans le workspace, elle resterait dans un fichier lisible par les autres jobs du même nœud, pourrait être archivée ou laissée par erreur (workspace non nettoyé, `archiveArtifacts`) et se retrouverait dans les sauvegardes. On devrait en plus gérer ses droits (`chmod 600`) et sa suppression même en cas d'échec.

**2. Pourquoi l'input doit-il être hors de tout agent ?**
Une validation humaine peut durer des minutes ou des heures. À l'intérieur d'un `agent`, elle **bloquerait un exécuteur** (et éventuellement un conteneur ou une VM cloud facturée) pendant toute l'attente, et les autres builds seraient affamés. Avec `agent none` sur le stage Approbation, le build reste en pause **sans consommer d'exécuteur**. Bonus : le workspace n'est pas verrouillé et un agent cloud peut être rendu.

**3. Pourquoi fixer l'id de l'input ? Quel piège de casse existe ?**
Sans `id`, Jenkins en génère un aléatoire à chaque build. Un outil externe (bot Slack/Teams, outil de change management, nos scripts curl) ne peut alors pas construire l'URL `/job/<job>/<n>/input/<id>/proceedEmpty` ou `/abort` à l'avance. Avec `id: 'DeployProd'`, l'URL est stable et documentable.
Piège de casse : Jenkins **met en majuscule la première lettre** de l'id dans l'URL. Un `id: 'deployProd'` répond donc sur `/input/DeployProd/`, et les appels vers `/input/deployProd/` échouent (404). D'où le choix d'un id déjà en PascalCase.

**4. Continuous Delivery ou Continuous Deployment ?**
- **Continuous Delivery** : chaque changement validé est **prêt** à partir en production (build, tests, artefact, déploiement automatisé), mais la mise en production reste une **décision humaine**. C'est ce lab : `input` + validation par `admin`.
- **Continuous Deployment** : aucune intervention humaine. Tout changement qui passe le pipeline est **déployé automatiquement** en production. Cela exige une très forte confiance dans les tests, de l'observabilité, des déploiements progressifs et un rollback automatique.

**5. Deux stratégies de déploiement sans interruption ?**
- **Blue/Green** : deux environnements identiques. On déploie la nouvelle version sur l'environnement inactif (green), on le teste, puis on bascule le trafic (load balancer, DNS, target group). Le rollback est instantané, il suffit de rebasculer. Le coût est double pendant la bascule.
- **Rolling update** : on remplace les instances ou conteneurs **par lots**, derrière un load balancer, avec health checks entre chaque lot (Auto Scaling Group, Kubernetes Deployment). Il n'y a pas de doublement d'infrastructure, mais deux versions coexistent pendant l'opération.
- (Variante : **Canary**, une petite fraction du trafic va vers la nouvelle version, puis on augmente si les métriques restent bonnes.)

Ici, une seule instance et `docker rm` puis `docker run` provoquent une courte coupure. Pour du zéro-downtime, il faudrait au moins deux conteneurs derrière un reverse proxy (blue/green local) ou un ALB devant plusieurs instances.
