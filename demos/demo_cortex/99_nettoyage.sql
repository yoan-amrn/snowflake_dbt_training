-- =====================================================================
-- DEMO CORTEX AGENT - Nettoyage de la démo
-- Supprime uniquement les schémas créés dans DB_YAR
-- (la base DB_YAR et le warehouse COMPUTE_WH sont conservés)
-- =====================================================================
USE ROLE SYSADMIN;

DROP SCHEMA IF EXISTS DB_YAR.APPS;         -- app Streamlit + stage
-- (optionnel, ACCOUNTADMIN) DROP INTEGRATION IF EXISTS PYPI_ACCESS_INTEGRATION;
DROP SCHEMA IF EXISTS DB_YAR.AGENTS;      -- contient l'agent AGENT_PANNES_RESEAU_LYON
DROP SCHEMA IF EXISTS DB_YAR.MAINTENANCE;  -- tables + semantic view
