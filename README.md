# Formation Snowflake : labs, démos et déploiement

Kit de formation Snowflake sur 2 jours (fondations, gouvernance, ingestion, performance, IA).
Il se redéploie en quelques minutes sur **n'importe quel compte trial** : tout le socle
(rôles, warehouses, participants, données) est généré à partir de `SNOWFLAKE_SAMPLE_DATA`
(TPCH), sans S3 et sans outil local.

## Déployer sur un nouveau compte trial

Prérequis : un compte trial **Enterprise**, de préférence AWS EU, et ce repo poussé sur GitHub
(public, ou privé avec un PAT : voir `setup/00_bootstrap_git.sql`).

1. **Bootstrap** (une seule fois, environ 1 min) : copier-coller `setup/00_bootstrap_git.sql` dans
   une worksheet Snowsight et l'exécuter en `ACCOUNTADMIN`. Le script crée l'API integration
   GitHub et l'objet `ADMIN.GIT.TRAINING_REPO`, puis lance `setup/deploy.sql`.
2. **Paramètres** : ils se règlent dans la clause `USING` de la dernière instruction du bootstrap :

   | Paramètre         | Défaut                 | Rôle                                      |
   |-------------------|------------------------|-------------------------------------------|
   | `nb_participants` | `10`                   | utilisateurs `P01`..`Pnn`                 |
   | `init_pwd`        | `Formation-Snow-2026!` | mot de passe initial (changé à la 1re connexion) |
   | `credit_quota`    | `100`                  | resource monitor du compte (crédits/mois) |

   Pour vérifier le rendu sans rien exécuter, ajouter `DRY_RUN = TRUE`.
3. **La veille** : lancer `setup/05_lab_prep.sql`, qui prépare les tables volumineuses du LAB 3
   (environ 3 à 5 crédits), puis vérifier que `search_optimization_progress = 100`.
   ```sql
   EXECUTE IMMEDIATE FROM @ADMIN.GIT.TRAINING_REPO/branches/main/setup/05_lab_prep.sql;
   ```

Après une modification du repo : `ALTER GIT REPOSITORY ADMIN.GIT.TRAINING_REPO FETCH;` puis
relancer `deploy.sql`. Tous les scripts sont idempotents.

