/* =============================================================================
   LAB 1 - GOUVERNANCE & SECURITE  (J1 apres-midi, ~1h45)
   RBAC - Secure Views - Row Access Policy - Dynamic Data Masking - Tags
   Jeu de donnees : TPCH (CUSTOMER enrichi d'email/telephone/adresse, ORDERS)

   Vous travaillez dans VOTRE schema SANDBOX.Pxx avec VOTRE role R_Pxx.
   Executez le bloc "Contexte" en premier a chaque nouvelle session.
   ============================================================================= */

-- =============================================================================
-- Contexte de session (a executer tel quel)
-- =============================================================================
SET me        = CURRENT_USER();            -- ex. P01
SET my_role   = 'R_' || $me;
SET my_wh     = 'WH_' || $me;
SET my_schema = 'SANDBOX.' || $me;
SET r_analyst = $me || '_ANALYST';         -- role que vous allez creer
SET r_pii     = $me || '_PII_READER';      -- role que vous allez creer

USE ROLE      IDENTIFIER($my_role);
USE WAREHOUSE IDENTIFIER($my_wh);
USE SCHEMA    IDENTIFIER($my_schema);

-- (!) Les utilisateurs recents ont DEFAULT_SECONDARY_ROLES = ('ALL') :
-- tous leurs roles sont actifs en meme temps. Pour tester fidelement un role
-- donne, on desactive les roles secondaires. (On en reparle a l'exercice 3.)
USE SECONDARY ROLES NONE;

-- =============================================================================
-- Exercice 0 - Preparer les donnees (5 min)
-- Creez dans votre schema :
--   - CUSTOMER : copie de FORMATION.RAW.CUSTOMER
--   - ORDERS   : copie de SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
-- Verifiez le nombre de lignes par REGION dans CUSTOMER.
-- =============================================================================
-- >>> SOLUTION
CREATE OR REPLACE TABLE CUSTOMER AS SELECT * FROM FORMATION.RAW.CUSTOMER;
CREATE OR REPLACE TABLE ORDERS   AS SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;

SELECT REGION, COUNT(*) AS NB_CLIENTS FROM CUSTOMER GROUP BY REGION ORDER BY 1;
-- <<< SOLUTION

-- =============================================================================
-- Exercice 1 - RBAC : construire une hierarchie de roles (20 min)
-- 1. Creez les roles $r_analyst et $r_pii (utilisez IDENTIFIER($var)).
-- 2. Hierarchie : ANALYST  ->  PII_READER  ->  votre role R_Pxx
--    (PII_READER herite d'ANALYST, et votre role herite de PII_READER).
-- 3. Donnez au role ANALYST : USAGE sur votre warehouse et votre schema.
--    (Ne donnez PAS encore de droits sur les tables.)
-- 4. Accordez les deux roles a votre utilisateur.
-- 5. Inspectez le resultat avec SHOW GRANTS TO ROLE / SHOW GRANTS OF ROLE.
-- Question : pourquoi rattacher les roles fonctionnels a R_Pxx (puis SYSADMIN)
--            plutot que de les laisser "orphelins" ?
-- =============================================================================
-- >>> SOLUTION
CREATE ROLE IF NOT EXISTS IDENTIFIER($r_analyst) COMMENT = 'Lecture des donnees non sensibles';
CREATE ROLE IF NOT EXISTS IDENTIFIER($r_pii)     COMMENT = 'Lecture des donnees personnelles en clair';

GRANT ROLE IDENTIFIER($r_analyst) TO ROLE IDENTIFIER($r_pii);
GRANT ROLE IDENTIFIER($r_pii)     TO ROLE IDENTIFIER($my_role);

GRANT USAGE ON WAREHOUSE IDENTIFIER($my_wh)     TO ROLE IDENTIFIER($r_analyst);
GRANT USAGE ON SCHEMA    IDENTIFIER($my_schema) TO ROLE IDENTIFIER($r_analyst);

GRANT ROLE IDENTIFIER($r_analyst) TO USER IDENTIFIER($me);
GRANT ROLE IDENTIFIER($r_pii)     TO USER IDENTIFIER($me);

SHOW GRANTS TO ROLE IDENTIFIER($r_analyst);   -- ce que le role possede
SHOW GRANTS OF ROLE IDENTIFIER($r_analyst);   -- a qui le role est accorde
SHOW GRANTS TO USER IDENTIFIER($me);

-- Reponse : un role non rattache a SYSADMIN cree des objets que les admins
-- ne voient pas / ne peuvent pas gerer. Best practice : toute hierarchie
-- fonctionnelle remonte a SYSADMIN ; ACCOUNTADMIN reste reserve.
-- NB : les FUTURE GRANTS (GRANT SELECT ON FUTURE TABLES IN SCHEMA ...) evitent
-- de rejouer les grants a chaque nouvelle table ; ils necessitent MANAGE GRANTS
-- (ou un schema MANAGED ACCESS) -> demonstration formateur.
-- <<< SOLUTION

-- =============================================================================
-- Exercice 2 - Vue standard vs Secure View (15 min)
-- 1. Creez une vue standard V_CUSTOMER_STD et une SECURE VIEW V_CUSTOMER_SECURE,
--    toutes deux : CUSTOMER_ID, CUSTOMER_NAME, COUNTRY, SEGMENT
--    des clients de la region 'EUROPE'.
-- 2. Accordez SELECT sur les deux vues au role ANALYST.
-- 3. Passez en role ANALYST :
--    a) interrogez les deux vues ;
--    b) essayez d'interroger directement la table CUSTOMER : que se passe-t-il ?
--    c) SHOW VIEWS : comparez les colonnes "text" et "is_secure".
-- Question : quel est le cout d'une secure view cote optimiseur ?
-- =============================================================================
-- >>> SOLUTION
CREATE OR REPLACE VIEW V_CUSTOMER_STD AS
SELECT CUSTOMER_ID, CUSTOMER_NAME, COUNTRY, SEGMENT
FROM CUSTOMER WHERE REGION = 'EUROPE';

