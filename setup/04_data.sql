/* =============================================================================
   04 - DONNEES PARTAGEES DES LABS (sans S3 : tout est genere depuis TPCH)
   A executer apres 01 -> 03 (via deploy.sql). Idempotent. Cout < 0,1 credit.
   - FORMATION.RAW.CUSTOMER            : clients TPCH enrichis de PII (LAB 1, LAB 3)
   - FORMATION.COMMON.STG_FILES        : stage interne + fichiers CSV/JSON/Parquet (LAB 2 - Formats & Stages)
   - FORMATION.COMMON.FF_*             : file formats partages
   - FORMATION.RAW.ORDERS_LANDING      : table d'atterrissage (LAB 2 bonus "Snowpipe simule")
   - FORMATION.RAW.T_SIMULATED_SNOWPIPE: task qui depose un fichier + le charge chaque minute
   ============================================================================= */

USE ROLE FORMATION_ADMIN;
USE WAREHOUSE WH_ADMIN;

-- -----------------------------------------------------------------------------
-- 1. CUSTOMER enrichi (LAB 1 : RAP sur REGION, masking EMAIL/PHONE/ADDRESS/BALANCE)
--    ACCOUNT_BALANCE en NUMBER(12,2) : doit correspondre a la signature de MP_BALANCE.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE FORMATION.RAW.CUSTOMER (
  CUSTOMER_ID     NUMBER(38,0),
  CUSTOMER_NAME   STRING,
  COUNTRY         STRING,
  REGION          STRING,
  SEGMENT         STRING,
  EMAIL           STRING,
  PHONE           STRING,
  ADDRESS         STRING,
  ACCOUNT_BALANCE NUMBER(12,2)
) COPY GRANTS
AS
SELECT c.C_CUSTKEY,
       c.C_NAME,
       n.N_NAME,
       r.R_NAME,
       c.C_MKTSEGMENT,
       LOWER(REPLACE(c.C_NAME, '#', '.')) || '@exemple.fr',
       c.C_PHONE,
       c.C_ADDRESS,
       c.C_ACCTBAL
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER c
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION   n ON n.N_NATIONKEY = c.C_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION   r ON r.R_REGIONKEY = n.N_REGIONKEY;
COMMENT ON TABLE FORMATION.RAW.CUSTOMER IS 'Clients TPCH_SF1 enrichis de donnees personnelles fictives';

-- -----------------------------------------------------------------------------
-- 2. Stage interne et file formats partages (LAB 2 - Formats & Stages)
-- -----------------------------------------------------------------------------
USE SCHEMA FORMATION.COMMON;

CREATE STAGE IF NOT EXISTS STG_FILES
  DIRECTORY = (ENABLE = TRUE)
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
  COMMENT = 'Fichiers d''exemple des labs (CSV, JSON, Parquet)';

CREATE OR REPLACE FILE FORMAT FF_CSV
  TYPE = CSV SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NULL') COMPRESSION = AUTO
  COMMENT = 'CSV avec entete ignore';
CREATE OR REPLACE FILE FORMAT FF_CSV_PARSE_HEADER
  TYPE = CSV PARSE_HEADER = TRUE FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  COMMENT = 'CSV avec entete lu (INFER_SCHEMA / MATCH_BY_COLUMN_NAME)';
CREATE OR REPLACE FILE FORMAT FF_JSON
  TYPE = JSON STRIP_OUTER_ARRAY = TRUE
  COMMENT = 'JSON (un document par ligne ou tableau)';
CREATE OR REPLACE FILE FORMAT FF_PARQUET
  TYPE = PARQUET
  COMMENT = 'Parquet';

-- Fichiers d'exemple (regeneres a chaque deploiement) : commandes de janvier 1998
REMOVE @STG_FILES/samples/;

-- CSV propre, compresse, decoupe en plusieurs fichiers
COPY INTO @STG_FILES/samples/orders_csv/orders_
FROM (
  SELECT O_ORDERKEY, O_CUSTKEY, O_ORDERSTATUS, O_TOTALPRICE, O_ORDERDATE, O_ORDERPRIORITY
  FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
  WHERE O_ORDERDATE BETWEEN '1998-01-01' AND '1998-01-31'
)
FILE_FORMAT = (TYPE = CSV COMPRESSION = GZIP FIELD_OPTIONALLY_ENCLOSED_BY = '"')
HEADER = TRUE MAX_FILE_SIZE = 200000;

-- CSV "sale" : quelques montants 'N/A' et dates invalides (exercice ON_ERROR / VALIDATION_MODE)
COPY INTO @STG_FILES/samples/orders_csv_errors/orders_bad.csv
FROM (
  SELECT O_ORDERKEY, O_CUSTKEY, O_ORDERSTATUS,
         IFF(MOD(O_ORDERKEY, 50) = 0, 'N/A', TO_VARCHAR(O_TOTALPRICE))        AS O_TOTALPRICE,
         IFF(MOD(O_ORDERKEY, 70) = 0, '1998-02-31', TO_VARCHAR(O_ORDERDATE))  AS O_ORDERDATE,
         O_ORDERPRIORITY
  FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
  WHERE O_ORDERDATE BETWEEN '1998-01-01' AND '1998-01-07'
)
FILE_FORMAT = (TYPE = CSV COMPRESSION = NONE FIELD_OPTIONALLY_ENCLOSED_BY = '"')
HEADER = TRUE SINGLE = TRUE;

