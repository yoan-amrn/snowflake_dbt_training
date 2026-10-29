/* =============================================================================
   LAB 2 - INGESTION : FORMATS & STAGES - ICEBERG - STREAMS & TASKS - DYNAMIC TABLES
   (J2 matin, ~1h45)
   Jeu de donnees : fichiers CSV/JSON/Parquet du stage FORMATION.COMMON.STG_FILES
                    (generes depuis TPCH), TPCH_SF1.ORDERS (commandes 1998)
   Hors lab (demos formateur) : Snowpipe auto-ingest / Openflow, External Access
   Integration & Secrets, dbt Projects -> dossier demos/
   (!) Fin de lab : SUSPENDRE vos tasks et dynamic tables (dernier bloc).
   ============================================================================= */

-- =============================================================================
-- Contexte de session
-- =============================================================================
SET me        = CURRENT_USER();
SET my_role   = 'R_' || $me;
SET my_wh     = 'WH_' || $me;
SET my_schema = 'SANDBOX.' || $me;

USE ROLE      IDENTIFIER($my_role);
USE WAREHOUSE IDENTIFIER($my_wh);
USE SCHEMA    IDENTIFIER($my_schema);

-- =============================================================================
-- Exercice 1 - Formats & Stages : charger des fichiers (30 min)
-- Le stage interne partage FORMATION.COMMON.STG_FILES contient sous samples/ :
--   orders_csv/ (CSV gzip, entete), orders_csv_errors/ (CSV avec erreurs),
--   orders_json/ (1 commande par document, lignes imbriquees), orders_parquet/
-- File formats partages : FORMATION.COMMON.FF_CSV, FF_CSV_PARSE_HEADER, FF_JSON, FF_PARQUET
-- 1. Listez le contenu du stage (LIST et DIRECTORY()).
-- 2. Interrogez directement les fichiers CSV SANS les charger ($1, $2... et
--    METADATA$FILENAME). Quel interet ?
-- 3. Creez ORDERS_CSV (O_ORDERKEY, O_CUSTKEY, O_ORDERSTATUS, O_TOTALPRICE NUMBER(12,2),
--    O_ORDERDATE DATE, O_ORDERPRIORITY) et chargez orders_csv/ par COPY INTO.
--    Relancez le meme COPY : combien de fichiers charges ? Pourquoi ?
-- 4. Fichier en erreur (orders_csv_errors/) :
--    a) testez-le avec VALIDATION_MODE = RETURN_ERRORS ;
--    b) chargez-le avec ON_ERROR = CONTINUE ;
--    c) retrouvez les lignes rejetees (VALIDATE) et l'historique (COPY_HISTORY).
-- 5. Parquet : decouvrez le schema avec INFER_SCHEMA, creez ORDERS_PARQUET avec
--    USING TEMPLATE, chargez avec MATCH_BY_COLUMN_NAME.
-- 6. JSON : chargez orders_json/ dans ORDERS_JSON (V VARIANT, FILE_NAME STRING),
--    puis calculez la quantite totale par segment client (LATERAL FLATTEN sur V:lines).
-- Bonus : Snowsight > Ingestion > Add data > Load files into a stage : deposez
--    votre propre fichier dans un stage STG_MOI de votre schema et chargez-le.
-- =============================================================================
-- >>> SOLUTION
LIST @FORMATION.COMMON.STG_FILES/samples/;
SELECT RELATIVE_PATH, SIZE, LAST_MODIFIED FROM DIRECTORY(@FORMATION.COMMON.STG_FILES) ORDER BY 1;

-- 2. Requete directe sur les fichiers (exploration avant chargement, controle qualite)
SELECT METADATA$FILENAME AS FICHIER, METADATA$FILE_ROW_NUMBER AS LIGNE,
       $1 AS O_ORDERKEY, $4 AS O_TOTALPRICE, $5 AS O_ORDERDATE
FROM @FORMATION.COMMON.STG_FILES/samples/orders_csv/ (FILE_FORMAT => 'FORMATION.COMMON.FF_CSV')
LIMIT 10;

