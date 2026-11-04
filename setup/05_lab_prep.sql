/* =============================================================================
   05 - PREPARATION FORMATEUR DES LABS (a lancer la veille, apres deploy.sql)
   Lance a part (pas dans deploy.sql) car il consomme des credits :
     EXECUTE IMMEDIATE FROM @ADMIN.GIT.TRAINING_REPO/branches/main/setup/05_lab_prep.sql;
   - tables volumineuses pour le LAB 3 (clustering, Search Optimization)
   Cout estime : ~3-5 credits (CTAS sur warehouse LARGE + build SOS serverless)
   ============================================================================= */

USE ROLE FORMATION_ADMIN;

-- -----------------------------------------------------------------------------
-- 1. LAB 3 : tables de performance (TPCH SF10)
-- -----------------------------------------------------------------------------
ALTER WAREHOUSE WH_ADMIN SET WAREHOUSE_SIZE = LARGE;
USE WAREHOUSE WH_ADMIN;
USE SCHEMA FORMATION.CURATED;

-- 1a. LINEITEM 60 M lignes dans l'ordre "naturel" (~ ordre de L_ORDERKEY)
--     -> L_SHIPDATE est dispersee dans toutes les micro-partitions
CREATE OR REPLACE TABLE LINEITEM_UNSORTED AS
SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM;

-- 1b. Meme contenu, trie a l'ecriture sur L_SHIPDATE + cle de clustering declaree
CREATE OR REPLACE TABLE LINEITEM_BY_SHIPDATE
  CLUSTER BY (L_SHIPDATE) AS
SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM
ORDER BY L_SHIPDATE;
-- Table deja triee : on evite que l'Automatic Clustering consomme pendant la formation
ALTER TABLE LINEITEM_BY_SHIPDATE SUSPEND RECLUSTER;

-- 1c. ORDERS 15 M lignes : lookup ponctuel sur O_CUSTKEY (valeur dispersee)
CREATE OR REPLACE TABLE ORDERS_SF10 AS
SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS;

CREATE OR REPLACE TABLE ORDERS_SF10_SOS AS
SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS;
ALTER TABLE ORDERS_SF10_SOS ADD SEARCH OPTIMIZATION ON EQUALITY(O_CUSTKEY), SUBSTRING(O_COMMENT);

ALTER WAREHOUSE WH_ADMIN SET WAREHOUSE_SIZE = XSMALL;

-- Le build SOS est asynchrone : attendre search_optimization_progress = 100
SHOW TABLES LIKE 'ORDERS_SF10_SOS' IN SCHEMA FORMATION.CURATED;
SELECT "name", "search_optimization", "search_optimization_progress"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- Lecture participants : portee par _FORMATION_CURATED_SR (future grants) ; filet de securite :
USE ROLE SECURITYADMIN;
GRANT SELECT ON ALL TABLES IN SCHEMA FORMATION.CURATED TO ROLE _FORMATION_CURATED_SR;
USE ROLE FORMATION_ADMIN;
-- (Cortex AI absent du trial : plus de verification ici, voir demos/J2_cortex_search_analyst_agent.sql)
