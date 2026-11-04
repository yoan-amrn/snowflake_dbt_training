/* =============================================================================
   LAB 3 - PERFORMANCE - ML - STREAMLIT  (J2 apres-midi, ~1h45)
   Jeu de donnees : TPCH SF10 / SF100 (sample data) + tables preparees par le
   formateur dans FORMATION.CURATED (LINEITEM_UNSORTED, LINEITEM_BY_SHIPDATE,
   ORDERS_SF10, ORDERS_SF10_SOS) par setup/05_lab_prep.sql la veille.
   Cortex AI Functions / Search / Analyst / Agents : absents du trial ->
   demo formateur sur compte payant (demos/J2_cortex_search_analyst_agent.sql)
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
-- A VOUS DE JOUER



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
-- A VOUS DE JOUER



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
-- A VOUS DE JOUER



-- =============================================================================
-- Exercice 4 - Search Optimization Service (10 min)
-- ORDERS_SF10 et ORDERS_SF10_SOS (15 M lignes) ; la 2e a la SOS sur
-- EQUALITY(O_CUSTKEY) et SUBSTRING(O_COMMENT).
-- 1. Recherchez les commandes du client 123456 dans chaque table ; comparez le pruning.
-- 2. Idem avec O_COMMENT ILIKE '%special requests%'... puis '%furiously regular%'.
-- 3. Estimez le cout d'activation sur ORDERS_SF10 (SYSTEM$ESTIMATE_SEARCH_OPTIMIZATION_COSTS).
-- Question : SOS ou clustering ?
-- =============================================================================
-- A VOUS DE JOUER



-- =============================================================================
-- Exercice 5 - ML natif : Forecast & Anomaly Detection (15 min)
-- 1. Vue V_DAILY_REVENUE (DS TIMESTAMP_NTZ, Y) : CA journalier TPCH_SF1.ORDERS
--    entre 1996-01-01 et 1998-07-31.
-- 2. Entrainez un modele SNOWFLAKE.ML.FORECAST et prevoyez 30 jours.
-- 3. Bonus : SNOWFLAKE.ML.ANOMALY_DETECTION entraine sur 1996-1997, detection sur 1998.
-- Question : que penser de la prevision obtenue ? (regardez la nature des donnees TPCH)
-- =============================================================================
-- A VOUS DE JOUER



-- =============================================================================
-- Exercice 6 - Streamlit in Snowflake (25 min)
-- 1. Snowsight > Projects > Streamlit > + Streamlit App :
--    nom APP_TPCH, emplacement SANDBOX.<vous>, warehouse WH_<vous>.
-- 2. Remplacez le code par celui du fichier utils/streamlit_app.py du repo de formation
--    (Projects > Workspaces > From Git repository > utils/streamlit_app.py).
-- 3. Testez les filtres. Ajoutez a l'onglet "Clients" la table CUSTOMER de votre
--    schema (LAB 1) : les donnees sont-elles masquees ? Pourquoi ?
-- 4. Accordez USAGE sur l'app au role ANALYST et testez en ANALYST.
-- =============================================================================
-- A VOUS DE JOUER



-- =============================================================================
-- (!) FIN DE LAB
-- =============================================================================
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
ALTER WAREHOUSE IDENTIFIER($my_wh) SET WAREHOUSE_SIZE = XSMALL;
ALTER WAREHOUSE IDENTIFIER($my_wh) SUSPEND;
