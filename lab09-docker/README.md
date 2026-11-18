# Lab 09 — Docker dans Jenkins : agents conteneurisés, build et push

Règle du lab : zéro clic. Tout passe par du code, `jenkins-cli` et des API.

> **Adaptation** : pas de compte Docker Hub disponible. Le push vise donc un **registre Docker
> local authentifié** (`registry:2` sur `127.0.0.1:5050`, htpasswd). La chaîne reste identique :
> `docker login --password-stdin`, 3 tags, `docker logout`, puis vérification par l'API Registry v2,
> le même standard que celui qu'utilise Docker Hub.
> Pour passer à Docker Hub : `REGISTRY = 'docker.io'`, `REGISTRY_CREDS = 'dockerhub-creds'`,
> déclarer `dockerhub-creds` dans JCasC (`DOCKERHUB_USER` / `DOCKERHUB_TOKEN`), puis utiliser
> `scripts/06-dockerhub-tags.sh`.

## Arborescence

| Fichier | Rôle |
|---|---|
| `ci/lab09.Jenkinsfile` | Pipeline déclaratif (`agent none`) : Préparation, Lint, Tests, Build image, Smoke test, Push, puis ménage en `post` |
| `ci/lab09-plugin.Jenkinsfile` | Variante avec l'API Groovy du plugin : `docker.image().inside`, `docker.build`, `withRun`, `withRegistry` |
| `scripts/00-registry-root.sh` | Tâche 2 (root) : jeton aléatoire, registre local, `secrets.env`, JCasC, redémarrage |
| `scripts/04-lint-and-create-jobs.sh` | Tâche 4 : `declarative-linter` puis création des jobs `09-docker` et `09-docker-plugin` |
| `scripts/05-docker-commands.sh` | Tâche 5 : commandes docker générées par Jenkins, relevées dans la console |
| `scripts/06-registry-tags.sh` | Tâche 6 : tags et digests lus par l'API du registre |
| `scripts/06-dockerhub-tags.sh` | Tâche 6 version Docker Hub (`hub.docker.com/v2/repositories/...`) |
| `scripts/07-run-published.sh` | Tâche 7 : pull de l'image publiée, `GET /`, version = n° de build |
| `scripts/08-check-leftovers.sh` | Tâche 8 : aucun conteneur `smoke-*` ou d'agent, aucune image restante |
| `scripts/jcli` | Wrapper du CLI Jenkins |

Fichiers modifiés ailleurs :
- `jenkins-demo-app/` : `/` renvoie `version` (variable `APP_VERSION`), le Dockerfile a `ARG APP_VERSION` et `USER nobody`, et un test est ajouté.
- `jenkins-as-code/casc/20-credentials.yaml` : ajout cumulatif de `registry-creds`.

## Déroulé

```bash
# Tâche 1
sudo -u jenkins docker ps                                   # permission denied
sudo usermod -aG docker jenkins && sudo systemctl restart jenkins
sudo -u jenkins docker ps                                   # OK
./scripts/jcli install-plugin docker-workflow
# Tâche 2
sudo bash scripts/00-registry-root.sh
./scripts/jcli list-credentials system::system::jenkins
# Tâches 3, 4 et 5
bash scripts/04-lint-and-create-jobs.sh
./scripts/jcli build 09-docker -s -v
bash scripts/05-docker-commands.sh 1
# Tâches 6, 7 et 8
sudo bash scripts/06-registry-tags.sh
sudo bash scripts/07-run-published.sh 1
bash scripts/08-check-leftovers.sh
# Tâche 9
./scripts/jcli build 09-docker-plugin -s -v
```

## Résultats

| Vérification | Résultat |
|---|---|
| `sudo -u jenkins docker ps` | refusé avant, OK après (`groups=jenkins,docker`) |
| `list-credentials` | 4 credentials, dont `registry-creds` (JCasC cumulatif) |
| `declarative-linter` | `Jenkinsfile successfully validated.` (×2) |
| Build `09-docker` #1 | **SUCCESS** |
| Lint et Tests | dans `python:3.12-slim` (`/usr/local/bin/python`, dans le conteneur) : 5 tests passés |
| Cache pip partagé (volume nommé) | 4.0K avant Lint, puis 5.4M réutilisés par Tests |
| Smoke test | port libre attribué par Docker, `/health` = up, `/` renvoie `"version":"1"`, conteneur supprimé |
| Push | tags `1`, `a4f9141`, `latest` avec le **même digest** `sha256:26c6dbbe…` ; `Removing login credentials` |
| API du registre | `tags: ["latest","a4f9141","1"]` |
| Image publiée lancée en local | `version: "1"` = build Jenkins #1 |
| Restes sur l'hôte | aucun conteneur `smoke-*`, aucun conteneur d'agent, aucune image `jenkins-demo-app` |
| Variante plugin `09-docker-plugin` #1 | **SUCCESS** : tags `plugin-1` et `plugin-a4f9141`, sans écraser les tags du job principal |

Commandes générées par Jenkins pour un stage `agent { docker }` (tâche 5) :

```
docker inspect -f . python:3.12-slim
docker run -t -d -u 108:117 -w <ws> -v <ws>:<ws>:rw,z -v <ws>@tmp:<ws>@tmp:rw,z -e ******** ... python:3.12-slim cat
docker top <id> -eo pid,comm
docker stop --time=1 <id>
docker rm -f --volumes <id>
```

Le conteneur est lancé avec `cat` pour rester vivant. Chaque `sh` du stage est ensuite exécuté par
`docker exec` dans ce conteneur : cette commande n'est pas affichée dans la console, mais c'est
elle qui exécute les steps. Le conteneur est arrêté puis supprimé à la fin du stage.

