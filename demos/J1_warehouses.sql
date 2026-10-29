/* =============================================================================
   DEMO J1 matin - VIRTUAL WAREHOUSES : tailles, multi-cluster, types, usages
   Compte : TRIAL (edition Enterprise requise pour le multi-cluster)
   Role   : FORMATION_ADMIN - Warehouse : WH_PERF_DEMO
   Cout   : < 0,5 credit
   ============================================================================= */

USE ROLE FORMATION_ADMIN;
USE WAREHOUSE WH_PERF_DEMO;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- -----------------------------------------------------------------------------
-- 1. Un warehouse = du compute, independant du stockage
-- -----------------------------------------------------------------------------
SHOW WAREHOUSES;
SELECT "name", "size", "state", "auto_suspend", "min_cluster_count", "max_cluster_count", "type"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
-- XS=1, S=2, M=4, L=8, XL=16 ... credits/heure, facture a la seconde (minimum 60 s par reprise)

-- -----------------------------------------------------------------------------
-- 2. Scale up : meme requete, deux tailles (montrer le Query Profile)
-- -----------------------------------------------------------------------------
ALTER WAREHOUSE WH_PERF_DEMO SET WAREHOUSE_SIZE = XSMALL;
SELECT L_RETURNFLAG, COUNT(*), SUM(L_EXTENDEDPRICE)
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM GROUP BY 1;

ALTER WAREHOUSE WH_PERF_DEMO SET WAREHOUSE_SIZE = MEDIUM;
SELECT L_RETURNFLAG, COUNT(*), SUM(L_EXTENDEDPRICE)
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM GROUP BY 1;
-- ~4x plus rapide pour ~4x le prix horaire -> cout comparable, latence divisee
ALTER WAREHOUSE WH_PERF_DEMO SET WAREHOUSE_SIZE = SMALL;

-- -----------------------------------------------------------------------------
-- 3. Scale out : multi-cluster pour la concurrence (pas pour la vitesse)
-- -----------------------------------------------------------------------------
ALTER WAREHOUSE WH_PERF_DEMO SET
  MIN_CLUSTER_COUNT = 1
  MAX_CLUSTER_COUNT = 3
  SCALING_POLICY = 'STANDARD';      -- ECONOMY : attend ~6 min de file avant d'ajouter un cluster
SHOW WAREHOUSES LIKE 'WH_PERF_DEMO';
-- Demo live : demander aux participants de lancer la requete du point 2 en meme temps
-- sur WH_PERF_DEMO (USE WAREHOUSE WH_PERF_DEMO a leur accorder), puis montrer
-- "started_clusters" et la file d'attente dans Monitoring > Query History.
SELECT START_TIME, WAREHOUSE_NAME, AVG_RUNNING, AVG_QUEUED_LOAD
FROM TABLE(INFORMATION_SCHEMA.WAREHOUSE_LOAD_HISTORY(
       DATE_RANGE_START => DATEADD(hour, -1, CURRENT_TIMESTAMP()),
       WAREHOUSE_NAME   => 'WH_PERF_DEMO'));
ALTER WAREHOUSE WH_PERF_DEMO SET MAX_CLUSTER_COUNT = 1;

-- -----------------------------------------------------------------------------
-- 4. Query Acceleration Service : renfort serverless ponctuel pour les gros scans
-- -----------------------------------------------------------------------------
ALTER WAREHOUSE WH_PERF_DEMO SET ENABLE_QUERY_ACCELERATION = TRUE QUERY_ACCELERATION_MAX_SCALE_FACTOR = 4;
SELECT SYSTEM$ESTIMATE_QUERY_ACCELERATION(LAST_QUERY_ID());
ALTER WAREHOUSE WH_PERF_DEMO SET ENABLE_QUERY_ACCELERATION = FALSE;

-- -----------------------------------------------------------------------------
-- 5. Types de warehouses (DDL montre, non execute : tailles minimales couteuses)
-- -----------------------------------------------------------------------------
-- Snowpark-optimized : 16x memoire par noeud (ML, UDF Python gourmandes), a partir de MEDIUM
-- CREATE WAREHOUSE WH_SNOWPARK WAREHOUSE_SIZE = MEDIUM WAREHOUSE_TYPE = 'SNOWPARK-OPTIMIZED';
-- Gen2 : nouvelle generation de hardware (DML / MERGE plus rapides)
-- CREATE WAREHOUSE WH_GEN2 WAREHOUSE_SIZE = XSMALL RESOURCE_CONSTRAINT = STANDARD_GEN_2;
-- Adaptive / interactive warehouses : selon disponibilite de la region.

-- -----------------------------------------------------------------------------
-- 6. Strategies d'usage (a commenter)
-- - 1 warehouse par usage (ELT, BI, data science, formateur) -> isolation + FinOps
--   (ici : 1 WH_Pxx par participant = attribution des couts par personne)
-- - AUTO_SUSPEND court (60 s) pour l'ad hoc, plus long pour la BI (cache SSD conserve)
-- - Resource monitor par warehouse critique, budgets pour le serverless
-- -----------------------------------------------------------------------------
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
ALTER WAREHOUSE WH_PERF_DEMO SUSPEND;