-- 3. Chargement CSV
CREATE OR REPLACE TABLE ORDERS_CSV (
  O_ORDERKEY NUMBER(38,0), O_CUSTKEY NUMBER(38,0), O_ORDERSTATUS STRING,
  O_TOTALPRICE NUMBER(12,2), O_ORDERDATE DATE, O_ORDERPRIORITY STRING
);
COPY INTO ORDERS_CSV
FROM @FORMATION.COMMON.STG_FILES/samples/orders_csv/
FILE_FORMAT = (FORMAT_NAME = 'FORMATION.COMMON.FF_CSV');
-- 2e execution : "Copy executed with 0 files processed" -> les metadonnees de
-- chargement (64 jours) evitent les doublons ; FORCE = TRUE pour recharger.
COPY INTO ORDERS_CSV
FROM @FORMATION.COMMON.STG_FILES/samples/orders_csv/
FILE_FORMAT = (FORMAT_NAME = 'FORMATION.COMMON.FF_CSV');

-- 4. Gestion des erreurs
COPY INTO ORDERS_CSV
FROM @FORMATION.COMMON.STG_FILES/samples/orders_csv_errors/
FILE_FORMAT = (FORMAT_NAME = 'FORMATION.COMMON.FF_CSV')
VALIDATION_MODE = RETURN_ERRORS;          -- rien n'est charge, liste des erreurs

COPY INTO ORDERS_CSV
FROM @FORMATION.COMMON.STG_FILES/samples/orders_csv_errors/
FILE_FORMAT = (FORMAT_NAME = 'FORMATION.COMMON.FF_CSV')
ON_ERROR = CONTINUE;                      -- status PARTIALLY_LOADED

SELECT * FROM TABLE(VALIDATE(ORDERS_CSV, JOB_ID => '_last'));

SELECT FILE_NAME, STATUS, ROW_COUNT, ROW_PARSED, ERROR_COUNT, FIRST_ERROR_MESSAGE
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
       TABLE_NAME => 'ORDERS_CSV', START_TIME => DATEADD(hour, -1, CURRENT_TIMESTAMP())));

-- 5. Parquet : schema auto-decouvert
SELECT COLUMN_NAME, TYPE, NULLABLE
FROM TABLE(INFER_SCHEMA(
       LOCATION    => '@FORMATION.COMMON.STG_FILES/samples/orders_parquet/',
       FILE_FORMAT => 'FORMATION.COMMON.FF_PARQUET'));

CREATE OR REPLACE TABLE ORDERS_PARQUET USING TEMPLATE (
  SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*)) WITHIN GROUP (ORDER BY ORDER_ID)
  FROM TABLE(INFER_SCHEMA(
         LOCATION    => '@FORMATION.COMMON.STG_FILES/samples/orders_parquet/',
         FILE_FORMAT => 'FORMATION.COMMON.FF_PARQUET'))
);
COPY INTO ORDERS_PARQUET
FROM @FORMATION.COMMON.STG_FILES/samples/orders_parquet/
FILE_FORMAT = (FORMAT_NAME = 'FORMATION.COMMON.FF_PARQUET')
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;
SELECT COUNT(*) FROM ORDERS_PARQUET;

-- 6. JSON semi-structure
CREATE OR REPLACE TABLE ORDERS_JSON (V VARIANT, FILE_NAME STRING);
COPY INTO ORDERS_JSON
FROM (SELECT $1, METADATA$FILENAME FROM @FORMATION.COMMON.STG_FILES/samples/orders_json/)
FILE_FORMAT = (FORMAT_NAME = 'FORMATION.COMMON.FF_JSON');

SELECT V:customer.segment::STRING   AS SEGMENT,
       COUNT(DISTINCT V:order_key)   AS NB_COMMANDES,
       SUM(l.value:quantity::NUMBER) AS QTE_TOTALE
FROM ORDERS_JSON, LATERAL FLATTEN(INPUT => V:lines) l
GROUP BY 1 ORDER BY 3 DESC;

-- Reponses :
-- - Requete directe = explorer / controler un fichier avant de le charger.
-- - Stage interne (stockage Snowflake) vs externe (S3/ADLS/GCS via STORAGE INTEGRATION) :
--   meme syntaxe COPY / requete directe, seule la definition du stage change.
-- - COPY INTO = chargement batch sur warehouse ; Snowpipe = meme COPY, declenche par
--   evenement et serverless (demo formateur).
-- - VARIANT : le JSON est stocke en colonnes internes -> requetes rapides avec ':' et FLATTEN.
-- <<< SOLUTION

