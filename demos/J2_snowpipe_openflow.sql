/* =============================================================================
   DEMO J2 matin - SNOWPIPE (ingestion continue) & OPENFLOW (CDC)
   Compte : PAID (auto-ingest S3 + Openflow) - Role : SYSADMIN / ACCOUNTADMIN
   Sur le TRIAL, le meme pattern est joue avec la task FORMATION.RAW.T_SIMULATED_SNOWPIPE
   (setup/04_data.sql, LAB 2 exercice 8).
   Partie A : necessite un bucket S3 + un role IAM (placeholders <...>).
   ============================================================================= */

USE ROLE SYSADMIN;
CREATE WAREHOUSE IF NOT EXISTS WH_DEMO WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 INITIALLY_SUSPENDED = TRUE;
USE WAREHOUSE WH_DEMO;
CREATE DATABASE IF NOT EXISTS DEMO_FORMATION;
CREATE SCHEMA IF NOT EXISTS DEMO_FORMATION.INGEST;
USE SCHEMA DEMO_FORMATION.INGEST;

CREATE TABLE IF NOT EXISTS ORDERS_LANDING (
  O_ORDERKEY NUMBER(38,0), O_CUSTKEY NUMBER(38,0), O_ORDERSTATUS STRING,
  O_TOTALPRICE NUMBER(12,2), O_ORDERDATE DATE, O_ORDERPRIORITY STRING,
  _FILE_NAME STRING, _LOADED_AT TIMESTAMP_LTZ
);

-- =============================================================================
-- PARTIE A - Snowpipe auto-ingest sur S3
-- =============================================================================
-- 1) Storage integration : Snowflake assume un role IAM du client (pas de cle d'acces)
-- USE ROLE ACCOUNTADMIN;
-- CREATE STORAGE INTEGRATION SI_S3_FORMATION
--   TYPE = EXTERNAL_STAGE STORAGE_PROVIDER = 'S3' ENABLED = TRUE
--   STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::<account_id>:role/<snowflake_role>'
--   STORAGE_ALLOWED_LOCATIONS = ('s3://<bucket>/formation/');
-- DESC INTEGRATION SI_S3_FORMATION;   -- STORAGE_AWS_IAM_USER_ARN + EXTERNAL_ID -> trust policy IAM
-- GRANT USAGE ON INTEGRATION SI_S3_FORMATION TO ROLE SYSADMIN;
-- USE ROLE SYSADMIN;

-- 2) Stage externe + pipe
-- CREATE STAGE STG_S3_ORDERS
--   URL = 's3://<bucket>/formation/orders/' STORAGE_INTEGRATION = SI_S3_FORMATION
--   FILE_FORMAT = (TYPE = CSV COMPRESSION = AUTO);
-- CREATE OR REPLACE PIPE PIPE_ORDERS AUTO_INGEST = TRUE AS
--   COPY INTO ORDERS_LANDING
--   FROM (SELECT $1, $2, $3, $4, $5, $6, METADATA$FILENAME, CURRENT_TIMESTAMP() FROM @STG_S3_ORDERS);
-- SHOW PIPES LIKE 'PIPE_ORDERS';      -- notification_channel = ARN SQS a brancher sur l'event S3 du bucket

-- 3) Deposer un fichier dans le bucket (console AWS / aws s3 cp), puis :
-- SELECT SYSTEM$PIPE_STATUS('PIPE_ORDERS');
-- ALTER PIPE PIPE_ORDERS REFRESH;     -- rattrapage des fichiers deposes avant la creation (7 j)

-- =============================================================================
-- PARTIE B - Pipe sur stage interne (sans cloud) : declenche par l'API REST
-- =============================================================================
CREATE STAGE IF NOT EXISTS STG_INT_ORDERS FILE_FORMAT = (TYPE = CSV COMPRESSION = AUTO);
CREATE OR REPLACE PIPE PIPE_ORDERS_INT AS
  COPY INTO ORDERS_LANDING
  FROM (SELECT $1, $2, $3, $4, $5, $6, METADATA$FILENAME, CURRENT_TIMESTAMP() FROM @STG_INT_ORDERS);
-- Pas de notification d'evenement sur un stage interne : l'application appelle
-- l'endpoint REST insertFiles (SDK snowflake-ingest, auth par paire de cles) apres
-- chaque PUT. En demo, deposer un fichier et constater qu'il n'est PAS charge
-- tant que personne ne notifie le pipe (contraste avec AUTO_INGEST) :
COPY INTO @STG_INT_ORDERS/batch_
FROM (SELECT O_ORDERKEY, O_CUSTKEY, O_ORDERSTATUS, O_TOTALPRICE, O_ORDERDATE, O_ORDERPRIORITY
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS SAMPLE (50 ROWS))
FILE_FORMAT = (TYPE = CSV COMPRESSION = GZIP) INCLUDE_QUERY_ID = TRUE;
LIST @STG_INT_ORDERS;
SELECT SYSTEM$PIPE_STATUS('PIPE_ORDERS_INT');

-- =============================================================================
-- Suivi et couts (communs aux deux parties)
-- =============================================================================
SELECT FILE_NAME, STATUS, ROW_COUNT, PIPE_RECEIVED_TIME, LAST_LOAD_TIME
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
       TABLE_NAME => 'ORDERS_LANDING', START_TIME => DATEADD(hour, -2, CURRENT_TIMESTAMP())));
-- SNOWFLAKE.ACCOUNT_USAGE.PIPE_USAGE_HISTORY : credits serverless par pipe
-- Points cles : serverless, facture au fichier + compute ; latence ~1 min ;
-- dedoublonnage par nom de fichier (14 j) ; fichiers de 100-250 Mo compresses ideaux.
-- Snowpipe Streaming : lignes (pas fichiers) via SDK/Kafka connector, latence ~secondes.

-- =============================================================================
-- PARTIE C - Openflow (UI) : integration CDC
-- =============================================================================
-- - Openflow = service d'integration manage (base Apache NiFi), deploye dans le
--   compte (Snowpark Container Services) ou dans le VPC client (BYOC).
-- - Demo : Data > Openflow > creer un deployment + runtime > connecteur
--   "PostgreSQL CDC" / "MySQL CDC" / "SQL Server CDC" : snapshot initial puis
--   replication continue des changements vers des tables Snowflake.
-- - Autres connecteurs : SharePoint, Google Drive, Kafka, Salesforce...
-- - Positionnement : Snowpipe = fichiers ; Snowpipe Streaming / Kafka = evenements ;
--   Openflow = connecteurs manages (CDC bases, SaaS, non structure).

-- Nettoyage
-- ALTER PIPE PIPE_ORDERS_INT SET PIPE_EXECUTION_PAUSED = TRUE;
-- DROP SCHEMA DEMO_FORMATION.INGEST;
