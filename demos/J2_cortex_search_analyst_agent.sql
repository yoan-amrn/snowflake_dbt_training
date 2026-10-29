/* =============================================================================
   DEMO J2 apres-midi - CORTEX SEARCH, CORTEX ANALYST, CORTEX AGENTS, CORTEX CODE
   Compte : PAID (fonctionnalites non disponibles / limitees sur le trial)
   Role   : SYSADMIN (+ CORTEX_USER, accorde a PUBLIC par defaut)
   Fil rouge : un agent qui repond a la fois sur les CHIFFRES (TPCH, via Analyst
   sur une semantic view) et sur les AVIS CLIENTS (texte libre, via Search).
   Cout : quelques centiemes de credit (30 avis generes + index + quelques questions).
   ============================================================================= */

USE ROLE SYSADMIN;
CREATE WAREHOUSE IF NOT EXISTS WH_DEMO WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 INITIALLY_SUSPENDED = TRUE;
USE WAREHOUSE WH_DEMO;
CREATE DATABASE IF NOT EXISTS DEMO_FORMATION;
CREATE SCHEMA IF NOT EXISTS DEMO_FORMATION.CORTEX;
USE SCHEMA DEMO_FORMATION.CORTEX;
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_EU';   -- si modele absent de la region

-- -----------------------------------------------------------------------------
-- 0. Donnees : avis clients generes (comme LAB 3 ex.5) + tables TPCH locales
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
-- 1. CORTEX SEARCH : recherche hybride (vectorielle + mots-cles) managee
--    Index maintenu automatiquement (TARGET_LAG), pas d'embeddings a gerer.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE CORTEX SEARCH SERVICE REVIEWS_SEARCH
  ON REVIEW
  ATTRIBUTES TON
  WAREHOUSE = WH_DEMO
  TARGET_LAG = '1 day'
AS
SELECT REVIEW_ID, P_NAME, TON, REVIEW FROM REVIEWS;

SHOW CORTEX SEARCH SERVICES;

SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
  'DEMO_FORMATION.CORTEX.REVIEWS_SEARCH',
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
    orders   AS DEMO_FORMATION.CORTEX.ORDERS   PRIMARY KEY (O_ORDERKEY) COMMENT = 'Commandes clients',
    customer AS DEMO_FORMATION.CORTEX.CUSTOMER PRIMARY KEY (C_CUSTKEY)  COMMENT = 'Clients',
    nation   AS DEMO_FORMATION.CORTEX.NATION   PRIMARY KEY (N_NATIONKEY) COMMENT = 'Pays',
    region   AS DEMO_FORMATION.CORTEX.REGION   PRIMARY KEY (R_REGIONKEY) COMMENT = 'Regions du monde'
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
CREATE OR REPLACE AGENT DEMO_FORMATION.CORTEX.AGENT_VENTES
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
      semantic_view: "DEMO_FORMATION.CORTEX.SV_TPCH_SALES"
      execution_environment:
        type: "warehouse"
        warehouse: "WH_DEMO"
    RechercheAvis:
      search_service: "DEMO_FORMATION.CORTEX.REVIEWS_SEARCH"
      max_results: "5"
      id_column: "REVIEW_ID"
      title_column: "P_NAME"
  $$;

DESCRIBE AGENT DEMO_FORMATION.CORTEX.AGENT_VENTES;
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
-- DROP AGENT DEMO_FORMATION.CORTEX.AGENT_VENTES;
-- DROP CORTEX SEARCH SERVICE DEMO_FORMATION.CORTEX.REVIEWS_SEARCH;   -- facture tant qu'il existe
-- -----------------------------------------------------------------------------