-- =============================================================================
-- Exercice 2 - Tables Iceberg managees par Snowflake (15 min)
-- (!) Si le compte refuse EXTERNAL_VOLUME = SNOWFLAKE_MANAGED : demo formateur.
-- 1. Creez la table Iceberg ORDERS_ICEBERG (memes colonnes que ORDERS_CSV),
--    catalogue Snowflake, stockage Snowflake (pas de bucket S3), BASE_LOCATION 'orders_iceberg'.
-- 2. Alimentez-la depuis ORDERS_CSV, puis faites un UPDATE.
-- 3. Recuperez l'emplacement des metadonnees Iceberg (SYSTEM$GET_ICEBERG_TABLE_INFORMATION).
-- 4. Interrogez la table telle qu'elle etait avant l'UPDATE (time travel).
-- Question : qu'apporte Iceberg par rapport a une table Snowflake standard ?
-- =============================================================================
-- >>> SOLUTION
CREATE OR REPLACE ICEBERG TABLE ORDERS_ICEBERG (
  O_ORDERKEY NUMBER(38,0), O_CUSTKEY NUMBER(38,0), O_ORDERSTATUS STRING,
  O_TOTALPRICE NUMBER(12,2), O_ORDERDATE DATE, O_ORDERPRIORITY STRING
)
  CATALOG = 'SNOWFLAKE'
  EXTERNAL_VOLUME = SNOWFLAKE_MANAGED
  BASE_LOCATION = 'orders_iceberg';

INSERT INTO ORDERS_ICEBERG SELECT * FROM ORDERS_CSV;
SET avant_update = CURRENT_TIMESTAMP();
UPDATE ORDERS_ICEBERG SET O_ORDERSTATUS = 'X' WHERE O_ORDERPRIORITY = '1-URGENT';

SELECT SYSTEM$GET_ICEBERG_TABLE_INFORMATION('ORDERS_ICEBERG');   -- metadataLocation : fichier metadata.json

SELECT O_ORDERSTATUS, COUNT(*) FROM ORDERS_ICEBERG GROUP BY 1;
SELECT O_ORDERSTATUS, COUNT(*) FROM ORDERS_ICEBERG AT (TIMESTAMP => $avant_update::TIMESTAMP_LTZ) GROUP BY 1;

SHOW ICEBERG TABLES LIKE 'ORDERS_ICEBERG';

-- Reponses :
-- - Format ouvert (Parquet + metadonnees Iceberg) : d'autres moteurs (Spark, Trino,
--   Athena, DuckDB...) lisent les memes donnees via le catalogue Iceberg REST
--   (Horizon Catalog / Snowflake Open Catalog) -> pas de copie, pas de lock-in.
-- - En production : EXTERNAL VOLUME sur le bucket du client (donnees chez lui).
-- - Catalogue externe (Glue, Open Catalog) : Snowflake lit des tables gerees ailleurs.
-- <<< SOLUTION

-- =============================================================================
-- Exercice 3 - Source et cible (5 min)
-- 1. ORDERS_SRC : commandes TPCH_SF1 de 1998 (O_ORDERDATE >= '1998-01-01').
-- 2. ORDERS_TGT : meme structure + colonne UPDATED_AT TIMESTAMP_LTZ,
--    chargee avec le contenu initial de ORDERS_SRC.
-- =============================================================================
-- >>> SOLUTION
CREATE OR REPLACE TABLE ORDERS_SRC AS
SELECT O_ORDERKEY, O_CUSTKEY, O_ORDERSTATUS, O_TOTALPRICE, O_ORDERDATE, O_ORDERPRIORITY
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_ORDERDATE >= '1998-01-01';

CREATE OR REPLACE TABLE ORDERS_TGT AS
SELECT *, CURRENT_TIMESTAMP()::TIMESTAMP_LTZ AS UPDATED_AT FROM ORDERS_SRC;

SELECT COUNT(*) FROM ORDERS_TGT;
-- <<< SOLUTION

-- =============================================================================
-- Exercice 4 - Stream : capturer les changements (CDC) (15 min)
-- 1. Creez le stream ST_ORDERS sur ORDERS_SRC.
-- 2. Simulez des changements :
--    - INSERT de 5 commandes (reprenez 5 commandes de 1997 avec O_ORDERKEY + 100000000)
--    - UPDATE : passez a 'F' le statut des commandes 'O' dont O_ORDERKEY < 20000 (quelques centaines)
--    - DELETE de 3 commandes de votre choix
-- 3. Interrogez le stream : repartition par METADATA$ACTION / METADATA$ISUPDATE.
-- 4. Interrogez-le une 2e fois : le contenu a-t-il disparu ? Pourquoi ?
-- Question : comment un UPDATE apparait-il dans un stream ?
-- =============================================================================
-- >>> SOLUTION
CREATE OR REPLACE STREAM ST_ORDERS ON TABLE ORDERS_SRC;

