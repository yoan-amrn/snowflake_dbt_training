/* =============================================================================
   DEMO J2 apres-midi - CORTEX AI FUNCTIONS, SEARCH, ANALYST, AGENTS, CORTEX CODE
   Compte : PAID (fonctionnalites non disponibles / limitees sur le trial)
   Role   : SYSADMIN (+ CORTEX_USER, accorde a PUBLIC par defaut)
   Fil rouge : un agent qui repond a la fois sur les CHIFFRES (TPCH, via Analyst
   sur une semantic view) et sur les AVIS CLIENTS (texte libre, via Search).
   Cout : quelques centiemes de credit (30 avis generes + index + quelques questions).
   ============================================================================= */

USE ROLE SYSADMIN;
-- CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 INITIALLY_SUSPENDED = TRUE;
USE WAREHOUSE COMPUTE_WH;
CREATE DATABASE IF NOT EXISTS DB_YAR;
CREATE SCHEMA IF NOT EXISTS DB_YAR.CORTEX;
USE SCHEMA DB_YAR.CORTEX;
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_EU';   -- si modele absent de la region

-- -----------------------------------------------------------------------------
-- 0. Donnees : avis clients generes par AI_COMPLETE + tables TPCH locales
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE REVIEWS AS
SELECT P_PARTKEY AS REVIEW_ID, P_NAME,
       CASE MOD(P_PARTKEY, 3) WHEN 0 THEN 'tres negatif' WHEN 1 THEN 'neutre' ELSE 'enthousiaste' END AS TON,
       AI_COMPLETE('llama3.1-8b',
         'Redige un avis client de 2 phrases, en francais, au ton ' || TON ||
         ', sur le produit "' || P_NAME || '". Evoque la qualite, la livraison, le prix ou le service client. ' ||
         'Reponds uniquement par l''avis.') AS REVIEW
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.PART
ORDER BY P_PARTKEY
LIMIT 30;

CREATE OR REPLACE TABLE ORDERS   AS SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;
CREATE OR REPLACE TABLE CUSTOMER AS SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER;
CREATE OR REPLACE TABLE NATION   AS SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION;
CREATE OR REPLACE TABLE REGION   AS SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION;

-- -----------------------------------------------------------------------------
-- 0bis. CORTEX AI FUNCTIONS : enrichir les avis en SQL (ex-LAB 3 ex.5, absent du trial)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE REVIEWS_ENRICHED AS
SELECT REVIEW_ID, P_NAME, TON, REVIEW,
       SNOWFLAKE.CORTEX.SENTIMENT(REVIEW)                                                       AS SENTIMENT,
       AI_CLASSIFY(REVIEW, ['qualite', 'livraison', 'prix', 'service client']):labels[0]::STRING  AS THEME,
       AI_FILTER(PROMPT('Cet avis client mentionne-t-il un probleme de livraison ? {0}', REVIEW)) AS PB_LIVRAISON,
       SNOWFLAKE.CORTEX.TRANSLATE(REVIEW, 'fr', 'en')                                           AS REVIEW_EN
FROM REVIEWS;

SELECT TON, ROUND(AVG(SENTIMENT), 2) AS SENTIMENT_MOYEN, COUNT(*)
FROM REVIEWS_ENRICHED GROUP BY 1;            -- coherence ton demande / sentiment mesure ?

SELECT THEME, COUNT(*), COUNT_IF(PB_LIVRAISON) AS NB_PB_LIVRAISON
FROM REVIEWS_ENRICHED GROUP BY 1 ORDER BY 2 DESC;

SELECT AI_AGG(REVIEW, 'Liste en francais les 3 principaux irritants clients, en une phrase chacun.') AS SYNTHESE
FROM REVIEWS_ENRICHED WHERE SENTIMENT < 0;

-- Notes : SENTIMENT est optimise pour l'anglais (comparer sur REVIEW_EN) ;
-- le modele se choisit selon cout/qualite (llama3.1-8b economique, mistral-large2
-- ou claude-* plus qualitatifs). Facturation au token : garder de petits volumes.

-- -----------------------------------------------------------------------------
-- 1. CORTEX SEARCH : recherche hybride (vectorielle + mots-cles) managee
--    Index maintenu automatiquement (TARGET_LAG), pas d'embeddings a gerer.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE CORTEX SEARCH SERVICE REVIEWS_SEARCH
  ON REVIEW
  ATTRIBUTES TON
  WAREHOUSE = COMPUTE_WH
  TARGET_LAG = '1 day'
AS
SELECT REVIEW_ID, P_NAME, TON, REVIEW FROM REVIEWS;

SHOW CORTEX SEARCH SERVICES;

SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
  'DB_YAR.CORTEX.REVIEWS_SEARCH',
  '{"query": "colis arrive en retard ou abime", "columns": ["P_NAME", "TON", "REVIEW"], "limit": 5}'
)):results AS RESULTATS;
-- Noter : la requete ne contient pas forcement les mots de l'avis (semantique).
-- UI : AI & ML > Cortex Search > REVIEWS_SEARCH > Playground

