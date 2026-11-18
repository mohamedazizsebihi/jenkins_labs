# Lab 10 — Agents, labels, parallélisme et matrice (agents déclarés par code)

Règle du lab : zéro clic. Les nœuds, les credentials et les jobs sont déclarés par code (JCasC + `jenkins-cli`) et vérifiés par API.

```
Contrôleur « Built-In Node » (label docker, 4 exécuteurs) ──SSH 127.0.0.1:2222──► agent-ssh-1
  accès au démon Docker (Lab 09)                                labels « linux ssh-agent », 2 exécuteurs,
                                                                mode EXCLUSIVE (conteneur jenkins/ssh-agent:latest-jdk21)
```

## Arborescence

| Fichier | Rôle |
|---|---|
| `../jenkins-as-code/casc/00-base.yaml` | Contrôleur : label `docker`, 4 exécuteurs |
| `../jenkins-as-code/casc/20-credentials.yaml` | + `agent-ssh-key` (SSH private key, scope **SYSTEM**, `${readFile:...}`) |
| `../jenkins-as-code/casc/40-agents.yaml` | Nœud `agent-ssh-1` : la **seule** définition de l'agent |
| `ci/lab10.Jenkinsfile` | Job `10-distribue` : Build (ssh-agent), Qualité en parallèle (failFast), Compatibilité en matrice, Vérification (ssh-agent) |
| `ci/lab10-sequentiel.Jenkinsfile` | Job `10-sequentiel` : le même travail, entièrement en séquence |
| `ci/lab10-ping.Jenkinsfile` / `ci/lab10-any.Jenkinsfile` | Jobs de test : avec le label `ssh-agent`, et sans label (`agent any`) |
| `scripts/00-agent-root.sh` | Tâches 1-2 (root) : clé ed25519, conteneur agent, clé d'hôte, test SSH, déploiement JCasC |
| `scripts/04-create-jobs.sh` | Lint (`declarative-linter`) puis création des 4 jobs |
| `scripts/06-nodes-api.sh` | Tâche 6 : nœuds par l'API (nom, labels, exécuteurs, état, motif) |
| `scripts/07-offline-queue.sh` | Tâche 7 : `offline-node -m`, file d'attente (API queue), `online-node` |
| `scripts/07b-exclusive.sh` | Critère « EXCLUSIVE » : un job sans label n'utilise jamais l'agent |
| `scripts/09-wfapi.sh` | Tâche 9 : stages, durées et nœud d'exécution par `wfapi` |
| `scripts/10-compare.sh` | Tâche 10 : durée distribuée vs séquentielle |

## Déroulé

```bash
./scripts/jcli install-plugin pipeline-stage-view -deploy      # fournit l'API wfapi
sudo bash scripts/00-agent-root.sh                             # tâches 1 à 5
./scripts/jcli reload-jcasc-configuration
./scripts/jcli wait-node-online agent-ssh-1                    # tâche 6
bash scripts/06-nodes-api.sh
bash scripts/04-create-jobs.sh
bash scripts/07-offline-queue.sh                               # tâche 7
bash scripts/07b-exclusive.sh
./scripts/jcli build 10-distribue -s -v                        # tâches 8 et 9
bash scripts/09-wfapi.sh 10-distribue
./scripts/jcli build 10-sequentiel -s -v                       # tâche 10
bash scripts/10-compare.sh
```

## Résultats

| Vérification | Résultat |
|---|---|
| Clé privée | `/etc/jenkins/files/jenkins_agent` en `-rw-r----- root:jenkins` |
| Test SSH | `connecté à <conteneur> en tant que jenkins`, Java 21, clé d'hôte vérifiée strictement |
| `wait-node-online agent-ssh-1` | en ligne après `reload-jcasc-configuration` (rechargement à chaud, sans redémarrage) |
| API nœuds | `Built-In Node` : `built-in docker`, 4 exécuteurs ; `agent-ssh-1` : `linux ssh-agent`, 2 exécuteurs |
| Hors ligne avec motif | file d'attente : `‘agent-ssh-1’ is offline` ; après `online-node`, `10-ping` s'exécute sur agent-ssh-1 |
| Mode EXCLUSIVE | contrôleur hors ligne et agent libre : `10-any` **attend** (`‘agent-ssh-1’ is reserved for jobs with matching label expression`) |
| Agent uniquement par JCasC | `delete-node agent-ssh-1`, puis `reload-jcasc-configuration` : l'agent revient à l'identique |
| `10-distribue` #1 | **FAILURE (vraie trouvaille)** : `pip-audit` trouve Flask 3.0.3 vulnérable (`PYSEC-2026-2151`), le stage Qualité échoue, la matrice et la vérification sont sautées |
| Correction | Flask 3.0.3 → **3.1.3** dans l'app (`feeae36`), `pip-audit` : *No known vulnerabilities found* |
| `10-distribue` #2 et #3 | **SUCCESS** : 3 branches parallèles + 5 cellules de matrice visibles dans `wfapi`, `app.tar.gz: OK` sur agent-ssh-1 |
| Nœud par stage | Build et Vérification sur **agent-ssh-1** ; Lint, Tests, Sécurité et les 5 cellules sur **built-in** (label docker) |
| Durées (cache pip chaud) | distribué **75 s** contre séquentiel **130 s**, soit **1.7x** plus rapide |