CREATE OR REPLACE SECURE VIEW V_CUSTOMER_SECURE AS
SELECT CUSTOMER_ID, CUSTOMER_NAME, COUNTRY, SEGMENT
FROM CUSTOMER WHERE REGION = 'EUROPE';

GRANT SELECT ON VIEW V_CUSTOMER_STD    TO ROLE IDENTIFIER($r_analyst);
GRANT SELECT ON VIEW V_CUSTOMER_SECURE TO ROLE IDENTIFIER($r_analyst);

USE ROLE IDENTIFIER($r_analyst);
SELECT COUNT(*) FROM V_CUSTOMER_STD;
SELECT COUNT(*) FROM V_CUSTOMER_SECURE;
SELECT COUNT(*) FROM CUSTOMER;   -- [X] erreur : l'acces passe uniquement par les vues

SHOW VIEWS;
SELECT "name", "is_secure", "text" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
-- -> la definition (et donc la logique de filtrage) de la secure view est masquee

USE ROLE IDENTIFIER($my_role);
-- Reponse : l'optimiseur ne "pousse" pas certains predicats/fonctions a travers
-- une secure view (pour eviter les fuites par effets de bord) -> potentiellement
-- moins de pruning. A reserver aux cas ou la definition doit rester cachee
-- (data sharing, logique de securite), pas en systematique.
-- <<< SOLUTION

-- =============================================================================
-- Exercice 3 - Row Access Policy pilotee par une table de mapping (25 min)
-- Objectif : ANALYST ne voit que la region EUROPE ; PII_READER et R_Pxx voient tout.
-- 1. Creez REGION_MAPPING(ROLE_NAME, REGION) et inserez :
--      ($r_analyst, 'EUROPE'), ($r_pii, 'ALL'), ($my_role, 'ALL')
-- 2. Creez la policy RAP_REGION (argument : la region) qui renvoie TRUE si un
--    role actif de la session (IS_ROLE_IN_SESSION) est mappe a la region ou a 'ALL'.
-- 3. Attachez-la a CUSTOMER(REGION) et accordez SELECT sur CUSTOMER a ANALYST.
-- 4. Testez le decompte par region avec ANALYST, puis PII_READER, puis R_Pxx.
-- 5. Refaites le test ANALYST apres USE SECONDARY ROLES ALL. Expliquez.
-- 6. La vue V_CUSTOMER_STD est-elle aussi filtree ?
-- =============================================================================
-- >>> SOLUTION
CREATE OR REPLACE TABLE REGION_MAPPING (ROLE_NAME STRING, REGION STRING);
INSERT INTO REGION_MAPPING VALUES
  ($r_analyst, 'EUROPE'),
  ($r_pii,     'ALL'),
  ($my_role,   'ALL');

