-- =====================================================================
-- DEMO CORTEX AGENT - Analyse des pannes réseau Métro / Tram (Lyon)
-- 04 - GENERATION DES INCIDENTS ET INTERVENTIONS (24 derniers mois)
-- ---------------------------------------------------------------------
-- ~7 500 incidents et ~9 000 interventions. Durée : < 1 min en XSMALL.
--
-- "Histoires" cachées dans les données, à faire découvrir par l'agent :
--   1. Ligne B : mise en service d'un nouveau système CBTC il y a 18 mois
--      -> pic de pannes de signalisation (perte de communication CBTC)
--      pendant ~8 mois, puis retour à la normale.
--   2. Ligne D : escalators chroniquement défaillants (x2,5), réparations
--      plus longues (sous-traitant), surtout Bellecour.
--   3. Ligne A : rames MPL 75 vieillissantes -> plus de pannes de traction.
--   4. Météo : gel/neige -> aiguillages & caténaires tram ; orages ->
--      caténaires & sous-stations ; canicule -> climatisation des rames.
--   5. Heures de pointe : plus d'incidents (portes, malaises voyageurs,
--      collisions tram) et plus de voyageurs impactés.
--   6. Légère amélioration globale de la fiabilité sur la période.
-- =====================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA DB_YAR.MAINTENANCE;

TRUNCATE TABLE IF EXISTS FACT_INTERVENTION;
TRUNCATE TABLE IF EXISTS FACT_INCIDENT;

-- ---------------------------------------------------------------------
-- 1. Nombre d'incidents par jour (météo, week-end, tendance, CBTC)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY TABLE TMP_JOURS AS
SELECT m.DATE_JOUR,
       m.EVENEMENT_METEO,
       CASE WHEN m.DATE_JOUR >= DATEADD(month, -18, CURRENT_DATE())
            THEN GREATEST(0, 1 - DATEDIFF(day, DATEADD(month, -18, CURRENT_DATE()), m.DATE_JOUR) / 240)
            ELSE 0 END AS FACTEUR_CBTC,
       GREATEST(0, ROUND(
           11
         * IFF(DAYOFWEEKISO(m.DATE_JOUR) >= 6, 0.7, 1.0)
         * CASE m.EVENEMENT_METEO
             WHEN 'Neige' THEN 1.8 WHEN 'Gel' THEN 1.3 WHEN 'Canicule' THEN 1.4
             WHEN 'Orage' THEN 1.5 WHEN 'Tempête / vent fort' THEN 1.4 ELSE 1.0 END
         * (1.05 - 0.10 * DATEDIFF(day, DATEADD(month, -24, CURRENT_DATE()), m.DATE_JOUR) / 730)
         + NORMAL(0, 2.5, RANDOM())
       )) AS NB_INCIDENTS_JOUR
FROM METEO_JOURNALIERE m
WHERE m.DATE_JOUR < CURRENT_DATE();

-- ---------------------------------------------------------------------
-- 2. Un enregistrement par incident + heure de début (pics de pointe)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY TABLE TMP_INC_RAW AS
WITH seq AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 60))
)
SELECT j.*, s.n AS NUM_DANS_JOUR, UNIFORM(0, 99, RANDOM()) AS U_HEURE
FROM TMP_JOURS j
JOIN seq s ON s.n <= j.NB_INCIDENTS_JOUR;

CREATE OR REPLACE TEMPORARY TABLE TMP_INC_H AS
SELECT r.*,
       CASE WHEN U_HEURE < 3  THEN UNIFORM(0, 4, RANDOM())     -- nuit (maintenance)
            WHEN U_HEURE < 8  THEN UNIFORM(5, 6, RANDOM())     -- début de service
            WHEN U_HEURE < 33 THEN UNIFORM(7, 9, RANDOM())     -- pointe du matin
            WHEN U_HEURE < 53 THEN UNIFORM(10, 15, RANDOM())   -- heures creuses
            WHEN U_HEURE < 78 THEN UNIFORM(16, 19, RANDOM())   -- pointe du soir
            WHEN U_HEURE < 96 THEN UNIFORM(20, 22, RANDOM())   -- soirée
            ELSE 23 END AS HEURE
