-- =====================================================================
-- DEMO CORTEX AGENT - Analyse des pannes réseau Métro / Tram (Lyon)
-- 05 - SEMANTIC VIEW (utilisée par Cortex Analyst)
-- =====================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA DB_YAR.MAINTENANCE;

CREATE OR REPLACE SEMANTIC VIEW DB_YAR.MAINTENANCE.SV_PANNES_RESEAU

  -- -------------------------------------------------------------------
  -- Tables logiques
  -- -------------------------------------------------------------------
  TABLES (
    lignes AS DB_YAR.MAINTENANCE.DIM_LIGNE
      PRIMARY KEY (LIGNE_ID)
      WITH SYNONYMS = ('ligne', 'lignes de métro', 'lignes de tram', 'réseau')
      COMMENT = 'Lignes du réseau : métro A, B, C, D, funiculaires F1, F2 et tramways T1 à T7',

    stations AS DB_YAR.MAINTENANCE.DIM_STATION
      PRIMARY KEY (STATION_ID)
      WITH SYNONYMS = ('station', 'arrêt', 'arrêts', 'gare')
      COMMENT = 'Stations par ligne. Une même station physique (ex : Bellecour) apparaît une fois par ligne desservie',

    equipements AS DB_YAR.MAINTENANCE.DIM_EQUIPEMENT
      PRIMARY KEY (EQUIPEMENT_ID)
      WITH SYNONYMS = ('équipement', 'matériel', 'actif', 'asset', 'parc')
      COMMENT = 'Parc des équipements maintenus : rames, escalators, ascenseurs, billettique, signalisation, énergie, voie',

    types_panne AS DB_YAR.MAINTENANCE.REF_TYPE_PANNE
      PRIMARY KEY (TYPE_PANNE_ID)
      WITH SYNONYMS = ('type de panne', 'nature de panne', 'cause', 'défaut')
      COMMENT = 'Catalogue des types de pannes et événements d exploitation',

    meteo AS DB_YAR.MAINTENANCE.METEO_JOURNALIERE
      PRIMARY KEY (DATE_JOUR)
      WITH SYNONYMS = ('météo', 'conditions météo', 'temps', 'climat')
      COMMENT = 'Conditions météorologiques journalières sur l agglomération lyonnaise',

    equipes AS DB_YAR.MAINTENANCE.DIM_EQUIPE_MAINTENANCE
      PRIMARY KEY (EQUIPE_ID)
      WITH SYNONYMS = ('équipe', 'équipe de maintenance', 'mainteneur', 'prestataire')
      COMMENT = 'Equipes de maintenance internes et sous-traitantes',

    incidents AS DB_YAR.MAINTENANCE.FACT_INCIDENT
      PRIMARY KEY (INCIDENT_ID)
      WITH SYNONYMS = ('incident', 'panne', 'pannes', 'défaillance', 'avarie', 'perturbation', 'dysfonctionnement')
      COMMENT = 'Incidents et pannes survenus sur le réseau, un enregistrement par incident',

    interventions AS DB_YAR.MAINTENANCE.FACT_INTERVENTION
      PRIMARY KEY (INTERVENTION_ID)
      WITH SYNONYMS = ('intervention', 'réparation', 'dépannage', 'opération de maintenance')
      COMMENT = 'Interventions des équipes de maintenance sur les incidents (coûts, délais, durées)'
  )

  -- -------------------------------------------------------------------
  -- Relations
  -- -------------------------------------------------------------------
  RELATIONSHIPS (
    incident_ligne        AS incidents (LIGNE_ID)        REFERENCES lignes,
    incident_station      AS incidents (STATION_ID)      REFERENCES stations,
    incident_equipement   AS incidents (EQUIPEMENT_ID)   REFERENCES equipements,
    incident_type_panne   AS incidents (TYPE_PANNE_ID)   REFERENCES types_panne,
    incident_meteo        AS incidents (DATE_INCIDENT)   REFERENCES meteo,
    intervention_incident AS interventions (INCIDENT_ID) REFERENCES incidents,
    intervention_equipe   AS interventions (EQUIPE_ID)   REFERENCES equipes
  )

  -- -------------------------------------------------------------------
  -- Faits (valeurs numériques au niveau ligne)
  -- -------------------------------------------------------------------
  FACTS (
    lignes.longueur_km               AS LONGUEUR_KM            COMMENT = 'Longueur de la ligne en km',
    lignes.frequentation_jour_moy    AS FREQUENTATION_JOUR_MOY WITH SYNONYMS = ('fréquentation', 'trafic voyageurs') COMMENT = 'Nombre moyen de voyages par jour ouvré sur la ligne',
    lignes.intervalle_pointe_min     AS INTERVALLE_POINTE_MIN  COMMENT = 'Intervalle entre deux passages en heure de pointe (minutes)',
    lignes.nb_stations_ligne         AS NB_STATIONS            COMMENT = 'Nombre de stations de la ligne',

    equipements.age_equipement_annees AS DATEDIFF('year', DATE_MISE_EN_SERVICE, CURRENT_DATE())
      WITH SYNONYMS = ('âge', 'ancienneté') COMMENT = 'Age de l équipement en années',

    meteo.temperature_min_c          AS TEMPERATURE_MIN_C  COMMENT = 'Température minimale du jour (°C)',
    meteo.temperature_max_c          AS TEMPERATURE_MAX_C  COMMENT = 'Température maximale du jour (°C)',
    meteo.precipitations_mm          AS PRECIPITATIONS_MM  WITH SYNONYMS = ('pluie', 'précipitations') COMMENT = 'Cumul de précipitations du jour (mm)',
    meteo.vent_rafales_kmh           AS VENT_RAFALES_KMH   COMMENT = 'Rafales de vent maximales (km/h)',

    incidents.duree_minutes          AS DUREE_MINUTES
      WITH SYNONYMS = ('durée', 'temps de résolution', 'durée de panne', 'temps d indisponibilité')
      COMMENT = 'Durée de l incident en minutes, de la détection à la remise en service. NULL si l incident est en cours',
    incidents.nb_voyageurs_impactes  AS NB_VOYAGEURS_IMPACTES COMMENT = 'Estimation du nombre de voyageurs impactés par l incident',
    incidents.nb_courses_supprimees  AS NB_COURSES_SUPPRIMEES COMMENT = 'Nombre de courses (passages) supprimées à cause de l incident',

    interventions.delai_intervention_min AS DELAI_INTERVENTION_MIN
      WITH SYNONYMS = ('délai d intervention', 'temps d arrivée', 'délai de prise en charge')
      COMMENT = 'Délai entre le début de l incident et l arrivée de l équipe sur site (minutes)',
    interventions.duree_intervention_min AS DUREE_INTERVENTION_MIN COMMENT = 'Durée de l intervention sur site (minutes)',
    interventions.nb_agents              AS NB_AGENTS              COMMENT = 'Nombre d agents mobilisés sur l intervention',
    interventions.cout_main_oeuvre_eur   AS COUT_MAIN_OEUVRE_EUR   COMMENT = 'Coût de main d oeuvre en euros',
    interventions.cout_pieces_eur        AS COUT_PIECES_EUR        COMMENT = 'Coût des pièces de rechange en euros',
    interventions.cout_total_eur         AS COUT_MAIN_OEUVRE_EUR + COUT_PIECES_EUR
      WITH SYNONYMS = ('coût', 'coût de maintenance', 'coût de réparation')
      COMMENT = 'Coût total de l intervention (main d oeuvre + pièces) en euros'
  )

  -- -------------------------------------------------------------------
  -- Dimensions
  -- -------------------------------------------------------------------
  DIMENSIONS (
    -- Lignes
    lignes.ligne_id               AS LIGNE_ID
      WITH SYNONYMS = ('code ligne', 'numéro de ligne')
      COMMENT = 'Code de la ligne : A, B, C, D (métro), F1, F2 (funiculaire), T1, T2, T3, T4, T5, T6, T7 (tramway)',
    lignes.nom_ligne              AS NOM_LIGNE
      COMMENT = 'Nom de la ligne : Métro A, Métro B, Métro C, Métro D, Funiculaire F1, Funiculaire F2, Tram T1 à Tram T7',
    lignes.mode_transport         AS MODE_TRANSPORT
      WITH SYNONYMS = ('mode', 'type de transport')
      COMMENT = 'Mode de transport : Métro, Tramway, Funiculaire',
    lignes.terminus_1             AS TERMINUS_1 COMMENT = 'Premier terminus de la ligne',
    lignes.terminus_2             AS TERMINUS_2 COMMENT = 'Second terminus de la ligne',
    lignes.conduite_automatique   AS CONDUITE_AUTOMATIQUE
      WITH SYNONYMS = ('ligne automatique', 'sans conducteur')
      COMMENT = 'TRUE si la ligne est en conduite automatique (lignes B et D)',
    lignes.annee_mise_en_service_ligne AS ANNEE_MISE_EN_SERVICE COMMENT = 'Année de mise en service de la ligne',

    -- Stations
    stations.station_id           AS STATION_ID COMMENT = 'Identifiant station-ligne, ex : D05',
    stations.nom_station          AS NOM_STATION
      WITH SYNONYMS = ('nom de station', 'nom d arrêt')
      COMMENT = 'Nom de la station, ex : Bellecour, Gare Part-Dieu-Vivier Merle, Perrache',
    stations.commune              AS COMMUNE
      WITH SYNONYMS = ('ville', 'arrondissement')
      COMMENT = 'Commune ou arrondissement : Lyon 1er à Lyon 9e, Villeurbanne, Vénissieux, Bron, Vaulx-en-Velin...',
    stations.est_correspondance   AS EST_CORRESPONDANCE COMMENT = 'TRUE si la station est un pôle de correspondance',
    stations.est_souterraine      AS EST_SOUTERRAINE    COMMENT = 'TRUE si la station est souterraine',

    -- Equipements
    equipements.equipement_id     AS EQUIPEMENT_ID COMMENT = 'Identifiant de l équipement, ex : ESC-D05-01, RAME-A-012',
    equipements.libelle_equipement AS LIBELLE_EQUIPEMENT COMMENT = 'Libellé lisible de l équipement',
    equipements.type_equipement   AS TYPE_EQUIPEMENT
      WITH SYNONYMS = ('type de matériel', 'catégorie d équipement')
      COMMENT = 'Type d équipement : Rame, Escalator, Ascenseur, Ventilation / désenfumage, Distributeur automatique de titres, Portillon de contrôle d accès, Ecran d information voyageurs, Signalisation, Sous-station d alimentation, Caténaire, Rail de traction, Aiguillage, Voie',
    equipements.famille_equipement AS FAMILLE_EQUIPEMENT
      WITH SYNONYMS = ('famille', 'domaine technique')
      COMMENT = 'Famille technique : Matériel roulant, Equipements de station, Billettique, Information voyageurs, Signalisation & automatismes, Energie, Voie',
    equipements.modele            AS MODELE
      WITH SYNONYMS = ('modèle de rame', 'série')
      COMMENT = 'Modèle : MPL 75 (ligne A), MPL 16 (ligne B), MCL 80 (ligne C), MPL 85 (ligne D), Citadis 302 / 402 / X05 (tram), CBTC (signalisation B et D)',
    equipements.fabricant         AS FABRICANT
      WITH SYNONYMS = ('constructeur', 'fournisseur')
      COMMENT = 'Fabricant de l équipement',
    equipements.criticite         AS CRITICITE COMMENT = 'Criticité de l équipement : Haute, Moyenne, Faible',
    equipements.date_mise_en_service_equipement AS DATE_MISE_EN_SERVICE COMMENT = 'Date de mise en service de l équipement',

    -- Types de panne
    types_panne.type_panne_id     AS TYPE_PANNE_ID COMMENT = 'Code du type de panne',
    types_panne.libelle_panne     AS LIBELLE_PANNE
      WITH SYNONYMS = ('nature de la panne', 'description de la panne', 'cause de la panne')
      COMMENT = 'Libellé de la panne, ex : Panne de traction, Perte de communication CBTC / pilotage automatique, Gel / givre sur aiguillage, Collision avec un véhicule routier',
    types_panne.categorie_panne   AS CATEGORIE_PANNE
      WITH SYNONYMS = ('catégorie', 'origine de la panne')
      COMMENT = 'Catégorie de la panne : Mécanique, Electrique, Electronique, Logiciel, Vandalisme, Externe',

    -- Météo
    meteo.date_jour_meteo         AS DATE_JOUR COMMENT = 'Date du relevé météo',
    meteo.evenement_meteo         AS EVENEMENT_METEO
      WITH SYNONYMS = ('événement météo', 'conditions climatiques')
      COMMENT = 'Evénement météo du jour : RAS, Pluie, Orage, Gel, Neige, Canicule, Tempête / vent fort',

    -- Equipes
    equipes.nom_equipe            AS NOM_EQUIPE COMMENT = 'Nom de l équipe de maintenance',
    equipes.specialite_equipe     AS SPECIALITE COMMENT = 'Spécialité de l équipe',
    equipes.base_equipe           AS BASE COMMENT = 'Site de rattachement de l équipe',
    equipes.statut_equipe         AS STATUT_EQUIPE
      WITH SYNONYMS = ('interne ou sous-traitant', 'sous-traitance')
      COMMENT = 'Interne ou Sous-traitant',

    -- Incidents
    incidents.incident_id         AS INCIDENT_ID COMMENT = 'Identifiant de l incident',
    incidents.date_incident       AS DATE_INCIDENT
      WITH SYNONYMS = ('date', 'jour de la panne')
      COMMENT = 'Date de l incident',
    incidents.date_heure_debut    AS DATE_HEURE_DEBUT COMMENT = 'Horodatage de début de l incident',
    incidents.date_heure_fin      AS DATE_HEURE_FIN   COMMENT = 'Horodatage de remise en service (NULL si en cours)',
    incidents.mois_incident       AS DATE_TRUNC('MONTH', DATE_INCIDENT)
      WITH SYNONYMS = ('mois', 'mensuel')
      COMMENT = 'Mois de l incident (premier jour du mois)',
    incidents.annee_incident      AS YEAR(DATE_INCIDENT) WITH SYNONYMS = ('année', 'annuel') COMMENT = 'Année de l incident',
    incidents.saison              AS CASE WHEN MONTH(DATE_INCIDENT) IN (12, 1, 2) THEN 'Hiver'
                                          WHEN MONTH(DATE_INCIDENT) IN (3, 4, 5)  THEN 'Printemps'
                                          WHEN MONTH(DATE_INCIDENT) IN (6, 7, 8)  THEN 'Eté'
                                          ELSE 'Automne' END
      COMMENT = 'Saison de l incident : Hiver, Printemps, Eté, Automne',
    incidents.jour_semaine        AS DECODE(DAYOFWEEKISO(DATE_INCIDENT), 1, '1-Lundi', 2, '2-Mardi', 3, '3-Mercredi',
                                            4, '4-Jeudi', 5, '5-Vendredi', 6, '6-Samedi', '7-Dimanche')
      COMMENT = 'Jour de la semaine, préfixé par son numéro pour le tri',
    incidents.est_week_end        AS DAYOFWEEKISO(DATE_INCIDENT) >= 6 COMMENT = 'TRUE si l incident a eu lieu un samedi ou un dimanche',
    incidents.heure_debut         AS HOUR(DATE_HEURE_DEBUT) WITH SYNONYMS = ('heure', 'heure de début') COMMENT = 'Heure de début de l incident (0 à 23)',
    incidents.tranche_horaire     AS CASE WHEN HOUR(DATE_HEURE_DEBUT) IN (7, 8, 9)    THEN 'Pointe du matin (7h-10h)'
                                          WHEN HOUR(DATE_HEURE_DEBUT) IN (17, 18, 19) THEN 'Pointe du soir (17h-20h)'
                                          WHEN HOUR(DATE_HEURE_DEBUT) BETWEEN 10 AND 16 THEN 'Heures creuses de journée'
                                          WHEN HOUR(DATE_HEURE_DEBUT) BETWEEN 1 AND 4   THEN 'Nuit (hors service commercial)'
                                          ELSE 'Début ou fin de service' END
      WITH SYNONYMS = ('plage horaire', 'créneau')
      COMMENT = 'Tranche horaire de l incident',
    incidents.est_heure_de_pointe AS HOUR(DATE_HEURE_DEBUT) IN (7, 8, 9, 17, 18, 19)
      WITH SYNONYMS = ('heure de pointe', 'rush')
      COMMENT = 'TRUE si l incident a commencé en heure de pointe (7h-10h ou 17h-20h)',
    incidents.gravite             AS GRAVITE
      COMMENT = 'Gravité de l incident de 1 (mineure) à 4 (critique). Un incident est dit critique ou majeur si gravité >= 3',
    incidents.niveau_gravite      AS DECODE(GRAVITE, 1, '1 - Mineure', 2, '2 - Modérée', 3, '3 - Majeure', 4, '4 - Critique')
      COMMENT = 'Libellé de la gravité : 1 - Mineure, 2 - Modérée, 3 - Majeure, 4 - Critique',
    incidents.impact_service      AS IMPACT_SERVICE
      WITH SYNONYMS = ('impact', 'impact sur la circulation', 'conséquence')
      COMMENT = 'Impact sur la circulation : Interruption totale, Interruption partielle, Ralentissement, Aucun',
    incidents.source_signalement  AS SOURCE_SIGNALEMENT
      COMMENT = 'Origine du signalement : Supervision PCC, Conducteur, Agent de station, Télésurveillance des équipements, Voyageur',
    incidents.statut_incident     AS STATUT
      COMMENT = 'Statut de l incident : Clos ou En cours',

    -- Interventions
    interventions.intervention_id   AS INTERVENTION_ID COMMENT = 'Identifiant de l intervention',
    interventions.type_intervention AS TYPE_INTERVENTION
      COMMENT = 'Type d intervention : Remplacement de pièce, Diagnostic et réparation, Réinitialisation / mise à jour logicielle, Sécurisation et dégagement, Remise en état, Réparation définitive / contrôle post-incident',
    interventions.rang_intervention AS RANG_INTERVENTION
      COMMENT = '1 = intervention initiale, 2 = réparation définitive ou contrôle post-incident',
    interventions.date_heure_arrivee AS DATE_HEURE_ARRIVEE COMMENT = 'Arrivée de l équipe sur site'
  )

  -- -------------------------------------------------------------------
  -- Métriques (KPI)
  -- -------------------------------------------------------------------
  METRICS (
    -- Incidents
    incidents.nb_incidents AS COUNT(incidents.incident_id)
      WITH SYNONYMS = ('nombre de pannes', 'nombre d incidents', 'volume d incidents')
      COMMENT = 'Nombre d incidents',
    incidents.nb_incidents_critiques AS COUNT_IF(incidents.gravite >= 3)
      WITH SYNONYMS = ('incidents majeurs', 'pannes graves')
      COMMENT = 'Nombre d incidents de gravité 3 (majeure) ou 4 (critique)',
    incidents.taux_incidents_critiques AS DIV0(COUNT_IF(incidents.gravite >= 3), COUNT(incidents.incident_id))
      COMMENT = 'Part des incidents de gravité >= 3 (ratio entre 0 et 1)',
    incidents.nb_interruptions_totales AS COUNT_IF(incidents.impact_service = 'Interruption totale')
      WITH SYNONYMS = ('interruptions de trafic', 'coupures de ligne', 'arrêts de service')
      COMMENT = 'Nombre d incidents ayant entraîné une interruption totale de la circulation',
    incidents.duree_moyenne_resolution_min AS AVG(incidents.duree_minutes)
      WITH SYNONYMS = ('MTTR', 'temps moyen de résolution', 'durée moyenne des pannes', 'temps moyen de réparation')
      COMMENT = 'MTTR : durée moyenne de résolution des incidents clos, en minutes',
    incidents.duree_mediane_resolution_min AS MEDIAN(incidents.duree_minutes)
      COMMENT = 'Durée médiane de résolution des incidents clos, en minutes',
    incidents.duree_totale_incidents_heures AS SUM(incidents.duree_minutes) / 60
      WITH SYNONYMS = ('heures d indisponibilité', 'temps total de panne')
      COMMENT = 'Durée cumulée des incidents en heures',
    incidents.heures_interruption_totale AS SUM(IFF(incidents.impact_service = 'Interruption totale', incidents.duree_minutes, 0)) / 60
      COMMENT = 'Durée cumulée des interruptions totales de circulation, en heures',
    incidents.total_voyageurs_impactes AS SUM(incidents.nb_voyageurs_impactes)
      WITH SYNONYMS = ('voyageurs impactés', 'clients impactés', 'impact voyageurs')
      COMMENT = 'Nombre total estimé de voyageurs impactés',
    incidents.total_courses_supprimees AS SUM(incidents.nb_courses_supprimees)
      WITH SYNONYMS = ('courses supprimées', 'offre non réalisée')
      COMMENT = 'Nombre total de courses supprimées',
    incidents.nb_incidents_en_cours AS COUNT_IF(incidents.statut_incident = 'En cours')
      COMMENT = 'Nombre d incidents non encore résolus',

    -- Equipements
    equipements.nb_equipements AS COUNT(equipements.equipement_id)
      WITH SYNONYMS = ('taille du parc', 'nombre d équipements')
      COMMENT = 'Nombre d équipements du parc',

    -- Interventions
    interventions.nb_interventions AS COUNT(interventions.intervention_id)
      COMMENT = 'Nombre d interventions de maintenance',
    interventions.cout_total_maintenance_eur AS SUM(interventions.cout_total_eur)
      WITH SYNONYMS = ('coût total', 'coût de maintenance corrective', 'dépenses de maintenance')
      COMMENT = 'Coût total des interventions (main d oeuvre + pièces) en euros',
    interventions.cout_pieces_total_eur AS SUM(interventions.cout_pieces_eur)
      COMMENT = 'Coût total des pièces de rechange en euros',
    interventions.cout_main_oeuvre_total_eur AS SUM(interventions.cout_main_oeuvre_eur)
      COMMENT = 'Coût total de main d oeuvre en euros',
    interventions.cout_moyen_intervention_eur AS AVG(interventions.cout_total_eur)
      COMMENT = 'Coût moyen d une intervention en euros',
    interventions.delai_moyen_intervention_min AS AVG(IFF(interventions.rang_intervention = 1, interventions.delai_intervention_min, NULL))
      WITH SYNONYMS = ('délai moyen d intervention', 'temps moyen d arrivée', 'réactivité')
      COMMENT = 'Délai moyen d arrivée sur site de la première équipe, en minutes',
    interventions.heures_homme_total AS SUM(interventions.nb_agents * interventions.duree_intervention_min) / 60
      WITH SYNONYMS = ('charge de travail', 'heures agents')
      COMMENT = 'Charge de maintenance en heures-homme'
  )

  COMMENT = 'Analyse des pannes et de la maintenance du réseau métro, tramway et funiculaire de Lyon : incidents, équipements, interventions, coûts, météo';

-- ---------------------------------------------------------------------
-- (Optionnel) Instructions spécifiques Cortex Analyst
-- Si votre compte supporte la clause AI_SQL_GENERATION, vous pouvez
-- l'ajouter juste avant le COMMENT final de la semantic view :
--
--   AI_SQL_GENERATION 'Les durées sont en minutes ; convertis en heures si
--   la valeur dépasse 120 minutes. Pour le MTTR, exclure les incidents en
--   cours. Quand on parle de "pannes critiques", filtrer gravite >= 3.
--   Par défaut, analyser les 12 derniers mois.'
-- ---------------------------------------------------------------------

-- Vérifications
SHOW SEMANTIC VIEWS IN SCHEMA DB_YAR.MAINTENANCE;
DESCRIBE SEMANTIC VIEW DB_YAR.MAINTENANCE.SV_PANNES_RESEAU;

-- Requête directe sur la semantic view
SELECT * FROM SEMANTIC_VIEW(
    DB_YAR.MAINTENANCE.SV_PANNES_RESEAU
    DIMENSIONS lignes.nom_ligne
    METRICS incidents.nb_incidents, incidents.duree_moyenne_resolution_min, incidents.total_voyageurs_impactes
  )
ORDER BY 2 DESC;
