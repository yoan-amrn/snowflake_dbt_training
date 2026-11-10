-- =====================================================================
-- DEMO CORTEX AGENT - Analyse des pannes réseau Métro / Tram (Lyon)
-- 07 - APP STREAMLIT "Cockpit fiabilité réseau" (runtime conteneur)
-- ---------------------------------------------------------------------
-- Projet Snowflake CLI dans le dossier streamlit/ :
--   streamlit/
--   ├── .streamlit/config.toml   thème et options Streamlit
--   ├── pyproject.toml           dépendances Python (installées depuis PyPI)
--   ├── snowflake.yml            définition du déploiement
--   └── streamlit_app.py         application
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. PRE-REQUIS (une seule fois, ACCOUNTADMIN)
--    - accès PyPI pour installer les dépendances du pyproject.toml
--    - droit d'utiliser le compute pool du conteneur
-- ---------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

CREATE EXTERNAL ACCESS INTEGRATION IF NOT EXISTS PYPI_ACCESS_INTEGRATION
  ALLOWED_NETWORK_RULES = (SNOWFLAKE.EXTERNAL_ACCESS.PYPI_RULE)
  ENABLED = TRUE
  COMMENT = 'Accès PyPI pour les apps Streamlit en runtime conteneur';
GRANT USAGE ON INTEGRATION PYPI_ACCESS_INTEGRATION TO ROLE SYSADMIN;

-- Compute pool : celui par défaut du compte (ou en créer un dédié, cf. ci-dessous)
SHOW COMPUTE POOLS;
GRANT USAGE ON COMPUTE POOL SYSTEM_COMPUTE_POOL_CPU TO ROLE SYSADMIN;
-- CREATE COMPUTE POOL IF NOT EXISTS STREAMLIT_POOL
--   MIN_NODES = 1 MAX_NODES = 1 INSTANCE_FAMILY = CPU_X64_XS AUTO_SUSPEND_SECS = 600;
-- GRANT USAGE, MONITOR ON COMPUTE POOL STREAMLIT_POOL TO ROLE SYSADMIN;
-- (penser alors à modifier compute_pool dans streamlit/snowflake.yml)

-- ---------------------------------------------------------------------
-- 1. Schéma de l'app
-- ---------------------------------------------------------------------
USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;

CREATE SCHEMA IF NOT EXISTS DB_YAR.APPS
  COMMENT = 'Démo Cortex Agent - applications Streamlit';

-- ---------------------------------------------------------------------
-- 2. Déploiement avec Snowflake CLI (recommandé), depuis le dossier streamlit/ :
--
--      cd streamlit
--      snow streamlit deploy --replace --connection <ma_connexion>
--      snow streamlit get-url cockpit_pannes_reseau --open
--
--    La connexion doit utiliser le rôle SYSADMIN.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- 3. Alternative 100 % SQL : déposer les 4 fichiers (en conservant le
--    dossier .streamlit/) dans un stage, puis créer l'app.
-- ---------------------------------------------------------------------
-- CREATE STAGE IF NOT EXISTS DB_YAR.APPS.STREAMLIT_STAGE DIRECTORY = (ENABLE = TRUE);
-- PUT file://streamlit/streamlit_app.py        @DB_YAR.APPS.STREAMLIT_STAGE/cockpit_pannes            AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
-- PUT file://streamlit/pyproject.toml          @DB_YAR.APPS.STREAMLIT_STAGE/cockpit_pannes            AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
-- PUT file://streamlit/.streamlit/config.toml  @DB_YAR.APPS.STREAMLIT_STAGE/cockpit_pannes/.streamlit AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
--
-- CREATE OR REPLACE STREAMLIT DB_YAR.APPS.COCKPIT_PANNES_RESEAU
--   FROM '@DB_YAR.APPS.STREAMLIT_STAGE/cockpit_pannes'
--   MAIN_FILE = 'streamlit_app.py'
--   QUERY_WAREHOUSE = COMPUTE_WH
--   RUNTIME_NAME = 'SYSTEM$ST_CONTAINER_RUNTIME_PY3_11'
--   COMPUTE_POOL = SYSTEM_COMPUTE_POOL_CPU
--   EXTERNAL_ACCESS_INTEGRATIONS = (PYPI_ACCESS_INTEGRATION)
--   TITLE = 'Cockpit fiabilité réseau Lyon';

-- Vérification
SHOW STREAMLITS IN SCHEMA DB_YAR.APPS;
