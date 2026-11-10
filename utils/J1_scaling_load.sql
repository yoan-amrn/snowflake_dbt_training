/* =============================================================================
   DEMO J1 matin - GENERATEUR DE CHARGE : scale up / scale out / scale in / across
   Compte : TRIAL (Enterprise, multi-cluster) - Role : FORMATION_ADMIN
   Complete demos/J1_warehouses.sql (partie 3) : la concurrence est generee par
   une procedure (async child jobs) au lieu de compter sur les participants.
   Exercice associe : labs/EXO_J1_scaling_enonce.sql (les participants analysent
   la table FORMATION.CURATED.SCALING_QUERIES produite a la fin de ce script).

   Deroule (~20 min, < 0,5 credit) :
     PHASE 1 - 3 lots de requetes sur un warehouse volontairement mal dimensionne
       Lot A : beaucoup de requetes courtes simultanees
       Lot B : une requete lourde seule
       Lot C : requetes lourdes + requetes courtes sur le meme warehouse
     -> snapshot -> les participants diagnostiquent (exercice, questions 1 a 4)
     PHASE 2 - remediation devant le groupe
       Lot A2 : lot A rejoue en multi-cluster (scale out, puis scale in)
       Lot B2 : lot B rejoue en MEDIUM (scale up)
       Lot C2 : lot C rejoue sur deux warehouses separes (across)
     -> snapshot complete -> exercice, question 5 (avant / apres)
   ============================================================================= */

-- =============================================================================
-- 0. Setup (une fois) : warehouse dedie + droits
-- =============================================================================
USE ROLE SYSADMIN;
CREATE WAREHOUSE IF NOT EXISTS WH_SCALING_DEMO
  WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  MIN_CLUSTER_COUNT = 1 MAX_CLUSTER_COUNT = 1 SCALING_POLICY = 'STANDARD'
  COMMENT = 'Demo scaling : generateur de charge';
CREATE WAREHOUSE IF NOT EXISTS WH_SCALING_BI
  WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Demo scaling : warehouse BI separe (lot C2)';
GRANT OWNERSHIP ON WAREHOUSE WH_SCALING_DEMO TO ROLE FORMATION_ADMIN COPY CURRENT GRANTS;
GRANT OWNERSHIP ON WAREHOUSE WH_SCALING_BI   TO ROLE FORMATION_ADMIN COPY CURRENT GRANTS;

USE ROLE FORMATION_ADMIN;
USE SCHEMA FORMATION.CURATED;

-- Un warehouse XS admet ~8 requetes simultanees par defaut avant de mettre en file.
-- On abaisse ce seuil a 2 pour reproduire, avec une seule personne, ce que
-- produiraient des dizaines d'utilisateurs : c'est le seul « artifice » de la demo.
ALTER WAREHOUSE WH_SCALING_DEMO SET MAX_CONCURRENCY_LEVEL = 2;
ALTER WAREHOUSE WH_SCALING_BI   SET MAX_CONCURRENCY_LEVEL = 2;

-- -----------------------------------------------------------------------------
-- Procedure de charge : lance NB_HEAVY requetes lourdes puis NB_SHORT requetes
-- courtes, toutes en parallele (ASYNC), sur le warehouse de la session.
--   LOT      : etiquette du lot (QUERY_TAG = 'scaling:<LOT>')
--   NB_SHORT : requetes courtes (agregat TPC-H Q1 sur SF10, ~10 s sur XS)
--   NB_HEAVY : requetes lourdes (tri complet de LINEITEM SF10 -> spilling sur XS)
-- EXECUTE AS CALLER : les requetes utilisent le warehouse et la session de l'appelant.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE FORMATION.CURATED.SP_SCALING_LOAD(LOT STRING, NB_SHORT INT, NB_HEAVY INT)
  RETURNS STRING
  LANGUAGE SQL
  EXECUTE AS CALLER
AS
$$
DECLARE
  tag STRING DEFAULT 'scaling:' || LOT;
  t0  TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP();
