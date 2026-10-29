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
-- A VOUS DE JOUER



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
-- A VOUS DE JOUER



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
-- A VOUS DE JOUER



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
-- A VOUS DE JOUER



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
-- A VOUS DE JOUER



-- =============================================================================
-- Exercice 5 (bonus) - Gouvernance de bout en bout (10 min)
-- 1. Creez la secure view V_CA_CLIENT : par client, CA total (ORDERS.O_TOTALPRICE)
--    avec CUSTOMER_NAME, EMAIL, REGION. Accordez-la a ANALYST.
-- 2. En ANALYST : les policies de CUSTOMER s'appliquent-elles a travers la vue ?
-- 3. En ANALYST, essayez un CREATE TABLE AS SELECT depuis la vue :
--    les donnees copiees sont-elles masquees ? Pourquoi est-ce important ?
-- =============================================================================
-- A VOUS DE JOUER



-- =============================================================================
-- Fin du LAB 1 - rien a suspendre. Les objets resteront utiles au LAB 3 (Streamlit).
-- =============================================================================