Pour la cellule `3.12 × alpine` (25.6 s), l'attente d'un exécuteur libre est comprise dans la durée : 5 cellules pour 4 exécuteurs sur le contrôleur.

## Pièges rencontrés

1. **`execNode` vide dans `wfapi`** : le nœud est donc lu dans les steps de chaque stage (`/execution/node/<id>/wfapi/describe`, step « Print Message » = `Nœud : …`).
2. **Pas de `tar` dans l'image agent** : l'archive est produite par `git archive --format=tar.gz`.
3. **Motif hors ligne** : Jenkins coupe le texte avant ` : ` et échappe l'apostrophe en HTML. Utiliser un motif simple.
4. **Comparaison de durées** : il faut un cache pip et des images déjà présents des deux côtés. Sinon, le premier build paie les téléchargements (113 s avec cache froid, 75 s avec cache chaud).
5. **Clé d'hôte** : `manuallyProvidedKeyVerificationStrategy` avec la clé relevée par `ssh-keyscan`, au lieu de `nonVerifying`. Si le conteneur est recréé, il faut relancer le script root.

## Réponses aux questions

**1. Agents permanents SSH, inbound (WebSocket/JNLP), cloud : différences ?**
- **SSH permanent** : le **contrôleur se connecte** à l'agent (port 22 de l'agent), copie `remoting.jar` et le lance. L'agent doit être joignable depuis le contrôleur et avoir Java. C'est simple pour des machines fixes d'un réseau interne.
- **Inbound** (JNLP / TCP 50000 ou **WebSocket** sur le port HTTP(S)) : c'est **l'agent qui se connecte** au contrôleur avec un secret. C'est idéal derrière un NAT ou un pare-feu (Windows, poste isolé, autre réseau). WebSocket évite d'ouvrir un port dédié.
- **Cloud** (Kubernetes, EC2, Docker…) : les agents sont **éphémères**, créés à la demande quand la file contient un build compatible, puis détruits. Ils offrent l'élasticité, un environnement propre à chaque build et un coût à l'usage, au prix d'un démarrage plus lent et d'une infrastructure à opérer.

**2. À quoi servent les labels ? Expression « linux ET (docker OU podman) »**
Un label décrit une **capacité** d'un nœud (OS, outil, architecture, zone). Un job ou un stage demande une **expression de labels**, et l'ordonnanceur choisit un nœud qui la satisfait. On découple ainsi le pipeline des noms de machines.
Expression : `linux && (docker || podman)`. Opérateurs disponibles : `&&`, `||`, `!`, `->`, `<->`, parenthèses.

**3. `stash` ou `archiveArtifacts` ?**
- `stash` / `unstash` : transfert de fichiers **entre les nœuds d'un même build**. Les fichiers sont temporaires, supprimés à la fin du build et invisibles dans l'interface. C'est fait pour de petits volumes (ici : sources, puis `dist/` de agent-ssh-1 vers les conteneurs et retour).
- `archiveArtifacts` : **livrables conservés** avec le build, téléchargeables dans l'interface et par l'API, suivis par empreinte (`fingerprint`) et soumis à la rétention (`buildDiscarder`). Pour des artefacts volumineux ou durables, on utilise plutôt un dépôt d'artefacts (Nexus, Artifactory, registre).

**4. Effet de `failFast` ?**
Dès qu'une branche du `parallel` (ou une cellule de matrice avec `failFast true`) échoue, Jenkins **interrompt immédiatement les autres branches** au lieu d'attendre leur fin. Le retour est plus rapide et on économise des exécuteurs. Sans `failFast`, les branches vont jusqu'au bout et on obtient tous les résultats d'un coup. Au build #1, Lint et Tests étaient **déjà terminés** quand la branche Sécurité a échoué (la plus lente) : `failFast` n'a donc rien eu à interrompre. C'est l'échec du stage `Qualité` qui a fait sauter la matrice et la Vérification (*skipped due to earlier failure*). L'effet de `failFast` se voit quand la branche en échec finit **avant** les autres.

**5. Pourquoi la clé de l'agent est-elle en scope SYSTEM ?**
La clé sert à **Jenkins lui-même** pour lancer l'agent, et aucun pipeline n'en a besoin. En scope **SYSTEM**, elle est utilisable par le contrôleur (configuration des nœuds) mais **invisible et inutilisable par les jobs** : `withCredentials` ou `credentials('agent-ssh-key')` échoue. En scope GLOBAL, n'importe quel auteur de Jenkinsfile pourrait la récupérer et se connecter à l'agent hors de Jenkins. C'est le principe du moindre privilège.
