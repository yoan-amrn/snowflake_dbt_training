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
-- A VOUS DE JOUER




-- =============================================================================
-- Exercice 2 - Mesurer la concurrence (5 min)
-- Pour chaque lot, calculez le nombre maximal de requetes presentes en meme temps
-- sur le warehouse (en cours OU en attente).
-- Indice : auto-jointure de la table sur elle-meme : la requete b est presente
-- au demarrage de la requete a si b.START_TIME <= a.START_TIME < b.END_TIME.
-- =============================================================================
-- A VOUS DE JOUER




-- =============================================================================
-- Exercice 3 - Chercher les signes d'un warehouse trop petit (5 min)
-- Pour chaque lot : volume scanne (Go), volume deborde sur disque local et
-- distant (Go), temps d'execution maximal.
-- Question : quel lot montre que la requete elle-meme manque de memoire ?
-- =============================================================================
-- A VOUS DE JOUER




-- =============================================================================
-- Exercice 4 - Votre diagnostic (5 min)
-- Completez le tableau ci-dessous dans votre schema, une ligne par lot :
--   LOT, SYMPTOME (ce que montrent les chiffres), SCALING (UP / OUT / ACROSS),
--   COMMANDE (l'ALTER WAREHOUSE ou l'organisation que vous proposez).
-- Puis confrontez votre reponse a celle de vos voisins.
-- =============================================================================
-- A VOUS DE JOUER




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
-- A VOUS DE JOUER




-- =============================================================================
-- Bonus (J1 apres-midi, FinOps) - Voir le scale out / scale in dans l'historique
-- ACCOUNT_USAGE a une latence de 45 min a 3 h : a faire apres le dejeuner.
-- Listez les evenements du warehouse WH_SCALING_DEMO de la matinee
-- (demarrages / arrets de clusters, redimensionnements).
-- =============================================================================
-- A VOUS DE JOUER