-- JSON semi-structure : une commande par document, avec client imbrique et tableau de lignes
COPY INTO @STG_FILES/samples/orders_json/orders_
FROM (
  SELECT OBJECT_CONSTRUCT(
           'order_key',  o.O_ORDERKEY,
           'order_date', o.O_ORDERDATE,
           'status',     o.O_ORDERSTATUS,
           'customer',   OBJECT_CONSTRUCT('key', c.C_CUSTKEY, 'name', c.C_NAME, 'segment', c.C_MKTSEGMENT),
           'lines',      ARRAY_AGG(OBJECT_CONSTRUCT(
                           'line_number', l.L_LINENUMBER, 'part_key', l.L_PARTKEY,
                           'quantity', l.L_QUANTITY, 'price', l.L_EXTENDEDPRICE))
         )
  FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS   o
  JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER c ON c.C_CUSTKEY  = o.O_CUSTKEY
  JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM l ON l.L_ORDERKEY = o.O_ORDERKEY
  WHERE o.O_ORDERDATE BETWEEN '1998-01-01' AND '1998-01-07'
  GROUP BY o.O_ORDERKEY, o.O_ORDERDATE, o.O_ORDERSTATUS, c.C_CUSTKEY, c.C_NAME, c.C_MKTSEGMENT
)
FILE_FORMAT = (TYPE = JSON COMPRESSION = GZIP);

-- Parquet (schema embarque dans le fichier)
COPY INTO @STG_FILES/samples/orders_parquet/orders_
FROM (
  SELECT O_ORDERKEY, O_CUSTKEY, O_ORDERSTATUS, O_TOTALPRICE, O_ORDERDATE, O_ORDERPRIORITY
  FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
  WHERE O_ORDERDATE BETWEEN '1998-01-01' AND '1998-01-31'
)
FILE_FORMAT = (TYPE = PARQUET)
HEADER = TRUE;

ALTER STAGE STG_FILES REFRESH;
SELECT RELATIVE_PATH, SIZE FROM DIRECTORY(@STG_FILES) ORDER BY 1;

-- -----------------------------------------------------------------------------
-- 3. "Snowpipe simule" (pas de S3 sur le trial) : une task serverless depose un
--    fichier dans un stage interne puis le charge par COPY INTO. Les COPY suivants
--    ignorent les fichiers deja charges (load metadata 64 j) : meme semantique
--    "exactly once par fichier" que Snowpipe. Le vrai Snowpipe : demos/J2_snowpipe_openflow.sql
--    Stage, table et task dans RAW : meme role proprietaire (_FORMATION_RAW_SFULL,
--    qui a EXECUTE MANAGED TASK via 02_formation_schemas.sql).
-- -----------------------------------------------------------------------------
USE SCHEMA FORMATION.RAW;

CREATE TABLE IF NOT EXISTS ORDERS_LANDING (
  O_ORDERKEY      NUMBER(38,0),
  O_CUSTKEY       NUMBER(38,0),
  O_ORDERSTATUS   STRING,
  O_TOTALPRICE    NUMBER(12,2),
  O_ORDERDATE     DATE,
  O_ORDERPRIORITY STRING,
  _FILE_NAME      STRING,
  _LOADED_AT      TIMESTAMP_LTZ
) COMMENT = 'Table d''atterrissage alimentee par fichiers (Snowpipe / simulation)';
-- Change tracking active par le proprietaire : les participants peuvent creer
-- un stream dessus avec un simple SELECT.
ALTER TABLE ORDERS_LANDING SET CHANGE_TRACKING = TRUE;

CREATE STAGE IF NOT EXISTS STG_LANDING
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Zone de depot du "Snowpipe simule"';

CREATE OR REPLACE TASK T_SIMULATED_SNOWPIPE
  USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
  SCHEDULE = '1 MINUTE'
  COMMENT = 'LAB 2 bonus : depose et charge un fichier de 50 commandes par minute (a suspendre apres le lab)'
AS
EXECUTE IMMEDIATE $$
BEGIN
  -- 1) un "systeme source" depose un fichier (nom unique grace a INCLUDE_QUERY_ID)
  COPY INTO @FORMATION.RAW.STG_LANDING/orders/batch_
  FROM (
    SELECT O_ORDERKEY, O_CUSTKEY, O_ORDERSTATUS, O_TOTALPRICE, CURRENT_DATE(), O_ORDERPRIORITY
    FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS SAMPLE (50 ROWS)
  )
  FILE_FORMAT = (TYPE = CSV COMPRESSION = GZIP)
  INCLUDE_QUERY_ID = TRUE;

  -- 2) l'ingestion charge les nouveaux fichiers uniquement
  COPY INTO FORMATION.RAW.ORDERS_LANDING
  FROM (
    SELECT $1, $2, $3, $4, $5, $6, METADATA$FILENAME, CURRENT_TIMESTAMP()
    FROM @FORMATION.RAW.STG_LANDING/orders/
  )
  FILE_FORMAT = (TYPE = CSV);
END;
$$;
-- La task est creee SUSPENDUE. Pendant le LAB 2 (bonus) :
--   ALTER TASK FORMATION.RAW.T_SIMULATED_SNOWPIPE RESUME;
--   ... puis SUSPEND a la fin du lab.

SELECT COUNT(*) AS NB_CLIENTS FROM FORMATION.RAW.CUSTOMER;
