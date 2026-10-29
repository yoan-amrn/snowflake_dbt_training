/* =============================================================================
   DEMO J2 matin - DBT PROJECTS ON SNOWFLAKE (complement Streams & Tasks)
   Compte : TRIAL (ou PAID) - Role : FORMATION_ADMIN - Warehouse : WH_ADMIN
   Projet : dossier dbt/ du repo (staging sur TPCH_SF1 + mart fct_revenue_by_nation)
   Cible  : FORMATION.DBT (profiles.yml), cree par 02_formation_schemas.sql
   ============================================================================= */

USE ROLE FORMATION_ADMIN;
USE WAREHOUSE WH_ADMIN;
ALTER GIT REPOSITORY ADMIN.GIT.TRAINING_REPO FETCH;
LS @ADMIN.GIT.TRAINING_REPO/branches/main/dbt/;

-- -----------------------------------------------------------------------------
-- 1. Deployer le projet depuis Git (objet DBT PROJECT versionne)
--    Pas de dbt deps ici (aucun package) -> pas besoin d'EXTERNAL_ACCESS_INTEGRATIONS.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE DBT PROJECT FORMATION.DBT.DBT_TPCH
  FROM '@ADMIN.GIT.TRAINING_REPO/branches/main/dbt'
  DEFAULT_TARGET = 'dev'
  COMMENT = 'Projet dbt de formation (TPCH)';

SHOW DBT PROJECTS IN SCHEMA FORMATION.DBT;

-- -----------------------------------------------------------------------------
-- 2. Executer : build = run + test
-- -----------------------------------------------------------------------------
EXECUTE DBT PROJECT FORMATION.DBT.DBT_TPCH ARGS = 'build --target dev';

SELECT * FROM FORMATION.DBT.FCT_REVENUE_BY_NATION ORDER BY REVENUE DESC LIMIT 10;
-- Logs et artefacts (manifest, run_results) : Snowsight > Monitoring > dbt projects

-- -----------------------------------------------------------------------------
-- 3. Orchestrer
-- -----------------------------------------------------------------------------
-- a) Natif : une task (serverless) apres l'arrivee des donnees
--    Schema MANAGED ACCESS : la task appartiendra a _FORMATION_DBT_SFULL (future grants),
--    qui doit pouvoir utiliser le projet.
USE ROLE SECURITYADMIN;
GRANT USAGE ON DBT PROJECT FORMATION.DBT.DBT_TPCH TO ROLE _FORMATION_DBT_SFULL;
USE ROLE FORMATION_ADMIN;
CREATE OR REPLACE TASK FORMATION.DBT.T_DBT_BUILD
  USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
  SCHEDULE = 'USING CRON 0 6 * * * Europe/Paris'
AS
  EXECUTE DBT PROJECT FORMATION.DBT.DBT_TPCH ARGS = 'build --target dev';
-- (laissee suspendue) EXECUTE TASK FORMATION.DBT.T_DBT_BUILD;

-- b) Airflow (MWAA) : Airflow orchestre le cross-systeme, Snowflake execute
--    SQLExecuteQueryOperator(
--        task_id="dbt_build", conn_id="snowflake_default",
--        sql="EXECUTE DBT PROJECT FORMATION.DBT.DBT_TPCH ARGS = 'build --target dev'")
--    -> plus besoin d'un worker dbt / d'un conteneur cote Airflow.

-- -----------------------------------------------------------------------------
-- 4. Cycle de dev : Workspaces Snowsight (editer, compiler, voir le DAG, commit/push)
--    puis ALTER GIT REPOSITORY ... FETCH + nouvelle version :
-- ALTER DBT PROJECT FORMATION.DBT.DBT_TPCH ADD VERSION
--   FROM '@ADMIN.GIT.TRAINING_REPO/branches/main/dbt';
-- -----------------------------------------------------------------------------

-- Nettoyage
-- DROP TASK FORMATION.DBT.T_DBT_BUILD;
-- DROP DBT PROJECT FORMATION.DBT.DBT_TPCH;
