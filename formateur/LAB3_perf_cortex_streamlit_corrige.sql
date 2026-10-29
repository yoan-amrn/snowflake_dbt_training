/* =============================================================================
   LAB 3 - PERFORMANCE - CORTEX AI - ML - STREAMLIT  (J2 apres-midi, ~2h)
   Jeu de donnees : TPCH SF10 / SF100 (sample data) + tables preparees par le
   formateur dans FORMATION.CURATED (LINEITEM_UNSORTED, LINEITEM_BY_SHIPDATE,
   ORDERS_SF10, ORDERS_SF10_SOS) par setup/05_lab_prep.sql la veille.
   Cortex Search / Analyst / Agents : demo formateur (demos/J2_cortex_search_analyst_agent.sql)
   (!) Remettez votre warehouse en XSMALL a la fin (dernier bloc).
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
-- Exercice 1 - Query Profile et les 3 niveaux de cache (20 min)
-- 1. Desactivez le cache de resultats (USE_CACHED_RESULT = FALSE) et lancez la
--    requete TPC-H Q1 sur TPCH_SF10.LINEITEM. Ouvrez le Query Profile :
--    temps par operateur, partitions scannees / totales, "% scanned from cache".
-- 2. Relancez-la telle quelle : qu'est-ce qui change ? (cache warehouse / SSD)
-- 3. Reactivez le cache de resultats, lancez-la deux fois : duree ? warehouse utilise ?
-- 4. Recuperez durees et octets scannes de vos dernieres requetes via
--    INFORMATION_SCHEMA.QUERY_HISTORY_BY_USER.
-- =============================================================================
-- >>> SOLUTION
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- TPC-H Q1 (pricing summary report)
SELECT L_RETURNFLAG, L_LINESTATUS,
       SUM(L_QUANTITY)                                       AS SUM_QTY,
       SUM(L_EXTENDEDPRICE)                                  AS SUM_BASE_PRICE,
       SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT))               AS SUM_DISC_PRICE,
       SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT) * (1 + L_TAX)) AS SUM_CHARGE,
       AVG(L_QUANTITY) AS AVG_QTY, AVG(L_DISCOUNT) AS AVG_DISC, COUNT(*) AS COUNT_ORDER
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM
WHERE L_SHIPDATE <= DATEADD(day, -90, '1998-12-01'::DATE)
GROUP BY 1, 2 ORDER BY 1, 2;
-- 1er run : lecture distante (remote disk) ; 2e run : "% scanned from cache" eleve

ALTER SESSION SET USE_CACHED_RESULT = TRUE;
-- relancer 2 fois la requete Q1 : le 2e run est servi par le RESULT CACHE
-- (quelques ms, aucun warehouse demarre, valable 24h si les donnees n'ont pas change)

SELECT QUERY_TEXT, WAREHOUSE_SIZE, EXECUTION_STATUS,
       TOTAL_ELAPSED_TIME / 1000 AS DUREE_S,
       BYTES_SCANNED / POWER(1024, 3) AS GO_SCANNES
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_USER(RESULT_LIMIT => 20))
WHERE QUERY_TEXT ILIKE '%L_RETURNFLAG%'
ORDER BY START_TIME DESC;
-- <<< SOLUTION

-- =============================================================================
-- Exercice 2 - Dimensionnement : scale up (15 min)
-- 1. Cache de resultats desactive, lancez Q1 sur TPCH_SF100.LINEITEM (600 M lignes)
--    avec votre warehouse XSMALL. Notez la duree.
-- 2. Passez le warehouse en SMALL, suspendez-le puis relancez (pour vider le cache SSD).
-- 3. Comparez duree x credits/heure : la requete coute-t-elle plus cher ?
-- Question : quand preferer un multi-cluster warehouse au scale up ?
-- (!) Cout : ~1-2 min de XS + ~1 min de S par participant (~0,1 credit chacun).
--     Si budget serre : un seul participant execute, les autres lisent le profile.
-- =============================================================================
-- >>> SOLUTION
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT L_RETURNFLAG, L_LINESTATUS, SUM(L_QUANTITY), SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT)), COUNT(*)
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM
WHERE L_SHIPDATE <= '1998-09-02'
GROUP BY 1, 2 ORDER BY 1, 2;                          -- XS (1 credit/h)

ALTER WAREHOUSE IDENTIFIER($my_wh) SET WAREHOUSE_SIZE = SMALL;
ALTER WAREHOUSE IDENTIFIER($my_wh) SUSPEND;           -- vide le cache local
-- (relancer la meme requete)                         -- S (2 credits/h)

-- Reponses :
-- - Sur une requete qui parallelise bien, doubler la taille ~ divise la duree par 2
--   -> cout quasi identique, resultat 2x plus vite. Au-dela, gains decroissants.
-- - Scale up = requetes plus lourdes/plus complexes (spilling dans le profile !).
--   Scale out (multi-cluster) = plus d'utilisateurs simultanes (files d'attente),
--   pas des requetes plus rapides.
ALTER WAREHOUSE IDENTIFIER($my_wh) SET WAREHOUSE_SIZE = XSMALL;
-- <<< SOLUTION

-- =============================================================================
-- Exercice 3 - Micro-partitions et clustering (20 min)
-- Tables : FORMATION.CURATED.LINEITEM_UNSORTED et LINEITEM_BY_SHIPDATE (meme contenu,
-- 60 M lignes ; la 2e est triee et clusterisee sur L_SHIPDATE).
-- 1. Sur chaque table : CA (L_EXTENDEDPRICE) des expeditions de mars 1995.
--    Comparez partitions scannees / totales (Query Profile ou GET_QUERY_OPERATOR_STATS).
-- 2. Comparez SYSTEM$CLUSTERING_INFORMATION des deux tables sur (L_SHIPDATE).
-- 3. Meme exercice avec un filtre sur L_ORDERKEY BETWEEN 1000000 AND 1010000.
-- Question : comment choisir une cle de clustering ? Combien ca coute ?
-- =============================================================================
-- >>> SOLUTION
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT SUM(L_EXTENDEDPRICE) FROM FORMATION.CURATED.LINEITEM_UNSORTED
WHERE L_SHIPDATE BETWEEN '1995-03-01' AND '1995-03-31';
SELECT OPERATOR_STATISTICS:pruning:partitions_scanned::INT AS SCANNEES,
       OPERATOR_STATISTICS:pruning:partitions_total::INT   AS TOTAL
FROM TABLE(GET_QUERY_OPERATOR_STATS(LAST_QUERY_ID())) WHERE OPERATOR_TYPE = 'TableScan';
-- ~ toutes les partitions

SELECT SUM(L_EXTENDEDPRICE) FROM FORMATION.CURATED.LINEITEM_BY_SHIPDATE
WHERE L_SHIPDATE BETWEEN '1995-03-01' AND '1995-03-31';
SELECT OPERATOR_STATISTICS:pruning:partitions_scanned::INT AS SCANNEES,
       OPERATOR_STATISTICS:pruning:partitions_total::INT   AS TOTAL
FROM TABLE(GET_QUERY_OPERATOR_STATS(LAST_QUERY_ID())) WHERE OPERATOR_TYPE = 'TableScan';
-- ~ 1-2 % des partitions

SELECT SYSTEM$CLUSTERING_INFORMATION('FORMATION.CURATED.LINEITEM_UNSORTED',  '(L_SHIPDATE)');
SELECT SYSTEM$CLUSTERING_INFORMATION('FORMATION.CURATED.LINEITEM_BY_SHIPDATE', '(L_SHIPDATE)');
-- average_depth / average_overlaps : eleves vs proches de 1

-- Filtre sur L_ORDERKEY : c'est l'inverse (table "naturelle" ~ triee par ORDERKEY)
SELECT COUNT(*) FROM FORMATION.CURATED.LINEITEM_UNSORTED   WHERE L_ORDERKEY BETWEEN 1000000 AND 1010000;
SELECT COUNT(*) FROM FORMATION.CURATED.LINEITEM_BY_SHIPDATE WHERE L_ORDERKEY BETWEEN 1000000 AND 1010000;

-- Reponses :
-- - Une seule organisation physique par table : clusteriser pour les filtres
--   les plus frequents/couteux (dates, colonnes a cardinalite moyenne).
-- - Reserve aux grosses tables (multi-To) dont les requetes filtrent mal.
-- - Automatic Clustering = service serverless facture en continu sur les tables
--   tres modifiees -> mesurer via AUTOMATIC_CLUSTERING_HISTORY.
-- <<< SOLUTION

-- =============================================================================
-- Exercice 4 - Search Optimization Service (10 min)
-- ORDERS_SF10 et ORDERS_SF10_SOS (15 M lignes) ; la 2e a la SOS sur
-- EQUALITY(O_CUSTKEY) et SUBSTRING(O_COMMENT).
-- 1. Recherchez les commandes du client 123456 dans chaque table ; comparez le pruning.
-- 2. Idem avec O_COMMENT ILIKE '%special requests%'... puis '%furiously regular%'.
-- 3. Estimez le cout d'activation sur ORDERS_SF10 (SYSTEM$ESTIMATE_SEARCH_OPTIMIZATION_COSTS).
-- Question : SOS ou clustering ?
-- =============================================================================
-- >>> SOLUTION
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT * FROM FORMATION.CURATED.ORDERS_SF10     WHERE O_CUSTKEY = 123456;
SELECT OPERATOR_STATISTICS:pruning:partitions_scanned::INT AS SCANNEES,
       OPERATOR_STATISTICS:pruning:partitions_total::INT   AS TOTAL
FROM TABLE(GET_QUERY_OPERATOR_STATS(LAST_QUERY_ID())) WHERE OPERATOR_TYPE = 'TableScan';

SELECT * FROM FORMATION.CURATED.ORDERS_SF10_SOS WHERE O_CUSTKEY = 123456;
SELECT OPERATOR_STATISTICS:pruning:partitions_scanned::INT AS SCANNEES,
       OPERATOR_STATISTICS:pruning:partitions_total::INT   AS TOTAL
FROM TABLE(GET_QUERY_OPERATOR_STATS(LAST_QUERY_ID())) WHERE OPERATOR_TYPE = 'TableScan';
-- Dans le Query Profile : "Search Optimization Access" sur la 2e requete

SELECT COUNT(*) FROM FORMATION.CURATED.ORDERS_SF10_SOS WHERE O_COMMENT ILIKE '%furiously regular%';

SELECT SYSTEM$ESTIMATE_SEARCH_OPTIMIZATION_COSTS('FORMATION.CURATED.ORDERS_SF10', 'EQUALITY(O_CUSTKEY)');

-- Reponse : clustering = plages/filtres larges sur peu de colonnes ;
-- SOS = recherches tres selectives (point lookup, LIKE, VARIANT, geo) sur des
-- colonnes a forte cardinalite. Les deux ont un cout de stockage + maintenance.
-- <<< SOLUTION

-- =============================================================================
-- Exercice 5 - Cortex AI Functions sur des avis clients (25 min)
-- 1. Generez REVIEWS : pour 30 pieces de TPCH_SF1.PART, un avis client court en
--    francais (ton negatif / neutre / enthousiaste selon MOD(P_PARTKEY, 3)) avec AI_COMPLETE.
-- 2. Enrichissez chaque avis :
--    - score de sentiment (SNOWFLAKE.CORTEX.SENTIMENT) ;
--    - theme via AI_CLASSIFY parmi : qualite, livraison, prix, service client ;
--    - booleen "probleme de livraison" via AI_FILTER ;
--    - traduction anglaise (SNOWFLAKE.CORTEX.TRANSLATE).
-- 3. Synthese : les 3 principaux irritants, en une requete (AI_AGG).
-- (!) Gardez de petits volumes : facturation au token.
-- =============================================================================
-- >>> SOLUTION
CREATE OR REPLACE TABLE REVIEWS AS
SELECT P_PARTKEY, P_NAME,
       CASE MOD(P_PARTKEY, 3) WHEN 0 THEN 'tres negatif' WHEN 1 THEN 'neutre' ELSE 'enthousiaste' END AS TON_DEMANDE,
       AI_COMPLETE('llama3.1-8b',
         'Redige un avis client de 2 phrases, en francais, au ton ' || TON_DEMANDE ||
         ', sur le produit "' || P_NAME || '". Evoque la qualite, la livraison, le prix ou le service client. ' ||
         'Reponds uniquement par l''avis.') AS REVIEW
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.PART
ORDER BY P_PARTKEY
LIMIT 30;

SELECT * FROM REVIEWS LIMIT 5;

CREATE OR REPLACE TABLE REVIEWS_ENRICHED AS
SELECT P_PARTKEY, P_NAME, TON_DEMANDE, REVIEW,
       SNOWFLAKE.CORTEX.SENTIMENT(REVIEW)                                                       AS SENTIMENT,
       AI_CLASSIFY(REVIEW, ['qualite', 'livraison', 'prix', 'service client']):labels[0]::STRING  AS THEME,
       AI_FILTER(PROMPT('Cet avis client mentionne-t-il un probleme de livraison ? {0}', REVIEW)) AS PB_LIVRAISON,
       SNOWFLAKE.CORTEX.TRANSLATE(REVIEW, 'fr', 'en')                                           AS REVIEW_EN
FROM REVIEWS;

SELECT TON_DEMANDE, ROUND(AVG(SENTIMENT), 2) AS SENTIMENT_MOYEN, COUNT(*)
FROM REVIEWS_ENRICHED GROUP BY 1;            -- coherence ton demande / sentiment mesure ?

SELECT THEME, COUNT(*), COUNT_IF(PB_LIVRAISON) AS NB_PB_LIVRAISON
FROM REVIEWS_ENRICHED GROUP BY 1 ORDER BY 2 DESC;

SELECT AI_AGG(REVIEW, 'Liste en francais les 3 principaux irritants clients, en une phrase chacun.') AS SYNTHESE
FROM REVIEWS_ENRICHED WHERE SENTIMENT < 0;

-- Notes : SENTIMENT est optimise pour l'anglais (comparer sur REVIEW_EN) ;
-- le modele se choisit selon cout/qualite (llama3.1-8b economique, mistral-large2
-- ou claude-* plus qualitatifs). Suivi des couts :
-- SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FUNCTIONS_USAGE_HISTORY (latence ~1h).
-- <<< SOLUTION

-- =============================================================================
-- Exercice 6 - ML natif : Forecast & Anomaly Detection (15 min)
-- 1. Vue V_DAILY_REVENUE (DS TIMESTAMP_NTZ, Y) : CA journalier TPCH_SF1.ORDERS
--    entre 1996-01-01 et 1998-07-31.
-- 2. Entrainez un modele SNOWFLAKE.ML.FORECAST et prevoyez 30 jours.
-- 3. Bonus : SNOWFLAKE.ML.ANOMALY_DETECTION entraine sur 1996-1997, detection sur 1998.
-- Question : que penser de la prevision obtenue ? (regardez la nature des donnees TPCH)
-- =============================================================================
-- >>> SOLUTION
CREATE OR REPLACE VIEW V_DAILY_REVENUE AS
SELECT O_ORDERDATE::TIMESTAMP_NTZ AS DS, SUM(O_TOTALPRICE) AS Y
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_ORDERDATE BETWEEN '1996-01-01' AND '1998-07-31'
GROUP BY 1;

CREATE OR REPLACE SNOWFLAKE.ML.FORECAST FC_REVENUE(
  INPUT_DATA => TABLE(V_DAILY_REVENUE),
  TIMESTAMP_COLNAME => 'DS',
  TARGET_COLNAME => 'Y'
);

CALL FC_REVENUE!FORECAST(FORECASTING_PERIODS => 30);
CREATE OR REPLACE TABLE FORECAST_REVENUE AS SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
SELECT * FROM FORECAST_REVENUE ORDER BY TS;
-- Visualiser dans Snowsight (Chart) : historique + FORECAST / LOWER_BOUND / UPPER_BOUND

-- Bonus anomalies
CREATE OR REPLACE VIEW V_REV_TRAIN AS SELECT * FROM V_DAILY_REVENUE WHERE DS <  '1998-01-01';
CREATE OR REPLACE VIEW V_REV_TEST  AS SELECT * FROM V_DAILY_REVENUE WHERE DS >= '1998-01-01';

CREATE OR REPLACE SNOWFLAKE.ML.ANOMALY_DETECTION AD_REVENUE(
  INPUT_DATA => TABLE(V_REV_TRAIN),
  TIMESTAMP_COLNAME => 'DS',
  TARGET_COLNAME => 'Y',
  LABEL_COLNAME => ''
);
CALL AD_REVENUE!DETECT_ANOMALIES(
  INPUT_DATA => TABLE(V_REV_TEST),
  TIMESTAMP_COLNAME => 'DS',
  TARGET_COLNAME => 'Y'
);
SELECT TS, Y, FORECAST, IS_ANOMALY FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE IS_ANOMALY;

-- Reponse : TPCH est un jeu synthetique sans saisonnalite ni tendance -> prevision
-- quasi plate, intervalles larges. Bon rappel : le modele ne vaut que par le signal
-- des donnees. Sur le projet client, on rejouera l'exercice sur une vraie serie.
-- <<< SOLUTION

-- =============================================================================
-- Exercice 7 - Streamlit in Snowflake (25 min)
-- 1. Snowsight > Projects > Streamlit > + Streamlit App :
--    nom APP_TPCH, emplacement SANDBOX.<vous>, warehouse WH_<vous>.
-- 2. Remplacez le code par celui du fichier streamlit_app.py fourni.
-- 3. Testez les filtres. Ajoutez a l'onglet "Clients" la table CUSTOMER de votre
--    schema (LAB 1) : les donnees sont-elles masquees ? Pourquoi ?
-- 4. Accordez USAGE sur l'app au role ANALYST et testez en ANALYST.
-- =============================================================================
-- >>> SOLUTION
-- Alternative SQL au point 1 (code depose sur un stage) :
-- CREATE STAGE IF NOT EXISTS STG_APPS;
-- PUT file://streamlit_app.py @STG_APPS/tpch_app AUTO_COMPRESS = FALSE OVERWRITE = TRUE;  -- SnowSQL / Snowflake CLI
-- CREATE OR REPLACE STREAMLIT APP_TPCH
--   FROM '@STG_APPS/tpch_app' MAIN_FILE = 'streamlit_app.py'
--   QUERY_WAREHOUSE = WH_P01;

-- Point 3 : l'app s'execute avec les droits de son PROPRIETAIRE (owner's rights).
-- R_Pxx herite de PII_READER -> donnees en clair, pour TOUS les viewers de l'app.
-- C'est un point de vigilance majeur : publier une app = exposer les donnees
-- que voit son proprietaire. Bonne pratique : faire posseder l'app par un role
-- au perimetre minimal (ex. ANALYST).
SET ddl = 'GRANT USAGE ON STREAMLIT APP_TPCH TO ROLE ' || $me || '_ANALYST';
EXECUTE IMMEDIATE $ddl;
-- <<< SOLUTION

-- =============================================================================
-- (!) FIN DE LAB
-- =============================================================================
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
ALTER WAREHOUSE IDENTIFIER($my_wh) SET WAREHOUSE_SIZE = XSMALL;
ALTER WAREHOUSE IDENTIFIER($my_wh) SUSPEND;
