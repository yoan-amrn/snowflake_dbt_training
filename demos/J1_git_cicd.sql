/* =============================================================================
   DEMO J1 matin - INTEGRATION GIT & CI/CD
   Compte : TRIAL - Role : FORMATION_ADMIN (lecture/fetch du repo via _ADMIN_GIT_SFULL)
   Fil rouge : ce repo de formation a lui-meme ete deploye ainsi (00_bootstrap_git.sql).
   Pipeline exemple : demos/ci/github_actions_deploy.yml
   ============================================================================= */

USE ROLE FORMATION_ADMIN;
USE WAREHOUSE WH_ADMIN;

-- -----------------------------------------------------------------------------
-- 1. Les 3 objets : API INTEGRATION (compte) -> [SECRET] -> GIT REPOSITORY (schema)
-- -----------------------------------------------------------------------------
SHOW API INTEGRATIONS LIKE 'API_GITHUB_FORMATION';      -- visible si USAGE accorde (sinon ACCOUNTADMIN)
DESCRIBE GIT REPOSITORY ADMIN.GIT.TRAINING_REPO;

-- -----------------------------------------------------------------------------
-- 2. Le repo est vu comme un stage en lecture seule : branches / tags / commits
-- -----------------------------------------------------------------------------
ALTER GIT REPOSITORY ADMIN.GIT.TRAINING_REPO FETCH;     -- synchronise avec GitHub
SHOW GIT BRANCHES IN ADMIN.GIT.TRAINING_REPO;
SHOW GIT TAGS     IN ADMIN.GIT.TRAINING_REPO;
LS @ADMIN.GIT.TRAINING_REPO/branches/main/;
LS @ADMIN.GIT.TRAINING_REPO/branches/main/labs/;

-- Lire un fichier versionne directement
SELECT $1 FROM @ADMIN.GIT.TRAINING_REPO/branches/main/README.md (FILE_FORMAT => (TYPE = CSV FIELD_DELIMITER = NONE)) LIMIT 20;

-- -----------------------------------------------------------------------------
-- 3. Deployer depuis Git : EXECUTE IMMEDIATE FROM (+ templates Jinja)
--    DRY_RUN = TRUE : affiche le SQL rendu sans l'executer (revue avant deploiement)
-- -----------------------------------------------------------------------------
EXECUTE IMMEDIATE FROM @ADMIN.GIT.TRAINING_REPO/branches/main/setup/06_finops.sql
  USING (credit_quota => 100)
  DRY_RUN = TRUE;

-- Meme principe pour des environnements : USING (env => 'DEV') / (env => 'PROD')
-- et dans le script : CREATE SCHEMA IF NOT EXISTS {{ env }}_CURATED ...

-- -----------------------------------------------------------------------------
-- 4. Versionner les objets Snowflake : bonnes pratiques
-- - DDL idempotents (CREATE OR ALTER / IF NOT EXISTS), un fichier par domaine
-- - CREATE OR ALTER TABLE : DDL declaratif, Snowflake calcule le diff
-- - Branches = environnements (feature -> dev, main -> prod), tags = releases
-- - Secrets jamais dans le repo : SECRET Snowflake ou secrets du CI
-- -----------------------------------------------------------------------------
CREATE OR ALTER TABLE FORMATION.CURATED.DEMO_CREATE_OR_ALTER (ID NUMBER, LIBELLE STRING);
CREATE OR ALTER TABLE FORMATION.CURATED.DEMO_CREATE_OR_ALTER (ID NUMBER, LIBELLE STRING, CREATED_AT TIMESTAMP_LTZ);
DESCRIBE TABLE FORMATION.CURATED.DEMO_CREATE_OR_ALTER;   -- colonne ajoutee sans perte de donnees
DROP TABLE FORMATION.CURATED.DEMO_CREATE_OR_ALTER;

-- -----------------------------------------------------------------------------
-- 5. Workspaces Snowsight relies a Git (UI) : Projects > Workspaces > From Git repository
--    -> edition, commit, push depuis Snowsight ; VS Code : extension Snowflake + Snowflake CLI.
-- 6. Pipeline CI/CD : montrer demos/ci/github_actions_deploy.yml
--    push sur main -> snow git fetch -> snow sql "EXECUTE IMMEDIATE FROM ..."
-- -----------------------------------------------------------------------------
