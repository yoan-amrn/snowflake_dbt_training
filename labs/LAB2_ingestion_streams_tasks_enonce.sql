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
-- A VOUS DE JOUER



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
-- A VOUS DE JOUER



-- =============================================================================
-- Exercice 3 - Source et cible (5 min)
-- 1. ORDERS_SRC : commandes TPCH_SF1 de 1998 (O_ORDERDATE >= '1998-01-01').
-- 2. ORDERS_TGT : meme structure + colonne UPDATED_AT TIMESTAMP_LTZ,
--    chargee avec le contenu initial de ORDERS_SRC.
-- =============================================================================
-- A VOUS DE JOUER



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
-- A VOUS DE JOUER



-- =============================================================================
-- Exercice 5 - Appliquer les changements avec MERGE (15 min)
-- Ecrivez le MERGE de ST_ORDERS vers ORDERS_TGT qui :
--   - supprime les lignes supprimees dans la source,
--   - met a jour les lignes modifiees (et UPDATED_AT),
--   - insere les nouvelles lignes.
-- Indice : excluez les lignes "DELETE" qui font partie d'un UPDATE.
-- Verifiez ensuite que le stream est vide et que SRC et TGT ont le meme nombre de lignes.
-- =============================================================================
-- A VOUS DE JOUER



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
-- A VOUS DE JOUER



-- =============================================================================
-- Exercice 7 - La meme chose en declaratif : Dynamic Table (10 min)
-- Creez DT_REVENUE_BY_PRIORITY (TARGET_LAG = '1 minute', sur votre warehouse) :
-- CA et nombre de commandes par O_ORDERPRIORITY et mois, depuis ORDERS_SRC.
-- Indice : le nom du warehouse doit etre litteral -> SET ddl = ... puis EXECUTE IMMEDIATE $ddl.
-- Inserez une ligne dans ORDERS_SRC et observez le rafraichissement (refresh_mode ?).
-- Question : stream + task ou dynamic table, comment choisir ?
-- =============================================================================
-- A VOUS DE JOUER



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
-- A VOUS DE JOUER



-- =============================================================================
-- (!) FIN DE LAB - suspendre ce qui consomme
-- =============================================================================
ALTER TASK IF EXISTS T_MERGE_ORDERS SUSPEND;
ALTER TASK IF EXISTS T_DAILY_REVENUE SUSPEND;
ALTER DYNAMIC TABLE IF EXISTS DT_REVENUE_BY_PRIORITY SUSPEND;
-- Formateur : ALTER TASK FORMATION.RAW.T_SIMULATED_SNOWPIPE SUSPEND;