INSERT INTO ORDERS_SRC
SELECT O_ORDERKEY + 100000000, O_CUSTKEY, O_ORDERSTATUS, O_TOTALPRICE, O_ORDERDATE, O_ORDERPRIORITY
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_ORDERDATE BETWEEN '1997-12-01' AND '1997-12-31'
LIMIT 5;

UPDATE ORDERS_SRC SET O_ORDERSTATUS = 'F'
WHERE O_ORDERSTATUS = 'O' AND O_ORDERKEY < 20000;

DELETE FROM ORDERS_SRC
WHERE O_ORDERKEY IN (SELECT O_ORDERKEY FROM ORDERS_SRC WHERE O_ORDERKEY < 100000000 ORDER BY O_ORDERKEY DESC LIMIT 3);

SELECT METADATA$ACTION, METADATA$ISUPDATE, COUNT(*)
FROM ST_ORDERS GROUP BY 1, 2 ORDER BY 1, 2;
SELECT SYSTEM$STREAM_HAS_DATA('ST_ORDERS');

-- Reponses :
-- - Un SELECT ne consomme pas le stream : seul un DML qui le lit (INSERT/MERGE...)
--   dans une transaction validee fait avancer son offset.
-- - Un UPDATE = un couple DELETE + INSERT avec METADATA$ISUPDATE = TRUE.
-- - Le stream ne stocke pas de donnees : c'est un offset sur la table (time travel).
-- <<< SOLUTION

-- =============================================================================
-- Exercice 5 - Appliquer les changements avec MERGE (15 min)
-- Ecrivez le MERGE de ST_ORDERS vers ORDERS_TGT qui :
--   - supprime les lignes supprimees dans la source,
--   - met a jour les lignes modifiees (et UPDATED_AT),
--   - insere les nouvelles lignes.
-- Indice : excluez les lignes "DELETE" qui font partie d'un UPDATE.
-- Verifiez ensuite que le stream est vide et que SRC et TGT ont le meme nombre de lignes.
-- =============================================================================
-- >>> SOLUTION
MERGE INTO ORDERS_TGT t
USING (
  SELECT * FROM ST_ORDERS
  WHERE NOT (METADATA$ACTION = 'DELETE' AND METADATA$ISUPDATE)
) s
ON t.O_ORDERKEY = s.O_ORDERKEY
WHEN MATCHED AND s.METADATA$ACTION = 'DELETE' THEN DELETE
WHEN MATCHED AND s.METADATA$ACTION = 'INSERT' THEN UPDATE SET
  t.O_CUSTKEY = s.O_CUSTKEY, t.O_ORDERSTATUS = s.O_ORDERSTATUS, t.O_TOTALPRICE = s.O_TOTALPRICE,
  t.O_ORDERDATE = s.O_ORDERDATE, t.O_ORDERPRIORITY = s.O_ORDERPRIORITY,
  t.UPDATED_AT = CURRENT_TIMESTAMP()
WHEN NOT MATCHED AND s.METADATA$ACTION = 'INSERT' THEN INSERT
  (O_ORDERKEY, O_CUSTKEY, O_ORDERSTATUS, O_TOTALPRICE, O_ORDERDATE, O_ORDERPRIORITY, UPDATED_AT)
  VALUES (s.O_ORDERKEY, s.O_CUSTKEY, s.O_ORDERSTATUS, s.O_TOTALPRICE, s.O_ORDERDATE, s.O_ORDERPRIORITY, CURRENT_TIMESTAMP());

SELECT SYSTEM$STREAM_HAS_DATA('ST_ORDERS');                 -- FALSE
SELECT (SELECT COUNT(*) FROM ORDERS_SRC) AS SRC, (SELECT COUNT(*) FROM ORDERS_TGT) AS TGT;
-- <<< SOLUTION