BEGIN
  ALTER SESSION SET USE_CACHED_RESULT = FALSE;
  EXECUTE IMMEDIATE 'ALTER SESSION SET QUERY_TAG = ''' || tag || '''';

  -- Lourdes d'abord : elles prennent les places disponibles sur le warehouse
  FOR i IN 1 TO NB_HEAVY DO
    LET tgt STRING := 'FORMATION.CURATED.SCALING_TMP_' || LOT || '_' || i;
    ASYNC (CREATE OR REPLACE TRANSIENT TABLE IDENTIFIER(:tgt) AS
           SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM
           ORDER BY L_COMMENT, L_ORDERKEY);
  END FOR;

  -- Courtes ensuite : filtre different a chaque requete -> pas de cache de resultats
  FOR i IN 1 TO NB_SHORT DO
    ASYNC (SELECT L_RETURNFLAG, L_LINESTATUS,
                  SUM(L_QUANTITY), SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT)), COUNT(*)
           FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM
           WHERE L_SHIPDATE <= DATEADD(day, -:i, '1998-12-01'::DATE)
           GROUP BY 1, 2);
  END FOR;

  AWAIT ALL;
  ALTER SESSION UNSET QUERY_TAG;
  RETURN 'Lot ' || LOT || ' termine : ' || (NB_SHORT + NB_HEAVY) || ' requetes en '
         || DATEDIFF(second, t0, CURRENT_TIMESTAMP()) || ' s';
END;
$$;

-- =============================================================================
-- PHASE 1 - Le warehouse « mal dimensionne » (XS, 1 cluster)
-- =============================================================================
USE WAREHOUSE WH_SCALING_DEMO;
ALTER WAREHOUSE WH_SCALING_DEMO SET WAREHOUSE_SIZE = XSMALL MIN_CLUSTER_COUNT = 1 MAX_CLUSTER_COUNT = 1;

CALL SP_SCALING_LOAD('A', 16, 0);   -- « rapport du lundi matin » : 16 utilisateurs en meme temps
-- Pendant l'execution : Monitoring > Query History (filtre WH_SCALING_DEMO) -> statut « Queued »

ALTER WAREHOUSE WH_SCALING_DEMO SUSPEND;   -- vide le cache local entre deux lots
CALL SP_SCALING_LOAD('B', 0, 1);    -- « recalcul nocturne » : une seule requete, lourde
-- Pendant l'execution : ouvrir le Query Profile de la requete -> « Bytes spilled »

ALTER WAREHOUSE WH_SCALING_DEMO SUSPEND;
CALL SP_SCALING_LOAD('C', 8, 2);    -- « ETL et BI sur le meme warehouse »

-- -----------------------------------------------------------------------------
-- Snapshot pour l'exercice (relancer apres la phase 2 : il remplace la table)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE FORMATION.CURATED.SCALING_QUERIES AS
SELECT REPLACE(QUERY_TAG, 'scaling:', '')            AS LOT,
       QUERY_ID,
       IFF(QUERY_TYPE = 'CREATE_TABLE_AS_SELECT', 'LOURDE', 'COURTE') AS TYPE_REQUETE,
       WAREHOUSE_NAME, WAREHOUSE_SIZE, CLUSTER_NUMBER,
       START_TIME, END_TIME,
       TOTAL_ELAPSED_TIME   / 1000 AS DUREE_TOTALE_S,
       EXECUTION_TIME       / 1000 AS EXECUTION_S,
       QUEUED_OVERLOAD_TIME / 1000 AS FILE_ATTENTE_S,
       QUEUED_PROVISIONING_TIME / 1000 AS DEMARRAGE_S,
       BYTES_SCANNED,
       NULL::NUMBER AS BYTES_SPILLED_LOCAL,
       NULL::NUMBER AS BYTES_SPILLED_REMOTE
FROM TABLE(FORMATION.INFORMATION_SCHEMA.QUERY_HISTORY_BY_USER(
       USER_NAME => CURRENT_USER(), RESULT_LIMIT => 2000,
       END_TIME_RANGE_START => DATEADD(hour, -8, CURRENT_TIMESTAMP())))
WHERE QUERY_TAG LIKE 'scaling:%'
  AND QUERY_TYPE IN ('SELECT', 'CREATE_TABLE_AS_SELECT')
  AND EXECUTION_STATUS = 'SUCCESS';

-- Spilling : lu dans les statistiques d'operateurs de chaque requete
EXECUTE IMMEDIATE $$
DECLARE
  c CURSOR FOR SELECT QUERY_ID FROM FORMATION.CURATED.SCALING_QUERIES;
BEGIN
  FOR r IN c DO
    LET qid STRING := r.QUERY_ID;
    UPDATE FORMATION.CURATED.SCALING_QUERIES t
    SET BYTES_SPILLED_LOCAL  = s.LOCAL_B,
        BYTES_SPILLED_REMOTE = s.REMOTE_B
    FROM (SELECT COALESCE(SUM(OPERATOR_STATISTICS:spilling:bytes_spilled_local_storage::NUMBER), 0)  AS LOCAL_B,
                 COALESCE(SUM(OPERATOR_STATISTICS:spilling:bytes_spilled_remote_storage::NUMBER), 0) AS REMOTE_B
          FROM TABLE(GET_QUERY_OPERATOR_STATS(:qid))) s
    WHERE t.QUERY_ID = :qid;
  END FOR;
  RETURN 'Spilling renseigne';
END;
$$;

SELECT LOT, TYPE_REQUETE, COUNT(*) AS NB, ROUND(AVG(EXECUTION_S), 1) AS EXEC_MOY_S,
       ROUND(AVG(FILE_ATTENTE_S), 1) AS ATTENTE_MOY_S, MAX(BYTES_SPILLED_LOCAL) AS SPILL_MAX
FROM FORMATION.CURATED.SCALING_QUERIES GROUP BY 1, 2 ORDER BY 1, 2;
-- Attendu : A = attente >> execution ; B = spilling, pas d'attente ;
--           C = les courtes attendent derriere les lourdes.
-- (!) Repetition la veille : si le lot B ne « spille » pas, passer a TPCH_SF100
--     dans la procedure (requete plus longue, ~0,1 credit de plus).

-- >>> Les participants font l'exercice (questions 1 a 4) pendant ~15 min.

-- =============================================================================
-- PHASE 2 - Remediation devant le groupe
-- =============================================================================

-- Lot A2 : SCALE OUT -> multi-cluster (1 a 4 clusters XS)
ALTER WAREHOUSE WH_SCALING_DEMO SET MIN_CLUSTER_COUNT = 1 MAX_CLUSTER_COUNT = 4 SCALING_POLICY = 'STANDARD';
CALL SP_SCALING_LOAD('A2', 16, 0);
-- Pendant et juste apres : observer le SCALE OUT puis le SCALE IN
SHOW WAREHOUSES LIKE 'WH_SCALING_DEMO';
SELECT "name", "started_clusters", "running", "queued" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
-- relancer ces 2 lignes toutes les 30 s : started_clusters redescend a 1 en quelques minutes
-- (scale in automatique), puis le warehouse se suspend apres AUTO_SUSPEND.
SELECT START_TIME, END_TIME, AVG_RUNNING, AVG_QUEUED_LOAD
FROM TABLE(FORMATION.INFORMATION_SCHEMA.WAREHOUSE_LOAD_HISTORY(
       DATE_RANGE_START => DATEADD(hour, -1, CURRENT_TIMESTAMP()),
       WAREHOUSE_NAME => 'WH_SCALING_DEMO'))
ORDER BY START_TIME;

-- Lot B2 : SCALE UP -> MEDIUM, mono-cluster
ALTER WAREHOUSE WH_SCALING_DEMO SUSPEND;
ALTER WAREHOUSE WH_SCALING_DEMO SET WAREHOUSE_SIZE = MEDIUM MAX_CLUSTER_COUNT = 1;
CALL SP_SCALING_LOAD('B2', 0, 1);

-- Lot C2 : ACROSS -> les lourdes sur WH_SCALING_DEMO, les courtes sur WH_SCALING_BI
ALTER WAREHOUSE WH_SCALING_DEMO SUSPEND;
ALTER WAREHOUSE WH_SCALING_DEMO SET WAREHOUSE_SIZE = XSMALL;
EXECUTE IMMEDIATE $$
BEGIN
  USE WAREHOUSE WH_SCALING_DEMO;
  ASYNC (CALL FORMATION.CURATED.SP_SCALING_LOAD('C2', 0, 2));
  USE WAREHOUSE WH_SCALING_BI;
  ASYNC (CALL FORMATION.CURATED.SP_SCALING_LOAD('C2', 8, 0));
  AWAIT ALL;
  RETURN 'Lot C2 termine';
END;
$$;
-- Si l'appel en parallele n'est pas accepte sur le compte : lancer les deux CALL
-- dans deux worksheets differentes, a quelques secondes d'intervalle.

-- Snapshot final : relancer le bloc « Snapshot pour l'exercice » ci-dessus,
-- puis les participants font la question 5 (avant / apres).

-- =============================================================================
-- Remise en etat
-- =============================================================================
ALTER WAREHOUSE WH_SCALING_DEMO SET WAREHOUSE_SIZE = XSMALL MIN_CLUSTER_COUNT = 1 MAX_CLUSTER_COUNT = 1;
ALTER WAREHOUSE WH_SCALING_DEMO SUSPEND;
ALTER WAREHOUSE WH_SCALING_BI   SUSPEND;
EXECUTE IMMEDIATE $$
DECLARE
  c CURSOR FOR SELECT TABLE_NAME FROM FORMATION.INFORMATION_SCHEMA.TABLES
               WHERE TABLE_SCHEMA = 'CURATED' AND TABLE_NAME LIKE 'SCALING_TMP_%';
BEGIN
  FOR r IN c DO
    LET t STRING := 'FORMATION.CURATED.' || r.TABLE_NAME;
    DROP TABLE IF EXISTS IDENTIFIER(:t);
  END FOR;
  RETURN 'Tables temporaires supprimees';
END;
$$;
-- La table SCALING_QUERIES est conservee : elle resservira en FinOps (J1 apres-midi).