-- -----------------------------------------------------------------------------
-- 2. CORTEX ANALYST : text-to-SQL sur un modele semantique (semantic view)
--    Le modele porte le vocabulaire metier : tables, jointures, dimensions, metriques.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SEMANTIC VIEW SV_TPCH_SALES
  TABLES (
    orders   AS DB_YAR.CORTEX.ORDERS   PRIMARY KEY (O_ORDERKEY) COMMENT = 'Commandes clients',
    customer AS DB_YAR.CORTEX.CUSTOMER PRIMARY KEY (C_CUSTKEY)  COMMENT = 'Clients',
    nation   AS DB_YAR.CORTEX.NATION   PRIMARY KEY (N_NATIONKEY) COMMENT = 'Pays',
    region   AS DB_YAR.CORTEX.REGION   PRIMARY KEY (R_REGIONKEY) COMMENT = 'Regions du monde'
  )
  RELATIONSHIPS (
    orders_customer AS orders (O_CUSTKEY)     REFERENCES customer,
    customer_nation AS customer (C_NATIONKEY) REFERENCES nation,
    nation_region   AS nation (N_REGIONKEY)   REFERENCES region
  )
  FACTS (
    orders.order_amount AS O_TOTALPRICE COMMENT = 'Montant TTC de la commande'
  )
  DIMENSIONS (
    orders.order_date      AS O_ORDERDATE     COMMENT = 'Date de commande',
    orders.order_priority  AS O_ORDERPRIORITY COMMENT = 'Priorite (1-URGENT a 5-LOW)',
    customer.segment       AS C_MKTSEGMENT    WITH SYNONYMS = ('segment marche', 'secteur') COMMENT = 'Segment client',
    nation.nation_name     AS N_NAME          WITH SYNONYMS = ('pays') COMMENT = 'Pays du client',
    region.region_name     AS R_NAME          COMMENT = 'Region du client'
  )
  METRICS (
    orders.revenue     AS SUM(orders.order_amount) WITH SYNONYMS = ('chiffre d''affaires', 'CA') COMMENT = 'Chiffre d''affaires',
    orders.order_count AS COUNT(orders.O_ORDERKEY) COMMENT = 'Nombre de commandes'
  )
  COMMENT = 'Ventes TPCH pour Cortex Analyst';

-- Une semantic view s'interroge aussi en SQL (sans IA) :
SELECT * FROM SEMANTIC_VIEW(
  SV_TPCH_SALES
  DIMENSIONS region.region_name
  METRICS orders.revenue, orders.order_count
) ORDER BY REVENUE DESC;

-- UI : AI & ML > Cortex Analyst > SV_TPCH_SALES > poser en francais :
--   "Quel est le CA par region en 1997 ?"  /  "Top 5 des pays par nombre de commandes urgentes"
--   -> montrer le SQL genere, la verified query a ajouter, les synonymes.

-- -----------------------------------------------------------------------------
-- 3. CORTEX AGENT : orchestre les outils (Analyst + Search) et compose la reponse
-- -----------------------------------------------------------------------------
CREATE OR REPLACE AGENT DB_YAR.CORTEX.AGENT_VENTES
  COMMENT = 'Agent de demo formation : ventes TPCH + avis clients'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  orchestration:
    budget:
      seconds: 60
      tokens: 16000

  instructions:
    response: "Reponds en francais, de maniere concise, avec des chiffres arrondis."
    orchestration: "Utilise AnalysteVentes pour toute question chiffree (CA, commandes, pays, segments). Utilise RechercheAvis pour les questions sur le ressenti, la qualite ou les irritants clients."
    sample_questions:
      - question: "Quel est le chiffre d'affaires par region ?"
      - question: "Quels sont les principaux irritants dans les avis clients ?"

  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "AnalysteVentes"
        description: "Interroge les ventes TPCH (commandes, clients, pays, regions)"
    - tool_spec:
        type: "cortex_search"
        name: "RechercheAvis"
        description: "Recherche dans les avis clients en texte libre"

  tool_resources:
    AnalysteVentes:
      semantic_view: "DB_YAR.CORTEX.SV_TPCH_SALES"
      execution_environment:
        type: "warehouse"
        warehouse: "COMPUTE_WH"
    RechercheAvis:
      search_service: "DB_YAR.CORTEX.REVIEWS_SEARCH"
      max_results: "5"
      id_column: "REVIEW_ID"
      title_column: "P_NAME"
  $$;

DESCRIBE AGENT DB_YAR.CORTEX.AGENT_VENTES;
-- Test : AI & ML > Agents > AGENT_VENTES > Playground, ou Snowflake Intelligence :
--   "Quel pays genere le plus de CA, et que disent les clients de la livraison ?"
--   -> montrer la trace : choix des outils, SQL genere, passages retrouves.
-- Acces programmatique : API REST agent:run / fonction SNOWFLAKE.CORTEX.DATA_AGENT_RUN.

-- -----------------------------------------------------------------------------
-- 4. CORTEX CODE (UI) : assistant de developpement dans Snowsight / VS Code
-- -----------------------------------------------------------------------------
-- - Worksheet / Workspace : "Explique cette requete", "Optimise", "Corrige l'erreur",
--   generation de SQL a partir du catalogue (connait les objets et les droits du role).
-- - Demo : ouvrir LAB 2 ex.5 (MERGE), demander "ecris le MERGE du stream ST_ORDERS
--   vers ORDERS_TGT" puis comparer au corrige.
-- - Gouvernance : respecte le RBAC, rien n'est execute sans validation.

-- -----------------------------------------------------------------------------
-- Couts : SNOWFLAKE.ACCOUNT_USAGE.CORTEX_SEARCH_SERVING_USAGE_HISTORY,
--         CORTEX_ANALYST_USAGE_HISTORY, CORTEX_FUNCTIONS_USAGE_HISTORY
-- Nettoyage
-- DROP AGENT DB_YAR.CORTEX.AGENT_VENTES;
-- DROP CORTEX SEARCH SERVICE DB_YAR.CORTEX.REVIEWS_SEARCH;   -- facture tant qu'il existe
-- -----------------------------------------------------------------------------