-- =============================================================================
-- Exercice 6 - Automatiser avec un DAG de tasks (20 min)
-- 1. Task racine T_MERGE_ORDERS : serverless (taille initiale XSMALL),
--    toutes les minutes, UNIQUEMENT si le stream contient des donnees,
--    execute le MERGE de l'exercice 5.
-- 2. Task enfant T_DAILY_REVENUE (AFTER T_MERGE_ORDERS) : reecrit la table
--    DAILY_REVENUE (O_ORDERDATE, NB_COMMANDES, CA) depuis ORDERS_TGT.
-- 3. Activez le DAG (ordre !), injectez quelques nouvelles lignes dans ORDERS_SRC,
--    attendez ~1 min et suivez l'execution dans TASK_HISTORY et dans Snowsight
--    (Monitoring > Task History, vue graphe).
-- Questions : que coute une execution "a vide" ? Tache serverless ou sur warehouse ?
-- =============================================================================
-- >>> SOLUTION
CREATE OR REPLACE TABLE DAILY_REVENUE (O_ORDERDATE DATE, NB_COMMANDES NUMBER, CA NUMBER(18,2));

CREATE OR REPLACE TASK T_MERGE_ORDERS
  USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
  SCHEDULE = '1 MINUTE'
  WHEN SYSTEM$STREAM_HAS_DATA('ST_ORDERS')
AS
MERGE INTO ORDERS_TGT t
USING (SELECT * FROM ST_ORDERS WHERE NOT (METADATA$ACTION = 'DELETE' AND METADATA$ISUPDATE)) s
ON t.O_ORDERKEY = s.O_ORDERKEY
WHEN MATCHED AND s.METADATA$ACTION = 'DELETE' THEN DELETE
WHEN MATCHED AND s.METADATA$ACTION = 'INSERT' THEN UPDATE SET
  t.O_CUSTKEY = s.O_CUSTKEY, t.O_ORDERSTATUS = s.O_ORDERSTATUS, t.O_TOTALPRICE = s.O_TOTALPRICE,
  t.O_ORDERDATE = s.O_ORDERDATE, t.O_ORDERPRIORITY = s.O_ORDERPRIORITY, t.UPDATED_AT = CURRENT_TIMESTAMP()
WHEN NOT MATCHED AND s.METADATA$ACTION = 'INSERT' THEN INSERT
  (O_ORDERKEY, O_CUSTKEY, O_ORDERSTATUS, O_TOTALPRICE, O_ORDERDATE, O_ORDERPRIORITY, UPDATED_AT)
  VALUES (s.O_ORDERKEY, s.O_CUSTKEY, s.O_ORDERSTATUS, s.O_TOTALPRICE, s.O_ORDERDATE, s.O_ORDERPRIORITY, CURRENT_TIMESTAMP());

CREATE OR REPLACE TASK T_DAILY_REVENUE
  USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
  AFTER T_MERGE_ORDERS
AS
INSERT OVERWRITE INTO DAILY_REVENUE
SELECT O_ORDERDATE, COUNT(*), SUM(O_TOTALPRICE) FROM ORDERS_TGT GROUP BY O_ORDERDATE;

-- Activer : enfants d'abord, racine ensuite
ALTER TASK T_DAILY_REVENUE RESUME;
ALTER TASK T_MERGE_ORDERS  RESUME;
-- (equivalent : SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('T_MERGE_ORDERS');)

-- Nouvelles donnees
INSERT INTO ORDERS_SRC
SELECT O_ORDERKEY + 200000000, O_CUSTKEY, 'O', O_TOTALPRICE, '1998-08-03'::DATE, O_ORDERPRIORITY
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS LIMIT 20;

-- Pour ne pas attendre : EXECUTE TASK T_MERGE_ORDERS;
SELECT NAME, STATE, SCHEDULED_TIME, COMPLETED_TIME, ERROR_MESSAGE
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(SCHEDULED_TIME_RANGE_START => DATEADD(hour, -1, CURRENT_TIMESTAMP())))
WHERE NAME IN ('T_MERGE_ORDERS', 'T_DAILY_REVENUE')
ORDER BY SCHEDULED_TIME DESC;

SELECT * FROM DAILY_REVENUE ORDER BY O_ORDERDATE DESC LIMIT 5;  -- 1998-08-03 doit apparaitre