CREATE OR REPLACE ROW ACCESS POLICY RAP_REGION
  AS (P_REGION STRING) RETURNS BOOLEAN ->
  EXISTS (
    SELECT 1 FROM REGION_MAPPING m      -- si erreur de resolution : qualifier SANDBOX.Pxx.REGION_MAPPING
    WHERE IS_ROLE_IN_SESSION(m.ROLE_NAME)
      AND m.REGION IN (P_REGION, 'ALL')
  );

ALTER TABLE CUSTOMER ADD ROW ACCESS POLICY RAP_REGION ON (REGION);
GRANT SELECT ON TABLE CUSTOMER TO ROLE IDENTIFIER($r_analyst);

USE ROLE IDENTIFIER($r_analyst);
SELECT REGION, COUNT(*) FROM CUSTOMER GROUP BY 1;   -- EUROPE uniquement

USE ROLE IDENTIFIER($r_pii);
SELECT REGION, COUNT(*) FROM CUSTOMER GROUP BY 1;   -- 5 regions

USE ROLE IDENTIFIER($my_role);
SELECT REGION, COUNT(*) FROM CUSTOMER GROUP BY 1;   -- 5 regions (le proprietaire est filtre aussi !)

-- Piege des roles secondaires
USE ROLE IDENTIFIER($r_analyst);
USE SECONDARY ROLES ALL;
SELECT REGION, COUNT(*) FROM CUSTOMER GROUP BY 1;   -- 5 regions : R_Pxx/PII_READER sont actifs en secondaire
USE SECONDARY ROLES NONE;

-- La policy s'applique a la table, donc a toute vue construite dessus
SELECT COUNT(*) FROM V_CUSTOMER_STD;                -- toujours filtre

USE ROLE IDENTIFIER($my_role);
-- Reponses :
-- - IS_ROLE_IN_SESSION tient compte de la hierarchie ET des roles secondaires,
--   CURRENT_ROLE() seulement du role primaire. Choix a faire consciemment.
-- - Une table de mapping = gouvernance pilotee par la donnee (ajouter une
--   region a un role = INSERT, pas de redeploiement de policy).
-- <<< SOLUTION

-- =============================================================================
-- Exercice 4 - Dynamic Data Masking : policy directe + tag-based masking (30 min)
-- Regle : seuls les roles listes dans PII_ACCESS voient les donnees personnelles.
-- 1. Creez PII_ACCESS(ROLE_NAME) contenant $r_pii.
-- 2. MP_EMAIL (STRING)       : en clair si autorise, sinon partie avant @ -> '*****'.
-- 3. MP_BALANCE (NUMBER(12,2)) : en clair si autorise, sinon arrondi au millier.
-- 4. Appliquez MP_EMAIL sur EMAIL, MP_BALANCE sur ACCOUNT_BALANCE.
-- 5. Tag-based masking :
--    a) tag PII_TYPE avec ALLOWED_VALUES 'EMAIL','PHONE','ADDRESS' ;
--    b) policy MP_PII_STRING : en clair si autorise, sinon '*** MASQUE ***' ;
--    c) associez MP_PII_STRING au tag ;
--    d) taggez PHONE, ADDRESS et EMAIL.
-- 6. Testez avec ANALYST puis PII_READER. Quelle policy s'applique sur EMAIL ?
-- 7. Inventaire : TAG_REFERENCES_ALL_COLUMNS et POLICY_REFERENCES.
-- =============================================================================
-- >>> SOLUTION
CREATE OR REPLACE TABLE PII_ACCESS (ROLE_NAME STRING);
INSERT INTO PII_ACCESS VALUES ($r_pii);

CREATE OR REPLACE MASKING POLICY MP_EMAIL AS (VAL STRING) RETURNS STRING ->
  CASE
    WHEN EXISTS (SELECT 1 FROM PII_ACCESS a WHERE IS_ROLE_IN_SESSION(a.ROLE_NAME)) THEN VAL
    ELSE REGEXP_REPLACE(VAL, '^[^@]+', '*****')
  END;

CREATE OR REPLACE MASKING POLICY MP_BALANCE AS (VAL NUMBER(12,2)) RETURNS NUMBER(12,2) ->
  CASE
    WHEN EXISTS (SELECT 1 FROM PII_ACCESS a WHERE IS_ROLE_IN_SESSION(a.ROLE_NAME)) THEN VAL
    ELSE ROUND(VAL, -3)
  END;