## Pièges rencontrés

1. **Groupe docker** : `usermod` ne suffit pas, il faut un `systemctl restart jenkins`. Les groupes d'un processus sont fixés à son démarrage.
2. **UID** : l'agent tourne en `-u 108:117`, un UID qui n'existe pas dans l'image. Il n'a donc pas de `HOME` utilisable, d'où `-e HOME=/tmp`. Et le volume nommé `jenkins-pip-cache`, créé par root, n'est pas inscriptible, d'où le `chown` à l'UID de jenkins dans le stage Préparation.
3. **Cache des couches** : `ARG APP_VERSION` est placé **après** `pip install` dans le Dockerfile. Placé avant, chaque build (nouvelle version) invaliderait la couche des dépendances.
4. **Jeton du registre** : le pipeline principal utilise `--password-stdin` et un `DOCKER_CONFIG` jetable, supprimé par un `trap`. La variante `withRegistry` du plugin lance `docker login -u … -p ********` : le mot de passe passe en argument, il est donc visible dans la liste des processus de l'hôte, même s'il est masqué dans la console.
5. **Docker Desktop** : un redémarrage de Docker Desktop fait disparaître `/var/run/docker.sock` quelques secondes, et les commandes `docker` échouent pendant ce temps.

## Réponses aux questions

**1. Pourquoi l'appartenance au groupe docker équivaut-elle à un accès root ? Alternatives ?**
Le socket `/var/run/docker.sock` pilote un démon qui tourne en **root**. Quiconque peut lui parler peut lancer `docker run -v /:/host --privileged …` et obtenir un shell root sur l'hôte : lire `/etc/shadow`, modifier `sudoers`, etc. Démonstration dans ce lab : dès son ajout au groupe, `jenkins` voit et peut arrêter **tous** les conteneurs de l'hôte, y compris ceux d'un autre projet. Donc tout auteur de Jenkinsfile devient root.
Alternatives :
- Docker ou Podman **rootless** ;
- builders sans démon : **Kaniko**, **Buildah**, **BuildKit rootless** ;
- agents dédiés et jetables (VM ou pod Kubernetes) réservés aux builds d'images ;
- un proxy du socket qui filtre l'API (par exemple *docker-socket-proxy*) ;
- un registre et un builder distants.

**2. `agent { docker }` ou `docker.image().inside {}` ?**
- `agent { docker { image … } }` (déclaratif) : **tout le stage** tourne dans le conteneur. La syntaxe est validée par le linter et les options sont déclaratives (`args`, `reuseNode`, `alwaysPull`…).
- `docker.image('…').inside('args') { … }` (API Groovy, dans un `script`) : seul le bloc tourne dans le conteneur. On peut donc mélanger dans un même stage des steps sur l'hôte (comme `docker.build`) et des steps en conteneur, ou utiliser plusieurs images à la suite. C'est plus souple, mais moins lisible et non validé par le linter.

Les deux reposent sur le même mécanisme : `docker run … cat`, puis `docker exec` pour chaque step, puis `docker stop` et `docker rm`.

**3. Pourquoi le workspace est-il visible dans le conteneur ? Quel problème d'UID peut survenir ?**
Jenkins monte le workspace et `workspace@tmp` **au même chemin** (`-v ws:ws -w ws`). Les steps lancés par `docker exec` lisent et écrivent donc les mêmes fichiers que Jenkins : sources, rapports JUnit, scripts temporaires de `sh` dans `@tmp`.
Problème d'UID : le conteneur est lancé avec l'UID et le GID de `jenkins` (`-u 108:117`), qui n'existent pas dans l'image. Conséquences :
- pas d'entrée dans `/etc/passwd` (« I have no name! ») ;
- pas de `HOME` inscriptible (`pip`, `npm`, `git` échouent) ;
- pas d'écriture possible dans les répertoires appartenant à root.

À l'inverse, forcer `-u root` crée dans le workspace des fichiers appartenant à root, que Jenkins ne peut plus supprimer (`cleanWs` ou checkout suivant en *permission denied*).

**4. Pourquoi ne pas utiliser seulement `latest` ?**
`latest` est **mutable** : le même nom désigne une image différente à chaque push. Conséquences :
- aucune traçabilité (quel commit tourne en production ?) ;
- pas de retour arrière fiable ;
- caches et politiques `IfNotPresent` qui gardent une ancienne image ;
- courses entre builds concurrents.

Les tags **immuables** (n° de build et SHA Git) relient une image à un build et à un commit. Ici, les 3 tags pointent vers le même digest. `latest` n'est qu'un raccourci, et en production on déploie de préférence **par digest**.

**5. Docker-in-Docker ou Docker-outside-of-Docker ?**
- **DinD** : un démon Docker tourne **dans** un conteneur (`docker:dind`, en `--privileged`). Il offre une isolation par build (images, réseau, cache). En contrepartie, il exige le mode privilégié, superpose deux systèmes de stockage, perd le cache à chaque build et reste un risque de sécurité.
- **DooD** (ce lab) : on utilise le démon **de l'hôte** via son socket. C'est simple, rapide, avec un cache partagé. En contrepartie, cela équivaut à root sur l'hôte, les conteneurs créés sont des « frères » (les chemins de bind mount sont ceux de l'hôte) et les noms ou ports peuvent entrer en collision entre builds.
- En entreprise, on préfère souvent des builders sans démon ou rootless (Kaniko, Buildah, BuildKit) sur des agents éphémères.