-- Reponses :
-- - Si WHEN est faux, la task est "SKIPPED" : le test SYSTEM$STREAM_HAS_DATA
--   tourne en cloud services, aucun compute facture.
-- - Serverless : ideal pour des traitements courts/frequents (pas de minimum
--   de 60 s de warehouse). Warehouse : charges lourdes ou partage d'un WH existant.
-- - Alternative recente : task "triggered" (sans SCHEDULE, declenchee par le stream).
-- <<< SOLUTION

-- =============================================================================
-- Exercice 7 - La meme chose en declaratif : Dynamic Table (10 min)
-- Creez DT_REVENUE_BY_PRIORITY (TARGET_LAG = '1 minute', sur votre warehouse) :
-- CA et nombre de commandes par O_ORDERPRIORITY et mois, depuis ORDERS_SRC.
-- Indice : le nom du warehouse doit etre litteral -> SET ddl = ... puis EXECUTE IMMEDIATE $ddl.
-- Inserez une ligne dans ORDERS_SRC et observez le rafraichissement (refresh_mode ?).
-- Question : stream + task ou dynamic table, comment choisir ?
-- =============================================================================
-- >>> SOLUTION
SET ddl = 'CREATE OR REPLACE DYNAMIC TABLE DT_REVENUE_BY_PRIORITY
  TARGET_LAG = ''1 minute''
  WAREHOUSE = ' || $my_wh || '
AS
SELECT O_ORDERPRIORITY, DATE_TRUNC(''month'', O_ORDERDATE) AS MOIS,
       COUNT(*) AS NB_COMMANDES, SUM(O_TOTALPRICE) AS CA
FROM ORDERS_SRC
GROUP BY ALL';
EXECUTE IMMEDIATE $ddl;

SHOW DYNAMIC TABLES LIKE 'DT_REVENUE_BY_PRIORITY';
SELECT "name", "refresh_mode", "target_lag", "scheduling_state" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

SELECT * FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(NAME => 'DT_REVENUE_BY_PRIORITY'))
ORDER BY REFRESH_START_TIME DESC LIMIT 5;

-- Reponse : Dynamic Table = on decrit le resultat, Snowflake gere le CDC et
-- l'orchestration (refresh INCREMENTAL quand c'est possible). Stream + Task =
-- controle fin (MERGE custom, appels de procedures, effets de bord, SCD2...).
-- <<< SOLUTION

-- =============================================================================
-- Exercice 8 (bonus) - Ingestion continue -> Stream de bout en bout (10 min)
-- Le formateur active la task FORMATION.RAW.T_SIMULATED_SNOWPIPE : chaque minute
-- un fichier de 50 commandes est depose dans @FORMATION.RAW.STG_LANDING puis charge
-- dans FORMATION.RAW.ORDERS_LANDING (comme le ferait Snowpipe).
-- 1. Creez un stream APPEND_ONLY ST_LANDING sur cette table partagee.
-- 2. Listez les fichiers deposes dans le stage.
-- 3. Apres 2-3 minutes, affichez les lignes arrivees depuis la creation du stream, par fichier.
-- Question : pourquoi un stream APPEND_ONLY ?
-- =============================================================================
-- >>> SOLUTION
CREATE OR REPLACE STREAM ST_LANDING ON TABLE FORMATION.RAW.ORDERS_LANDING APPEND_ONLY = TRUE;
LIST @FORMATION.RAW.STG_LANDING/orders/;
-- ... 2-3 minutes plus tard :
SELECT _FILE_NAME, COUNT(*) AS NB_LIGNES, MIN(_LOADED_AT) AS CHARGE_A
FROM ST_LANDING GROUP BY 1 ORDER BY 3;
-- Reponse : une table d'atterrissage ne recoit que des INSERT ; APPEND_ONLY ignore
-- UPDATE/DELETE et est plus leger a calculer. Pattern classique :
-- Snowpipe -> table RAW -> stream -> task (MERGE) ou dynamic table.
-- <<< SOLUTION

-- =============================================================================
-- (!) FIN DE LAB - suspendre ce qui consomme
-- =============================================================================
ALTER TASK IF EXISTS T_MERGE_ORDERS SUSPEND;
ALTER TASK IF EXISTS T_DAILY_REVENUE SUSPEND;
ALTER DYNAMIC TABLE IF EXISTS DT_REVENUE_BY_PRIORITY SUSPEND;
-- Formateur : ALTER TASK FORMATION.RAW.T_SIMULATED_SNOWPIPE SUSPEND;