FROM TMP_INC_RAW r;

CREATE OR REPLACE TEMPORARY TABLE TMP_INC AS
SELECT ROW_NUMBER() OVER (ORDER BY DATE_JOUR, HEURE, NUM_DANS_JOUR) AS INC_SEQ,
       h.*,
       DATEADD(minute, HEURE * 60 + UNIFORM(0, 59, RANDOM()), h.DATE_JOUR::TIMESTAMP_NTZ) AS DATE_HEURE_DEBUT
FROM TMP_INC_H h;

-- ---------------------------------------------------------------------
-- 3. Tirage pondéré de l'équipement en panne
--    (tirage exponentiel : clé = -ln(U) / poids, on garde la plus petite)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY TABLE TMP_INC_EQUIP AS
SELECT i.*,
       e.EQUIPEMENT_ID, e.TYPE_EQUIPEMENT, e.LIGNE_ID, e.STATION_ID,
       l.MODE_TRANSPORT, l.FREQUENTATION_JOUR_MOY, l.INTERVALLE_POINTE_MIN,
       r.NIVEAU, r.EQUIPE_ID AS EQUIPE_SPECIALISTE,
       -LN(UNIFORM(0.000001::FLOAT, 1::FLOAT, RANDOM())) / (
           r.POIDS_DEFAILLANCE
           -- vieillissement
         * (1 + DATEDIFF(year, e.DATE_MISE_EN_SERVICE, i.DATE_JOUR) / 40)
           -- histoires lignes
         * CASE
             WHEN e.STATION_ID IN ('A03','D05') AND e.TYPE_EQUIPEMENT = 'Escalator' THEN 3.5
             WHEN e.LIGNE_ID = 'D' AND e.TYPE_EQUIPEMENT = 'Escalator'             THEN 2.5
             WHEN e.LIGNE_ID = 'A' AND e.TYPE_EQUIPEMENT = 'Rame'                  THEN 1.6
             WHEN e.LIGNE_ID = 'B' AND e.TYPE_EQUIPEMENT = 'Signalisation'         THEN 1 + 15 * i.FACTEUR_CBTC
             ELSE 1 END
           -- météo
         * CASE
             WHEN i.EVENEMENT_METEO IN ('Gel','Neige')
                  AND e.TYPE_EQUIPEMENT IN ('Aiguillage','Caténaire')                                     THEN 6
             WHEN i.EVENEMENT_METEO IN ('Orage','Tempête / vent fort')
                  AND e.TYPE_EQUIPEMENT IN ('Caténaire','Sous-station d''alimentation')                   THEN 5
             WHEN i.EVENEMENT_METEO = 'Canicule'
                  AND e.TYPE_EQUIPEMENT IN ('Rame','Sous-station d''alimentation','Ventilation / désenfumage') THEN 2.5
             WHEN i.EVENEMENT_METEO IN ('Pluie','Orage') AND e.TYPE_EQUIPEMENT = 'Escalator'             THEN 1.5
             ELSE 1 END
           -- la nuit, pas de rames en circulation
         * IFF(i.HEURE BETWEEN 1 AND 4 AND e.TYPE_EQUIPEMENT = 'Rame', 0.1, 1)
       ) AS CLE_TIRAGE_EQUIP
FROM TMP_INC i
CROSS JOIN DIM_EQUIPEMENT e
JOIN REF_TYPE_EQUIPEMENT r ON r.TYPE_EQUIPEMENT = e.TYPE_EQUIPEMENT
JOIN DIM_LIGNE l          ON l.LIGNE_ID = e.LIGNE_ID
QUALIFY ROW_NUMBER() OVER (PARTITION BY i.INC_SEQ ORDER BY CLE_TIRAGE_EQUIP) = 1;

