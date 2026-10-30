/* =============================================================================
   00 - BOOTSTRAP GIT : seul script a COPIER-COLLER dans une worksheet Snowsight
   A executer en ACCOUNTADMIN sur un compte trial neuf (edition ENTERPRISE).
   Cree le lien entre le compte et le repo GitHub de formation, puis tout le
   reste se deploie depuis le repo (setup/deploy.sql).
   Idempotent : peut etre relance.

   Repo PUBLIC  : rien a changer.
   Repo PRIVE   : decommenter le bloc "Repo prive" (secret = PAT GitHub en lecture).
   ============================================================================= */

USE ROLE ACCOUNTADMIN;

-- -----------------------------------------------------------------------------
-- 1. Base ADMIN et schema GIT (meme definition que 01_account.sql)
-- -----------------------------------------------------------------------------
USE ROLE SYSADMIN;
CREATE DATABASE IF NOT EXISTS ADMIN COMMENT = 'Database for administration';
CREATE SCHEMA IF NOT EXISTS ADMIN.GIT WITH MANAGED ACCESS
  COMMENT = 'Git repositories & secrets for CI/CD (dbt project sync)';

-- -----------------------------------------------------------------------------
-- 2. API integration GitHub (objet compte -> ACCOUNTADMIN)
--    Adapter API_ALLOWED_PREFIXES si le repo change d'organisation.
-- -----------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;
CREATE API INTEGRATION IF NOT EXISTS API_GITHUB_FORMATION
  API_PROVIDER = GIT_HTTPS_API
  API_ALLOWED_PREFIXES = ('https://github.com/yoan-amrn')
  -- ALLOWED_AUTHENTICATION_SECRETS = (ADMIN.GIT.SEC_GITHUB_PAT)   -- repo prive
  ENABLED = TRUE
  COMMENT = 'Acces au repo GitHub de formation';
GRANT USAGE ON INTEGRATION API_GITHUB_FORMATION TO ROLE SYSADMIN;

-- --- Repo prive (optionnel) ---------------------------------------------------
-- USE ROLE SYSADMIN;
-- CREATE OR REPLACE SECRET ADMIN.GIT.SEC_GITHUB_PAT
--   TYPE = PASSWORD USERNAME = 'yoan-amrn' PASSWORD = '<github_pat_lecture_seule>';
-- USE ROLE ACCOUNTADMIN;
-- ALTER API INTEGRATION API_GITHUB_FORMATION SET ALLOWED_AUTHENTICATION_SECRETS = (ADMIN.GIT.SEC_GITHUB_PAT);

-- -----------------------------------------------------------------------------
-- 3. Objet GIT REPOSITORY (clone en lecture du repo) + premier FETCH
-- -----------------------------------------------------------------------------
USE ROLE SYSADMIN;
CREATE GIT REPOSITORY IF NOT EXISTS ADMIN.GIT.TRAINING_REPO
  API_INTEGRATION = API_GITHUB_FORMATION
  ORIGIN = 'https://github.com/yoan-amrn/snowflake_dbt_training.git'
  -- GIT_CREDENTIALS = ADMIN.GIT.SEC_GITHUB_PAT                       -- repo prive
  COMMENT = 'Scripts de setup, labs, demos et projet dbt de la formation';

ALTER GIT REPOSITORY ADMIN.GIT.TRAINING_REPO FETCH;
LS @ADMIN.GIT.TRAINING_REPO/branches/main/setup/;

-- -----------------------------------------------------------------------------
-- 4. Etape suivante : deployer tout le socle depuis le repo
--    (ouvrir setup/deploy.sql pour ajuster les parametres si besoin)
--    Le mot de passe initial n'est JAMAIS commite : remplacer <mot_de_passe_initial>
--    dans la worksheet au moment de l'execution (sans sauvegarder), ou lancer le
--    deploy depuis GitHub Actions avec le secret TRAINING_INIT_PWD
--    (voir demos/ci/github_actions_deploy.yml).
-- -----------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;
EXECUTE IMMEDIATE FROM @ADMIN.GIT.TRAINING_REPO/branches/main/setup/deploy.sql
  USING (nb_participants => 10, init_pwd => '<mot_de_passe_initial>', credit_quota => 100);
