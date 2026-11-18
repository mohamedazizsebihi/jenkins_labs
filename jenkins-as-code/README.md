# Lab 07 — Credentials, paramètres et conditions (secrets gérés par code)

Règle du lab : zéro clic. Tout passe par JCasC, `jenkins-cli` et des fichiers versionnés.

## Arborescence

| Fichier | Rôle |
|---|---|
| `casc/20-credentials.yaml` | Credentials déclarés par JCasC (`demo-api-token`, `httpbin-creds`, `app-config`), sans aucune valeur secrète |
| `ci/lab07.Jenkinsfile` | Pipeline paramétré (source de vérité du job `07-params-credentials`) |
| `credentials/demo-api-token-cli.xml.tpl` | Modèle XML pour `create-credentials-by-xml` |
| `scripts/jcli` | Wrapper du CLI Jenkins |
| `scripts/00-setup-root.sh` | Côté serveur (root) : `/etc/jenkins/secrets.env`, `app.env`, JCasC, override systemd, redémarrage |
| `scripts/05-credential-cli.sh` | Tâche 5 : création, liste et suppression d'un credential en CLI |
| `scripts/07-create-and-run.sh` | Tâche 7 : création du job depuis le Jenkinsfile et lancement des 4 builds |
| `scripts/08-check-secrets.sh` | Tâche 8 : grep des consoles et du dépôt Git |
| `scripts/09-replay-insecure.sh` | Tâche 9 : Replay avec interpolation Groovy (anti-pattern volontaire) |
| `secrets.env.example` | Modèle des variables attendues (sans valeur réelle) |

## Déroulé

```bash
sudo bash scripts/00-setup-root.sh                     # tâches 1, 2, 4 (valeurs saisies au clavier)
./scripts/jcli list-credentials system::system::jenkins # tâche 4
bash scripts/05-credential-cli.sh                      # tâche 5
bash scripts/07-create-and-run.sh                      # tâches 6, 7
bash scripts/08-check-secrets.sh                       # tâche 8
bash scripts/09-replay-insecure.sh                     # tâche 9
```

Chaîne de résolution d'un secret :

```
/etc/jenkins/secrets.env (root, 600)
   └─ systemd EnvironmentFile ─► variables d'environnement du processus Jenkins
        └─ JCasC (CASC_JENKINS_CONFIG=/etc/jenkins/casc.d) résout ${DEMO_API_TOKEN}, ${HTTPBIN_PASSWORD}
/etc/jenkins/files/app.env (jenkins, 600)
   └─ JCasC ${readFileBase64:/etc/jenkins/files/app.env} ─► credential "app-config"
```

## Résultats

| Build | Paramètres | Tests | Déploiement prod | Résultat |
|---|---|---|---|---|
| #1 | valeurs par défaut (dev, 1.0.0) | exécuté | sauté | SUCCESS |
| #2 | `TARGET_ENV=dev RUN_TESTS=false` | **sauté** | sauté | SUCCESS |
| #3 | `TARGET_ENV=prod VERSION=2.0.0-SNAPSHOT` | exécuté | **sauté** (SNAPSHOT) | SUCCESS, avec 2 `retry` sur timeout httpbin |
| #4 | `TARGET_ENV=prod VERSION=2.0.0` | exécuté | **exécuté** | SUCCESS |
| #5 | Replay du #4 avec guillemets doubles | exécuté | exécuté | SUCCESS + avertissement Jenkins |