-- ---------------------------------------------------------------------
-- 4. Localisation : pour le matériel roulant / l'infrastructure,
--    on rattache l'incident à une station de la ligne
-- ---------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY TABLE TMP_INC_LOC AS
SELECT ie.*, COALESCE(ie.STATION_ID, s.STATION_ID) AS STATION_INCIDENT
FROM TMP_INC_EQUIP ie
LEFT JOIN DIM_STATION s
  ON ie.STATION_ID IS NULL AND s.LIGNE_ID = ie.LIGNE_ID
QUALIFY ROW_NUMBER() OVER (PARTITION BY ie.INC_SEQ ORDER BY RANDOM()) = 1;

-- ---------------------------------------------------------------------
-- 5. Tirage pondéré du type de panne (selon équipement, mode, météo...)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY TABLE TMP_INC_PANNE AS
SELECT x.*,
       p.TYPE_PANNE_ID, p.CATEGORIE_PANNE, p.GRAVITE_TYPIQUE, p.DUREE_MOYENNE_MIN, p.IMPACT_SERVICE_TYPIQUE,
       -LN(UNIFORM(0.000001::FLOAT, 1::FLOAT, RANDOM())) / (
           p.POIDS
         * CASE
             WHEN p.CONDITION_DECLENCHANTE = 'GEL'      AND x.EVENEMENT_METEO IN ('Gel','Neige')                 THEN 8
             WHEN p.CONDITION_DECLENCHANTE = 'GEL'                                                              THEN 0.05
             WHEN p.CONDITION_DECLENCHANTE = 'CHALEUR'  AND x.EVENEMENT_METEO = 'Canicule'                      THEN 8
             WHEN p.CONDITION_DECLENCHANTE = 'CHALEUR'  AND MONTH(x.DATE_JOUR) BETWEEN 6 AND 8                  THEN 2
             WHEN p.CONDITION_DECLENCHANTE = 'CHALEUR'                                                          THEN 0.1
             WHEN p.CONDITION_DECLENCHANTE = 'INTEMPERIES' AND x.EVENEMENT_METEO IN ('Orage','Tempête / vent fort','Pluie') THEN 5
             WHEN p.CONDITION_DECLENCHANTE = 'CBTC'     AND x.LIGNE_ID = 'B'                                    THEN 1 + 20 * x.FACTEUR_CBTC
             WHEN p.CONDITION_DECLENCHANTE = 'CBTC'     AND x.LIGNE_ID = 'D'                                    THEN 1
             WHEN p.CONDITION_DECLENCHANTE = 'CBTC'                                                             THEN 0.00001
             WHEN p.CONDITION_DECLENCHANTE = 'POINTE'   AND x.HEURE IN (7,8,9,17,18,19)                         THEN 3
             ELSE 1 END
       ) AS CLE_TIRAGE_PANNE
FROM TMP_INC_LOC x
JOIN REF_TYPE_PANNE p
  ON p.TYPE_EQUIPEMENT = x.TYPE_EQUIPEMENT
 AND (p.MODE_APPLICABLE IS NULL OR p.MODE_APPLICABLE = x.MODE_TRANSPORT)
QUALIFY ROW_NUMBER() OVER (PARTITION BY x.INC_SEQ ORDER BY CLE_TIRAGE_PANNE) = 1;

-- ---------------------------------------------------------------------
-- 6. Gravité, durée, source de signalement
-- ---------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY TABLE TMP_INC_FINAL AS
SELECT x.*,
       CASE WHEN UNIFORM(1, 10, RANDOM()) = 1 THEN LEAST(4, x.GRAVITE_TYPIQUE + 1)
            WHEN UNIFORM(1, 10, RANDOM()) = 1 THEN GREATEST(1, x.GRAVITE_TYPIQUE - 1)
            ELSE x.GRAVITE_TYPIQUE END AS GRAVITE,
       GREATEST(3, ROUND(
           x.DUREE_MOYENNE_MIN
         * (0.35 + 2.3 * POW(UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()), 1.6))
         * IFF(x.LIGNE_ID = 'D' AND x.TYPE_EQUIPEMENT = 'Escalator', 1.6, 1)
         * IFF(x.HEURE BETWEEN 1 AND 4, 0.7, 1)
       )) AS DUREE_CALC,
       UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS U_SOURCE
