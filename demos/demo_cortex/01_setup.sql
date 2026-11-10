-- =====================================================================
-- DEMO CORTEX AGENT - Analyse des pannes réseau Métro / Tram (Lyon)
-- 01 - SETUP : création des schémas dans la base existante DB_YAR
-- ---------------------------------------------------------------------
-- Pré-requis (déjà existants) :
--   - base DB_YAR, propriété du rôle SYSADMIN
--   - warehouse COMPUTE_WH
-- Aucun autre objet de niveau compte n'est créé.
-- =====================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE DB_YAR;

-- Données de maintenance + semantic view
CREATE SCHEMA IF NOT EXISTS DB_YAR.MAINTENANCE
  COMMENT = 'Démo Cortex Agent - pannes réseau métro / tram Lyon : lignes, stations, équipements, incidents, interventions (données fictives)';

-- Agent Cortex
CREATE SCHEMA IF NOT EXISTS DB_YAR.AGENTS
  COMMENT = 'Démo Cortex Agent - agents Cortex';

USE SCHEMA DB_YAR.MAINTENANCE;

-- ---------------------------------------------------------------------
-- Vérification des droits Cortex
-- Par défaut, le rôle de base SNOWFLAKE.CORTEX_USER est accordé à PUBLIC.
-- Si ce n'est pas le cas sur le compte, exécuter en ACCOUNTADMIN :
--   GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE SYSADMIN;
-- Si les modèles LLM ne sont pas disponibles dans la région du compte :
--   ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';
-- ---------------------------------------------------------------------
SHOW GRANTS OF DATABASE ROLE SNOWFLAKE.CORTEX_USER;
