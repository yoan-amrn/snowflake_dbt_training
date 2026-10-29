/* =============================================================================
   DEMO J1 apres-midi - DATA SHARING & MARKETPLACE
   Compte fournisseur : TRIAL (ACCOUNTADMIN)  -  Compte consommateur : PAID
   Les deux comptes doivent etre dans la meme region pour un share direct ;
   sinon passer par un listing (auto-fulfillment cross-region).
   (!) Certains comptes trial ne peuvent pas ajouter de comptes consommateurs :
       dans ce cas montrer la partie fournisseur puis le Marketplace uniquement.
   ============================================================================= */

-- =============================================================================
-- PARTIE 1 - Fournisseur (TRIAL)
-- =============================================================================
USE ROLE FORMATION_ADMIN;
USE WAREHOUSE WH_ADMIN;

-- Donnees a partager : agregat materialise (on ne re-partage pas SNOWFLAKE_SAMPLE_DATA,
-- qui est lui-meme un share) + secure view obligatoire pour un share
CREATE OR REPLACE TABLE FORMATION.CURATED.REVENUE_BY_NATION AS
SELECT r.R_NAME AS REGION, n.N_NAME AS NATION, YEAR(o.O_ORDERDATE) AS ANNEE,
       COUNT(*) AS NB_COMMANDES, SUM(o.O_TOTALPRICE) AS CA
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS   o
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER c ON c.C_CUSTKEY   = o.O_CUSTKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION   n ON n.N_NATIONKEY = c.C_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION   r ON r.R_REGIONKEY = n.N_REGIONKEY
GROUP BY ALL;

CREATE OR REPLACE SECURE VIEW FORMATION.CURATED.V_SHARE_REVENUE AS
SELECT REGION, NATION, ANNEE, NB_COMMANDES, CA
FROM FORMATION.CURATED.REVENUE_BY_NATION
WHERE ANNEE >= 1996;

USE ROLE ACCOUNTADMIN;
CREATE SHARE IF NOT EXISTS SH_FORMATION COMMENT = 'Demo data sharing formation';
GRANT USAGE  ON DATABASE FORMATION                        TO SHARE SH_FORMATION;
GRANT USAGE  ON SCHEMA   FORMATION.CURATED                TO SHARE SH_FORMATION;
GRANT SELECT ON VIEW     FORMATION.CURATED.V_SHARE_REVENUE TO SHARE SH_FORMATION;

SHOW GRANTS TO SHARE SH_FORMATION;

-- Identifiant du compte consommateur (a lire sur le compte PAID : SELECT CURRENT_ORGANIZATION_NAME() || '.' || CURRENT_ACCOUNT_NAME();)
-- ALTER SHARE SH_FORMATION ADD ACCOUNTS = <org>.<compte_paid>;

-- Points cles :
-- - Aucune copie : le consommateur lit le stockage du fournisseur, en temps reel.
-- - Le consommateur paie son compute ; le fournisseur, son stockage.
-- - Secure view = la logique de filtrage n'est pas visible du consommateur.
-- - Partage "par client" : filtrer sur CURRENT_ACCOUNT() dans la secure view
--   ou via une table de mapping (meme logique que la RAP du LAB 1).

-- =============================================================================
-- PARTIE 2 - Consommateur (PAID)
-- =============================================================================
-- USE ROLE ACCOUNTADMIN;
-- SHOW SHARES;                                             -- INBOUND : SH_FORMATION
-- CREATE DATABASE FORMATION_PARTAGEE FROM SHARE <org>.<compte_trial>.SH_FORMATION;
-- GRANT IMPORTED PRIVILEGES ON DATABASE FORMATION_PARTAGEE TO ROLE SYSADMIN;
-- SELECT * FROM FORMATION_PARTAGEE.CURATED.V_SHARE_REVENUE LIMIT 10;
-- Montrer cote fournisseur : un INSERT dans REVENUE_BY_NATION est visible immediatement.

-- =============================================================================
-- PARTIE 3 - Partage interne et Marketplace (UI Snowsight, TRIAL)
-- =============================================================================
-- - Listings internes (Organizational listings) : partage entre comptes d'une meme
--   organisation, avec catalogue interne, gouvernance et auto-fulfillment.
-- - Marketplace : Data Products > Marketplace, rechercher un jeu gratuit
--   (ex. meteo, calendriers, donnees publiques INSEE / Weather Source...) > Get.
--   La base apparait comme une base partagee, interrogeable immediatement :
-- SHOW DATABASES;                         -- kind = IMPORTED DATABASE
-- SELECT * FROM <base_marketplace>.<schema>.<table> LIMIT 10;
-- - Cas d'usage : enrichissement (meteo x frequentation), partage avec partenaires,
--   monetisation, Native Apps.

-- Nettoyage
-- DROP SHARE SH_FORMATION;