FROM TMP_INC_PANNE x;

-- ---------------------------------------------------------------------
-- 7. Chargement FACT_INCIDENT
-- ---------------------------------------------------------------------
INSERT INTO FACT_INCIDENT
  (INCIDENT_ID, DATE_INCIDENT, DATE_HEURE_DEBUT, DATE_HEURE_FIN, DUREE_MINUTES, LIGNE_ID, STATION_ID,
   EQUIPEMENT_ID, TYPE_PANNE_ID, GRAVITE, IMPACT_SERVICE, NB_VOYAGEURS_IMPACTES, NB_COURSES_SUPPRIMEES,
   SOURCE_SIGNALEMENT, STATUT)
WITH f AS (
  SELECT t.*,
         DATEADD(minute, DUREE_CALC, DATE_HEURE_DEBUT) AS FIN_THEORIQUE,
         DATEADD(minute, DUREE_CALC, DATE_HEURE_DEBUT) > CURRENT_TIMESTAMP()::TIMESTAMP_NTZ AS EN_COURS,
         IFF(HEURE BETWEEN 1 AND 4, 'Aucun', IMPACT_SERVICE_TYPIQUE) AS IMPACT
  FROM TMP_INC_FINAL t
)
SELECT 'INC-' || LPAD(INC_SEQ, 6, '0'),
       DATE_JOUR,
       DATE_HEURE_DEBUT,
       IFF(EN_COURS, NULL, FIN_THEORIQUE),
       IFF(EN_COURS, NULL, DUREE_CALC),
       LIGNE_ID,
       STATION_INCIDENT,
       EQUIPEMENT_ID,
       TYPE_PANNE_ID,
       GRAVITE,
       IMPACT,
       ROUND(
           CASE IMPACT WHEN 'Interruption totale' THEN 1.0 WHEN 'Interruption partielle' THEN 0.45
                       WHEN 'Ralentissement' THEN 0.15 ELSE 0 END
         * FREQUENTATION_JOUR_MOY / 1140 * DUREE_CALC
         * CASE WHEN HEURE IN (7,8,9,17,18,19) THEN 1.9 ELSE 0.75 END
         * IFF(DAYOFWEEKISO(DATE_JOUR) >= 6, 0.6, 1)
       ),
       CASE IMPACT WHEN 'Interruption totale'    THEN ROUND(2 * DUREE_CALC / INTERVALLE_POINTE_MIN)
                   WHEN 'Interruption partielle' THEN ROUND(DUREE_CALC / INTERVALLE_POINTE_MIN)
                   ELSE 0 END,
       CASE
         WHEN NIVEAU = 'LIGNE'  THEN IFF(U_SOURCE < 0.7, 'Supervision PCC', 'Conducteur')
         WHEN NIVEAU = 'FLOTTE' THEN
              CASE WHEN CATEGORIE_PANNE = 'Externe' AND U_SOURCE < 0.3 THEN 'Voyageur'
                   WHEN LIGNE_ID IN ('B','D') THEN 'Supervision PCC'
                   ELSE 'Conducteur' END
         ELSE CASE WHEN U_SOURCE < 0.45 THEN 'Télésurveillance des équipements'
                   WHEN U_SOURCE < 0.80 THEN 'Agent de station'
                   ELSE 'Voyageur' END
       END,
       IFF(EN_COURS, 'En cours', 'Clos')
FROM f;