Critères de validation :
- **Aucun secret dans Git ni dans les consoles** : `08-check-secrets.sh` trouve 0 occurrence sur les builds #1 à #5, dans les fichiers et dans tout l'historique Git.
- **Déploiement prod uniquement au 3ᵉ build CLI** (#4). Le #5 n'est que le Replay du #4.
- **Recréation à l'identique** : après `delete-credentials demo-api-token`, la commande `reload-jcasc-configuration` le recrée. Il en va de même à chaque redémarrage ou reconstruction de Jenkins.

Avertissement relevé à la tâche 9 :

```
Warning: A secret was passed to "sh" using Groovy String interpolation, which is insecure.
         Affected argument(s) used the following variable(s): [API_PASS]
```

Seul `API_PASS` est cité, car le nom d'utilisateur n'est pas traité comme secret (option « Treat username as secret » désactivée par défaut).

## Pièges rencontrés

1. **L'URL httpbin contient le mot de passe** (`/basic-auth/isoset/<mot de passe>`). Écrite en dur, elle aurait mis le secret dans Git. Elle est donc construite avec `$API_USER/$API_PASS`, et la console affiche `/basic-auth/isoset/****`.
2. **`sh` est lancé avec `-xe`**. En chargeant `app.env`, la trace aurait affiché `+ DB_PASSWORD=<valeur>` en clair, car le masquage d'un *secret file* ne connaît que le chemin du fichier, pas son contenu. La solution est `set +x` en tête du bloc.
3. **Un `restart` lancé depuis Jenkins ne relit pas l'environnement** : il faut `systemctl restart jenkins` pour prendre en compte `EnvironmentFile`.
4. **Un credential créé à la main (CLI ou UI) dans le store System est une dérive** : JCasC le supprime au prochain chargement, car la liste déclarée remplace la liste existante.

## Réponses aux questions

**1. Scopes GLOBAL et SYSTEM d'un credential ?**
- **GLOBAL** : le credential est utilisable par Jenkins et par tous les jobs et pipelines (`credentials()`, `withCredentials`, configuration SCM).
- **SYSTEM** : réservé à Jenkins lui-même (connexion des agents SSH, intégrations configurées dans « Administrer Jenkins »). Il est invisible pour les jobs : un pipeline ne peut pas le lire, ce qui limite la surface d'exfiltration.

**2. Que crée `credentials('httpbin-creds')` dans un bloc `environment` ?**
Pour un credential *Username with password* affecté à `HTTPBIN = credentials('httpbin-creds')`, trois variables sont créées, toutes masquées :
- `HTTPBIN` contient `utilisateur:motdepasse` ;
- `HTTPBIN_USR` contient l'utilisateur ;
- `HTTPBIN_PSW` contient le mot de passe.

Pour un *secret text*, la variable contient la valeur. Pour un *secret file*, elle contient le chemin d'un fichier temporaire supprimé en fin de bloc.

**3. Pourquoi passer les secrets au shell avec des guillemets simples ?**
Avec `sh '... $API_PASS'`, c'est le **shell** qui lit la variable d'environnement au moment de l'exécution : le secret n'est jamais dans la chaîne Groovy. Avec `sh "... ${API_PASS}"`, **Groovy** insère la valeur dans la commande avant son envoi à l'agent. Conséquences :
- le secret est écrit en clair dans le script temporaire (`workspace@tmp/durable-*/script.sh`) ;
- il peut apparaître dans les logs, les vues Replay et les traces de pipeline ;
- un caractère spécial dans le secret (`$`, `` ` ``, `;`, `'`, espace) peut casser la commande ou permettre une injection shell ;
- le masquage peut échouer si l'échappement modifie la valeur affichée.

**4. Le masquage `****` suffit-il ? Contre-exemple ?**
Non. C'est une simple recherche de la valeur exacte dans la sortie de la console. Il suffit de transformer le secret pour qu'il ne soit plus reconnu :
- `echo "$TOKEN" | base64` ou `echo "$TOKEN" | rev` ;
- `echo "$TOKEN" | sed 's/./& /g'` (un espace entre chaque caractère) ;
- `echo "${TOKEN:0:4}"` (affichage partiel) ;
- écrire le secret dans un fichier archivé comme artefact, ou l'envoyer vers un serveur externe (`curl -d "$TOKEN" https://...`) ;
- et le masquage ne protège rien du tout pour le contenu d'un *secret file* (voir le piège 2).

Toute personne qui peut modifier le Jenkinsfile ou lancer un Replay peut donc lire les secrets. La vraie protection, ce sont les droits sur les dépôts, les branches et la permission `Run/Replay`, et le scope des credentials (folders, SYSTEM).

**5. Quelles alternatives à `secrets.env` pour fournir les valeurs à JCasC en entreprise ?**
- **Kubernetes Secrets** montés en fichiers : JCasC lit les fichiers du répertoire indiqué par `SECRETS` (par défaut `/run/secrets`), un fichier par variable.
- **Docker / Swarm secrets** (`/run/secrets/<nom>`).
- **HashiCorp Vault** : résolution des `${...}` par JCasC via le plugin Vault, ou credentials lus dynamiquement par `withVault`.
- **AWS Secrets Manager / SSM Parameter Store**, **Azure Key Vault**, **GCP Secret Manager** : plugins *credentials provider* qui exposent les secrets du coffre comme credentials Jenkins, sans les stocker dans `JENKINS_HOME`.
- **CyberArk Conjur**, **1Password Connect**…

Principe commun : le secret vit dans un coffre centralisé, avec rotation, audit et contrôle d'accès. Jenkins ne fait que le référencer.
