/* =============================================================================
   EXERCICE J1 matin - DIAGNOSTIQUER LE BON TYPE DE SCALING  (~25 min)
   Scale up / scale out / across : a partir de requetes reellement executees.

   Le formateur a fait tourner trois lots de requetes (A, B, C) sur un warehouse
   XS mono-cluster, puis copie leur historique dans FORMATION.CURATED.SCALING_QUERIES.
   Votre mission : pour chaque lot, dire quel est le probleme et quel type de
   scaling le resout, chiffres a l'appui.

   Colonnes utiles de SCALING_QUERIES :
     LOT, TYPE_REQUETE (COURTE / LOURDE), WAREHOUSE_NAME, WAREHOUSE_SIZE, CLUSTER_NUMBER,
     START_TIME, END_TIME, DUREE_TOTALE_S, EXECUTION_S, FILE_ATTENTE_S (attente de
     ressources), DEMARRAGE_S (demarrage du warehouse), BYTES_SCANNED,
     BYTES_SPILLED_LOCAL, BYTES_SPILLED_REMOTE (donnees debordees sur disque)
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
-- Exercice 1 - Premier coup d'oeil (5 min)
-- Pour chaque LOT et TYPE_REQUETE : nombre de requetes, duree totale moyenne,
-- temps d'execution moyen, temps d'attente moyen.
-- Question : dans quel lot les requetes passent-elles plus de temps a attendre
--            qu'a s'executer ?
-- =============================================================================
-- >>> SOLUTION
SELECT LOT, TYPE_REQUETE, COUNT(*) AS NB,
       ROUND(AVG(DUREE_TOTALE_S), 1) AS DUREE_MOY_S,
       ROUND(AVG(EXECUTION_S), 1)    AS EXEC_MOY_S,
       ROUND(AVG(FILE_ATTENTE_S), 1) AS ATTENTE_MOY_S
FROM FORMATION.CURATED.SCALING_QUERIES
WHERE LOT IN ('A', 'B', 'C')
GROUP BY 1, 2 ORDER BY 1, 2;
-- Reponse : lot A (et les courtes du lot C) : l'attente depasse largement
-- l'execution. Le lot B n'attend pas, mais s'execute longtemps.
-- <<< SOLUTION

-- =============================================================================
-- Exercice 2 - Mesurer la concurrence (5 min)
-- Pour chaque lot, calculez le nombre maximal de requetes presentes en meme temps
-- sur le warehouse (en cours OU en attente).
-- Indice : auto-jointure de la table sur elle-meme : la requete b est presente
-- au demarrage de la requete a si b.START_TIME <= a.START_TIME < b.END_TIME.
-- =============================================================================
-- >>> SOLUTION
WITH q AS (SELECT * FROM FORMATION.CURATED.SCALING_QUERIES WHERE LOT IN ('A', 'B', 'C'))
SELECT a.LOT, MAX(nb) AS CONCURRENCE_MAX
FROM (SELECT a.LOT, a.QUERY_ID, COUNT(*) AS nb
      FROM q a JOIN q b
        ON b.LOT = a.LOT AND b.START_TIME <= a.START_TIME AND b.END_TIME > a.START_TIME
      GROUP BY 1, 2) a
GROUP BY 1 ORDER BY 1;
-- Reponse : A ~16, B = 1, C ~10. Un warehouse n'execute qu'un nombre limite de
-- requetes a la fois : au-dela, elles patientent en file (FILE_ATTENTE_S).
-- <<< SOLUTION

-- =============================================================================
-- Exercice 3 - Chercher les signes d'un warehouse trop petit (5 min)
-- Pour chaque lot : volume scanne (Go), volume deborde sur disque local et
-- distant (Go), temps d'execution maximal.
-- Question : quel lot montre que la requete elle-meme manque de memoire ?
-- =============================================================================
-- >>> SOLUTION
SELECT LOT, TYPE_REQUETE,
       ROUND(MAX(BYTES_SCANNED)        / POWER(1024, 3), 2) AS GO_SCANNES,
       ROUND(MAX(BYTES_SPILLED_LOCAL)  / POWER(1024, 3), 2) AS GO_SPILL_LOCAL,
       ROUND(MAX(BYTES_SPILLED_REMOTE) / POWER(1024, 3), 2) AS GO_SPILL_DISTANT,
       ROUND(MAX(EXECUTION_S), 1) AS EXEC_MAX_S
FROM FORMATION.CURATED.SCALING_QUERIES
WHERE LOT IN ('A', 'B', 'C')
GROUP BY 1, 2 ORDER BY 1, 2;
-- Reponse : lot B (et les lourdes du lot C) : spilling = la memoire du warehouse
-- ne suffit pas, les donnees debordent sur disque (local, puis distant = pire).
-- <<< SOLUTION

-- =============================================================================
-- Exercice 4 - Votre diagnostic (5 min)
-- Completez le tableau ci-dessous dans votre schema, une ligne par lot :
--   LOT, SYMPTOME (ce que montrent les chiffres), SCALING (UP / OUT / ACROSS),
--   COMMANDE (l'ALTER WAREHOUSE ou l'organisation que vous proposez).
-- Puis confrontez votre reponse a celle de vos voisins.
-- =============================================================================
-- >>> SOLUTION
CREATE OR REPLACE TABLE DIAGNOSTIC_SCALING (LOT STRING, SYMPTOME STRING, SCALING STRING, COMMANDE STRING);
INSERT INTO DIAGNOSTIC_SCALING VALUES
  ('A', 'Requetes courtes, attente >> execution, forte concurrence, pas de spilling',
        'OUT', 'ALTER WAREHOUSE WH_SCALING_DEMO SET MIN_CLUSTER_COUNT = 1 MAX_CLUSTER_COUNT = 4'),
  ('B', 'Une seule requete, pas d''attente, execution longue avec spilling',
        'UP',  'ALTER WAREHOUSE WH_SCALING_DEMO SET WAREHOUSE_SIZE = MEDIUM'),
  ('C', 'Les courtes (BI) attendent derriere les lourdes (ETL) sur le meme warehouse',
        'ACROSS', 'Un warehouse ETL et un warehouse BI distincts, chacun dimensionne pour sa charge');
SELECT * FROM DIAGNOSTIC_SCALING ORDER BY LOT;
-- Points a faire ressortir :
-- - Scale up n'aide PAS le lot A : plus gros, le warehouse execute toujours peu de
--   requetes a la fois ; il faut plus de clusters, pas des clusters plus gros.
-- - Scale out n'aide PAS le lot B : une requete ne s'execute que sur un cluster.
-- - Le lot C se « resout » aussi en scale out ou up, mais en payant pour la BI la
--   taille de l'ETL : isoler les usages est plus lisible et plus economique.
-- <<< SOLUTION

-- =============================================================================
-- Exercice 5 - Avant / apres (5 min, apres la demo de remediation)
-- Le formateur a rejoue les lots avec sa remediation : A2 (multi-cluster),
-- B2 (MEDIUM), C2 (deux warehouses).
-- 1. Comparez pour A/A2, B/B2, C/C2 : duree du lot (fin de la derniere requete -
--    debut de la premiere), attente moyenne, spilling, clusters utilises.
-- 2. Estimez le cout de chaque lot en credits :
--    (duree du lot en heures) x (credits/heure de la taille) x (clusters utilises)
--    XSMALL = 1, SMALL = 2, MEDIUM = 4 credits/h.
-- Question : la remediation coute-t-elle plus cher ? Qu'a-t-on gagne ?
-- =============================================================================
-- >>> SOLUTION
WITH lots AS (
  SELECT LOT, REGEXP_REPLACE(LOT, '2$', '') AS SCENARIO,
         IFF(ENDSWITH(LOT, '2'), 'APRES', 'AVANT') AS PHASE, *
  FROM FORMATION.CURATED.SCALING_QUERIES
)
SELECT SCENARIO, PHASE,
       DATEDIFF(second, MIN(START_TIME), MAX(END_TIME))         AS DUREE_LOT_S,
       ROUND(AVG(FILE_ATTENTE_S), 1)                            AS ATTENTE_MOY_S,
       ROUND(MAX(BYTES_SPILLED_LOCAL) / POWER(1024, 3), 2)      AS GO_SPILL_MAX,
       COUNT(DISTINCT WAREHOUSE_NAME || '-' || CLUSTER_NUMBER)  AS CLUSTERS_UTILISES,
       LISTAGG(DISTINCT WAREHOUSE_SIZE, ', ')                   AS TAILLES,
       ROUND(DATEDIFF(second, MIN(START_TIME), MAX(END_TIME)) / 3600
             * MAX(DECODE(UPPER(WAREHOUSE_SIZE), 'X-SMALL', 1, 'XSMALL', 1, 'SMALL', 2, 'MEDIUM', 4, 1))
             * COUNT(DISTINCT WAREHOUSE_NAME || '-' || CLUSTER_NUMBER), 3) AS CREDITS_ESTIMES
FROM lots
GROUP BY 1, 2 ORDER BY 1, 2 DESC;
-- Reponses attendues :
-- - A2 : plusieurs clusters (CLUSTER_NUMBER 1..4), attente quasi nulle, lot ~3-4x
--   plus court. Cout comparable : 4 clusters pendant 1/4 du temps.
-- - B2 : plus de spilling, execution ~3-4x plus rapide, cout comparable
--   (4 credits/h pendant ~1/4 du temps) : c'est le scale up « gratuit ».
-- - C2 : les courtes n'attendent plus ; cout = deux petits warehouses.
-- - L'estimation est grossiere (minimum de 60 s a chaque demarrage, clusters qui
--   restent allumes apres la charge) : la vraie facture se lit dans
--   WAREHOUSE_METERING_HISTORY (cf. FinOps cet apres-midi).
-- <<< SOLUTION

-- =============================================================================
-- Bonus (J1 apres-midi, FinOps) - Voir le scale out / scale in dans l'historique
-- ACCOUNT_USAGE a une latence de 45 min a 3 h : a faire apres le dejeuner.
-- Listez les evenements du warehouse WH_SCALING_DEMO de la matinee
-- (demarrages / arrets de clusters, redimensionnements).
-- =============================================================================
-- >>> SOLUTION
SELECT TIMESTAMP, EVENT_NAME, EVENT_REASON, EVENT_STATE, SIZE, CLUSTER_NUMBER
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_EVENTS_HISTORY
WHERE WAREHOUSE_NAME = 'WH_SCALING_DEMO'
  AND TIMESTAMP >= DATEADD(hour, -12, CURRENT_TIMESTAMP())
ORDER BY TIMESTAMP;
-- On y voit les clusters 2, 3, 4 demarrer pendant le lot A2 (scale out) puis
-- s'arreter un par un quelques minutes apres (scale in).
-- <<< SOLUTION