-- ---------------------------------------------------------------------
-- 8. Interventions
-- ---------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY TABLE TMP_INTER AS
WITH inc AS (
  SELECT i.INCIDENT_ID, i.DATE_HEURE_DEBUT, i.DATE_HEURE_FIN, i.DUREE_MINUTES, i.GRAVITE, i.STATUT, i.LIGNE_ID,
         p.CATEGORIE_PANNE, e.TYPE_EQUIPEMENT, l.MODE_TRANSPORT, r.EQUIPE_ID AS EQUIPE_SPECIALISTE,
         COALESCE(i.DUREE_MINUTES,
                  DATEDIFF(minute, i.DATE_HEURE_DEBUT, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ)) AS DUREE_REF
  FROM FACT_INCIDENT i
  JOIN REF_TYPE_PANNE p      ON p.TYPE_PANNE_ID = i.TYPE_PANNE_ID
  JOIN DIM_EQUIPEMENT e      ON e.EQUIPEMENT_ID = i.EQUIPEMENT_ID
  JOIN REF_TYPE_EQUIPEMENT r ON r.TYPE_EQUIPEMENT = e.TYPE_EQUIPEMENT
  JOIN DIM_LIGNE l           ON l.LIGNE_ID = i.LIGNE_ID
)
SELECT inc.*,
       -- équipe de 1re intervention
       CASE WHEN TYPE_EQUIPEMENT = 'Rame' THEN IFF(MODE_TRANSPORT = 'Tramway', 'EQ02', 'EQ01')
            WHEN CATEGORIE_PANNE = 'Externe' AND GRAVITE >= 3 THEN 'EQ09'
            ELSE EQUIPE_SPECIALISTE END AS EQUIPE_1,
       -- équipe de 2e intervention (spécialiste)
       CASE WHEN TYPE_EQUIPEMENT = 'Rame' THEN IFF(MODE_TRANSPORT = 'Tramway', 'EQ02', 'EQ01')
            ELSE EQUIPE_SPECIALISTE END AS EQUIPE_2,
       -- délai d'arrivée sur site
       LEAST(GREATEST(1, ROUND(DUREE_REF * 0.6)),
             CASE GRAVITE WHEN 4 THEN UNIFORM(5, 20, RANDOM())
                          WHEN 3 THEN UNIFORM(10, 45, RANDOM())
                          WHEN 2 THEN UNIFORM(30, 240, RANDOM())
                          ELSE UNIFORM(60, 720, RANDOM()) END
             * IFF(LIGNE_ID = 'D' AND TYPE_EQUIPEMENT = 'Escalator', 2, 1)) AS DELAI,
       CASE WHEN CATEGORIE_PANNE = 'Logiciel'   THEN 'Réinitialisation / mise à jour logicielle'
            WHEN CATEGORIE_PANNE = 'Externe'    THEN 'Sécurisation et dégagement'
            WHEN CATEGORIE_PANNE = 'Vandalisme' THEN 'Remise en état'
            WHEN UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.55 THEN 'Remplacement de pièce'
            ELSE 'Diagnostic et réparation' END AS TYPE_INTERVENTION,
       CASE GRAVITE WHEN 4 THEN UNIFORM(3, 6, RANDOM())
                    WHEN 3 THEN UNIFORM(2, 4, RANDOM())
                    ELSE UNIFORM(1, 2, RANDOM()) END AS NB_AGENTS,
       CASE TYPE_EQUIPEMENT WHEN 'Rame' THEN 2 WHEN 'Signalisation' THEN 1.5 WHEN 'Escalator' THEN 1.3 ELSE 1 END AS MULT_PIECES,
       CASE CATEGORIE_PANNE WHEN 'Mécanique'    THEN UNIFORM(200, 6000, RANDOM())
                            WHEN 'Electrique'   THEN UNIFORM(150, 8000, RANDOM())
                            WHEN 'Electronique' THEN UNIFORM(300, 4500, RANDOM())
                            WHEN 'Vandalisme'   THEN UNIFORM(100, 2500, RANDOM())
                            ELSE UNIFORM(0, 400, RANDOM()) END AS BASE_PIECES,
       UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS U_SECONDE,
       UNIFORM(60, 2880, RANDOM())           AS OFFSET_2,
       UNIFORM(30, 300, RANDOM())            AS DUREE_2,
       IFF(UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.4, UNIFORM(100, 3000, RANDOM()), 0) AS BASE_PIECES_2
FROM inc;

-- 8a. Intervention initiale (tous les incidents)
INSERT INTO FACT_INTERVENTION
  (INTERVENTION_ID, INCIDENT_ID, EQUIPE_ID, RANG_INTERVENTION, TYPE_INTERVENTION, DATE_HEURE_ARRIVEE,
   DATE_HEURE_FIN, DELAI_INTERVENTION_MIN, DUREE_INTERVENTION_MIN, NB_AGENTS, COUT_MAIN_OEUVRE_EUR, COUT_PIECES_EUR)