**Remise à zéro** (`/!\` irréversible) :
```sql
EXECUTE IMMEDIATE FROM @ADMIN.GIT.TRAINING_REPO/branches/main/setup/99_teardown.sql
  USING (nb_participants => 10, drop_git => FALSE);
```

### Ce que crée le socle

| Script | Contenu |
|---|---|
| `01_account.sql` | rôles `FORMATION_ADMIN` / `FORMATION_PARTICIPANT`, `WH_ADMIN`, `WH_PERF_DEMO`, bases `FORMATION`, `SANDBOX`, `ADMIN` (GIT, SECURITY) |
| `02_formation_schemas.sql` | schémas `FORMATION.{COMMON,RAW,CURATED,ICEBERG,DBT}` en managed access + rôles techniques `_SR/_SW/_SFULL`, privilèges compte des labs |
| `03_participants.sql` | par participant : user `Pxx`, rôle `R_Pxx`, warehouse `WH_Pxx` (XS), schéma `SANDBOX.Pxx` |
| `04_data.sql` | `FORMATION.RAW.CUSTOMER` (TPCH + PII fictives), stage `FORMATION.COMMON.STG_FILES` (CSV/JSON/Parquet), file formats, `ORDERS_LANDING` + task « Snowpipe simulé » |
| `05_lab_prep.sql` | tables LINEITEM / ORDERS SF10 (clustering, SOS), test Cortex. **Lancé à part.** |
| `06_finops.sql` | resource monitor `RM_FORMATION` |

## Côté participants

- Connexion avec `Pxx` et le mot de passe initial. Prévoir 5 minutes au début de J1 pour
  l'enrôlement MFA.
- Les énoncés sont dans `labs/`. On peut les ouvrir dans Snowsight via
  *Projects > Workspaces > From Git repository*, ou les copier-coller.
- Chaque lab commence par un bloc « Contexte de session » qui sélectionne `R_Pxx`, `WH_Pxx` et `SANDBOX.Pxx`.

## Programme et supports

Les démos marquées **PAID** utilisent des fonctions absentes du trial (EAI, Cortex Agents,
Openflow, Snowpipe S3). Elles se jouent sur un compte payant séparé. Chaque script démarre
par son propre mini-setup (`DEMO_FORMATION`, `WH_DEMO`).

| Jour | Créneau | Sujet | Support | Compte |
|---|---|---|---|---|
| J1 matin | 45 min | Architecture (compute/storage, services, micro-partitions) | théorique | – |
| J1 matin | 45 min | Virtual Warehouses | `demos/J1_warehouses.sql` | TRIAL |
| J1 matin | 45 min | Organisation & Workspaces | démo UI (bases/schémas/stages du socle) | TRIAL |
| J1 matin | 45 min | Intégration Git & CI/CD | `demos/J1_git_cicd.sql`, `demos/ci/github_actions_deploy.yml` | TRIAL |
| J1 après-midi | 60+30+60 min | RBAC, Secure Views, RLS, Dynamic Data Masking, tags | **LAB 1** `labs/LAB1_gouvernance_enonce.sql` | TRIAL |
| J1 après-midi | 45 min | Data Sharing & Marketplace | `demos/J1_data_sharing.sql` | TRIAL → PAID |
| J1 après-midi | 45 min | Monitoring & FinOps | `demos/J1_finops.sql` | TRIAL |
| J2 matin | 60 min | Snowpipe, Openflow (CDC) | `demos/J2_snowpipe_openflow.sql` (+ LAB 2 ex. 8 sur le trial) | PAID |
| J2 matin | 30 min | Open Catalog / Iceberg | **LAB 2 ex. 2** (Iceberg Snowflake-managed) | TRIAL |
| J2 matin | 30 min | Formats & Stages | **LAB 2 ex. 1** | TRIAL |
| J2 matin | 45 min | Streams & Tasks, Dynamic Tables, dbt | **LAB 2 ex. 3 à 8** + `demos/J2_dbt_projects.sql` | TRIAL |
| J2 matin | 30 min | External access integration / Secrets | `demos/J2_eai_secrets.sql` | PAID |
| J2 après-midi | 60 min | Performance (Query Profile, caches, clustering, SOS) | **LAB 3 ex. 1 à 4** | TRIAL |
| J2 après-midi | 60 min | Cortex AI functions, ML Forecast / Anomaly | **LAB 3 ex. 5 et 6** | TRIAL |
| J2 après-midi | – | Cortex Search / Analyst / Agents, Cortex Code | `demos/J2_cortex_search_analyst_agent.sql` | PAID |
| J2 après-midi | 30 min | Streamlit in Snowflake | **LAB 3 ex. 7** + `utils/streamlit_app.py` | TRIAL |
| J2 après-midi | 60 min | Synthèse & Q/A | – | – |

## Organisation du repo

```
setup/      déploiement du socle (00 à copier-coller, deploy.sql orchestre, 99 teardown)
formateur/  corrigés des labs (source de vérité, blocs -- >>> SOLUTION / -- <<< SOLUTION)
labs/       énoncés participants, générés : python utils/make_enonces.py
demos/      démos formateur (en-tête : compte TRIAL ou PAID)
dbt/        projet dbt (TPCH -> FORMATION.DBT), déployé par demos/J2_dbt_projects.sql
utils/      make_enonces.py, streamlit_app.py (LAB 3 ex. 7)
```

**Modifier un lab** : éditer uniquement `formateur/LABx_*_corrige.sql`, puis lancer
`python utils/make_enonces.py` et committer les deux fichiers.

## Coûts et points de vigilance

- Le trial offre environ 400 $. Le socle et les labs consomment de l'ordre de 15 à 25 crédits
  pour 10 participants, la majeure partie au LAB 3 (SF100, Cortex).
- À la fin de chaque lab, exécuter son dernier bloc, qui suspend les tasks, les dynamic tables
  et remet le warehouse en XS. Côté formateur, suspendre aussi `FORMATION.RAW.T_SIMULATED_SNOWPIPE`
  après le LAB 2.
- Le resource monitor ne couvre que les warehouses. Le serverless (tasks, SOS, Cortex) se suit
  avec `demos/J1_finops.sql`.
- Cortex : si un modèle n'est pas disponible dans la région,
  `ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_EU';`.
