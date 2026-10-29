/* =============================================================================
   DEMO J1 apres-midi - MONITORING & FINOPS
   Compte : TRIAL - Role : ACCOUNTADMIN (ou FORMATION_PARTICIPANT pour les vues
   ACCOUNT_USAGE : USAGE_VIEWER / GOVERNANCE_VIEWER accordes par 02_formation_schemas.sql)
   (!) ACCOUNT_USAGE : latence 45 min a 3 h, retention 1 an.
       INFORMATION_SCHEMA : temps reel, retention 7 a 14 jours, perimetre base courante.
   ============================================================================= */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WH_ADMIN;

-- -----------------------------------------------------------------------------
-- 1. Query History : qui consomme quoi ?
-- -----------------------------------------------------------------------------
-- Temps reel (INFORMATION_SCHEMA)
SELECT USER_NAME, WAREHOUSE_NAME, EXECUTION_STATUS,
       TOTAL_ELAPSED_TIME / 1000 AS DUREE_S, BYTES_SCANNED / POWER(1024, 3) AS GO_SCANNES,
       LEFT(QUERY_TEXT, 80) AS REQUETE
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY(RESULT_LIMIT => 100))
ORDER BY START_TIME DESC;

-- Historique (ACCOUNT_USAGE) : top 10 des requetes les plus longues sur 7 jours
SELECT QUERY_ID, USER_NAME, WAREHOUSE_NAME, WAREHOUSE_SIZE,
       TOTAL_ELAPSED_TIME / 1000 AS DUREE_S,
       BYTES_SPILLED_TO_LOCAL_STORAGE + BYTES_SPILLED_TO_REMOTE_STORAGE AS SPILL_OCTETS,
       PARTITIONS_SCANNED, PARTITIONS_TOTAL
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP())
ORDER BY TOTAL_ELAPSED_TIME DESC
LIMIT 10;

-- Cout attribue par requete (credits compute)
SELECT USER_NAME, WAREHOUSE_NAME, ROUND(SUM(CREDITS_ATTRIBUTED_COMPUTE), 3) AS CREDITS
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
WHERE START_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY 1, 2 ORDER BY 3 DESC;

-- -----------------------------------------------------------------------------
-- 2. Consommation par warehouse = par participant (1 WH_Pxx chacun)
-- -----------------------------------------------------------------------------
SELECT WAREHOUSE_NAME, ROUND(SUM(CREDITS_USED), 3) AS CREDITS,
       ROUND(SUM(CREDITS_USED_CLOUD_SERVICES), 3) AS CREDITS_CLOUD_SERVICES
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE START_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY 1 ORDER BY 2 DESC;

-- Vue d'ensemble par service (warehouses, serverless tasks, SOS, clustering, Cortex...)
SELECT USAGE_DATE, SERVICE_TYPE, ROUND(SUM(CREDITS_BILLED), 3) AS CREDITS
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
WHERE USAGE_DATE >= DATEADD(day, -7, CURRENT_DATE())
GROUP BY 1, 2 ORDER BY 1 DESC, 3 DESC;

-- Cortex : cout des fonctions IA (LAB 3)
SELECT FUNCTION_NAME, MODEL_NAME, SUM(TOKENS) AS TOKENS, ROUND(SUM(TOKEN_CREDITS), 4) AS CREDITS
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FUNCTIONS_USAGE_HISTORY
GROUP BY 1, 2 ORDER BY 4 DESC;

-- Stockage (base par base, time travel et fail-safe inclus)
SELECT DATABASE_NAME, ROUND(AVG(AVERAGE_DATABASE_BYTES) / POWER(1024, 3), 2) AS GO,
       ROUND(AVG(AVERAGE_FAILSAFE_BYTES) / POWER(1024, 3), 2) AS GO_FAILSAFE
FROM SNOWFLAKE.ACCOUNT_USAGE.DATABASE_STORAGE_USAGE_HISTORY
WHERE USAGE_DATE >= DATEADD(day, -7, CURRENT_DATE())
GROUP BY 1 ORDER BY 2 DESC;

-- -----------------------------------------------------------------------------
-- 3. Garde-fous
-- -----------------------------------------------------------------------------
-- Resource monitor compte (setup/06_finops.sql) : warehouses uniquement
SHOW RESOURCE MONITORS;

-- Resource monitor dedie a un warehouse
CREATE OR REPLACE RESOURCE MONITOR RM_PERF_DEMO WITH CREDIT_QUOTA = 5
  TRIGGERS ON 80 PERCENT DO NOTIFY ON 100 PERCENT DO SUSPEND;
ALTER WAREHOUSE WH_PERF_DEMO SET RESOURCE_MONITOR = RM_PERF_DEMO;

-- Budgets : couvrent aussi le serverless (selon disponibilite sur le compte)
-- CALL SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET!ACTIVATE();
-- CALL SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET!SET_SPENDING_LIMIT(100);
-- UI : Admin > Cost Management > Budgets

-- Timeouts : eviter les requetes qui tournent des heures
ALTER WAREHOUSE WH_PERF_DEMO SET STATEMENT_TIMEOUT_IN_SECONDS = 600;

-- -----------------------------------------------------------------------------
-- 4. Leviers d'optimisation des couts (a commenter)
-- - AUTO_SUSPEND court, warehouses dimensionnes par usage, pas de "gros WH partage"
-- - Tags d'objets (COST_CENTER) + QUERY_TAG pour attribuer les couts
-- - Surveiller le spilling (-> scale up) et la file d'attente (-> multi-cluster)
-- - Serverless (tasks, SOS, clustering, DT) : suivre *_HISTORY, suspendre hors usage
-- - Cloud services factures seulement au-dela de 10 % du compute journalier
-- -----------------------------------------------------------------------------
ALTER SESSION SET QUERY_TAG = 'formation:demo_finops';