SELECT REPLACE(INCIDENT_ID, 'INC', 'INT') || '-1',
       INCIDENT_ID,
       EQUIPE_1,
       1,
       TYPE_INTERVENTION,
       DATEADD(minute, DELAI, DATE_HEURE_DEBUT),
       IFF(STATUT = 'Clos', DATE_HEURE_FIN, NULL),
       DELAI,
       IFF(STATUT = 'Clos', GREATEST(DUREE_MINUTES - DELAI, 1), NULL),
       NB_AGENTS,
       IFF(STATUT = 'Clos', ROUND(NB_AGENTS * LEAST(GREATEST(DUREE_MINUTES - DELAI, 1), 240) / 60 * 68, 2), 0),
       IFF(TYPE_INTERVENTION IN ('Remplacement de pièce', 'Remise en état'), ROUND(BASE_PIECES * MULT_PIECES, 2), 0)
FROM TMP_INTER;

-- 8b. Réparation définitive / contrôle (une partie des incidents clos)
INSERT INTO FACT_INTERVENTION
  (INTERVENTION_ID, INCIDENT_ID, EQUIPE_ID, RANG_INTERVENTION, TYPE_INTERVENTION, DATE_HEURE_ARRIVEE,
   DATE_HEURE_FIN, DELAI_INTERVENTION_MIN, DUREE_INTERVENTION_MIN, NB_AGENTS, COUT_MAIN_OEUVRE_EUR, COUT_PIECES_EUR)
SELECT REPLACE(INCIDENT_ID, 'INC', 'INT') || '-2',
       INCIDENT_ID,
       EQUIPE_2,
       2,
       'Réparation définitive / contrôle post-incident',
       DATEADD(minute, OFFSET_2, DATE_HEURE_FIN),
       DATEADD(minute, OFFSET_2 + DUREE_2, DATE_HEURE_FIN),
       DATEDIFF(minute, DATE_HEURE_DEBUT, DATEADD(minute, OFFSET_2, DATE_HEURE_FIN)),
       DUREE_2,
       2,
       ROUND(2 * DUREE_2 / 60 * 68, 2),
       ROUND(BASE_PIECES_2 * MULT_PIECES, 2)
FROM TMP_INTER
WHERE STATUT = 'Clos'
  AND (   EQUIPE_1 = 'EQ09'
       OR (GRAVITE >= 3 AND U_SECONDE < 0.30)
       OR (TYPE_INTERVENTION = 'Diagnostic et réparation' AND U_SECONDE < 0.15))
  AND DATEADD(minute, OFFSET_2 + DUREE_2, DATE_HEURE_FIN) < CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

-- ---------------------------------------------------------------------
-- 9. Contrôles
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS nb_incidents, MIN(DATE_INCIDENT) AS du, MAX(DATE_INCIDENT) AS au,
       COUNT_IF(STATUT = 'En cours') AS en_cours
FROM FACT_INCIDENT;

SELECT COUNT(*) AS nb_interventions, SUM(COUT_MAIN_OEUVRE_EUR + COUT_PIECES_EUR) AS cout_total_eur
FROM FACT_INTERVENTION;

-- Répartition par ligne
SELECT LIGNE_ID, COUNT(*) AS nb_incidents, ROUND(AVG(DUREE_MINUTES)) AS duree_moy_min
FROM FACT_INCIDENT GROUP BY 1 ORDER BY 2 DESC;

-- Histoire 1 : pic CBTC ligne B
SELECT DATE_TRUNC('month', DATE_INCIDENT) AS mois, COUNT(*) AS nb_pannes_sig_B
FROM FACT_INCIDENT i JOIN DIM_EQUIPEMENT e USING (EQUIPEMENT_ID)
WHERE i.LIGNE_ID = 'B' AND e.TYPE_EQUIPEMENT = 'Signalisation'
GROUP BY 1 ORDER BY 1;