ALTER TABLE CUSTOMER MODIFY COLUMN EMAIL           SET MASKING POLICY MP_EMAIL;
ALTER TABLE CUSTOMER MODIFY COLUMN ACCOUNT_BALANCE SET MASKING POLICY MP_BALANCE;

-- Tag-based masking
CREATE OR REPLACE TAG PII_TYPE ALLOWED_VALUES 'EMAIL', 'PHONE', 'ADDRESS'
  COMMENT = 'Classification des donnees personnelles';

CREATE OR REPLACE MASKING POLICY MP_PII_STRING AS (VAL STRING) RETURNS STRING ->
  CASE
    WHEN EXISTS (SELECT 1 FROM PII_ACCESS a WHERE IS_ROLE_IN_SESSION(a.ROLE_NAME)) THEN VAL
    ELSE '*** MASQUE ***'
  END;

ALTER TAG PII_TYPE SET MASKING POLICY MP_PII_STRING;

ALTER TABLE CUSTOMER MODIFY
  COLUMN PHONE   SET TAG PII_TYPE = 'PHONE',
  COLUMN ADDRESS SET TAG PII_TYPE = 'ADDRESS',
  COLUMN EMAIL   SET TAG PII_TYPE = 'EMAIL';

-- Tests
USE ROLE IDENTIFIER($r_analyst);
SELECT CUSTOMER_NAME, EMAIL, PHONE, ADDRESS, ACCOUNT_BALANCE, REGION FROM CUSTOMER LIMIT 10;
-- EMAIL : *****@exemple.fr (policy directe prioritaire sur le tag)
-- PHONE/ADDRESS : *** MASQUE *** (via le tag) ; BALANCE arrondi ; EUROPE uniquement (RAP)

USE ROLE IDENTIFIER($r_pii);
SELECT CUSTOMER_NAME, EMAIL, PHONE, ADDRESS, ACCOUNT_BALANCE, REGION FROM CUSTOMER LIMIT 10;
-- tout en clair, toutes regions

USE ROLE IDENTIFIER($my_role);

-- Inventaire de gouvernance
SELECT TAG_NAME, TAG_VALUE, COLUMN_NAME
FROM TABLE(INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('CUSTOMER', 'table'));

SELECT POLICY_NAME, POLICY_KIND, REF_COLUMN_NAME, TAG_NAME, POLICY_STATUS
FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(REF_ENTITY_NAME => 'CUSTOMER', REF_ENTITY_DOMAIN => 'table'));
-- <<< SOLUTION

-- =============================================================================
-- Exercice 5 (bonus) - Gouvernance de bout en bout (10 min)
-- 1. Creez la secure view V_CA_CLIENT : par client, CA total (ORDERS.O_TOTALPRICE)
--    avec CUSTOMER_NAME, EMAIL, REGION. Accordez-la a ANALYST.
-- 2. En ANALYST : les policies de CUSTOMER s'appliquent-elles a travers la vue ?
-- 3. En ANALYST, essayez un CREATE TABLE AS SELECT depuis la vue :
--    les donnees copiees sont-elles masquees ? Pourquoi est-ce important ?
-- =============================================================================
-- >>> SOLUTION
CREATE OR REPLACE SECURE VIEW V_CA_CLIENT AS
SELECT c.CUSTOMER_ID, c.CUSTOMER_NAME, c.EMAIL, c.REGION,
       COUNT(o.O_ORDERKEY) AS NB_COMMANDES, SUM(o.O_TOTALPRICE) AS CA_TOTAL
FROM CUSTOMER c
LEFT JOIN ORDERS o ON o.O_CUSTKEY = c.CUSTOMER_ID
GROUP BY ALL;

GRANT SELECT ON VIEW V_CA_CLIENT TO ROLE IDENTIFIER($r_analyst);

USE ROLE IDENTIFIER($r_analyst);
SELECT * FROM V_CA_CLIENT ORDER BY CA_TOTAL DESC LIMIT 10;   -- masque + filtre EUROPE

-- ANALYST n'a pas CREATE TABLE sur le schema -> erreur attendue.
-- (Si on lui accorde le droit, la table creee contient les valeurs DEJA masquees :
--  le masquage s'applique a la lecture, une copie ne "demasque" jamais.)
CREATE TABLE COPIE_CA AS SELECT * FROM V_CA_CLIENT;

USE ROLE IDENTIFIER($my_role);
-- <<< SOLUTION

-- =============================================================================
-- Fin du LAB 1 - rien a suspendre. Les objets resteront utiles au LAB 3 (Streamlit).
-- =============================================================================
