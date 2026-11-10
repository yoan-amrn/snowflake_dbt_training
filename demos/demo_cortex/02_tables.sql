-- =====================================================================
-- DEMO CORTEX AGENT - Analyse des pannes réseau Métro / Tram (Lyon)
-- 02 - MODELE DE DONNEES (DDL)
-- ---------------------------------------------------------------------
-- Modèle en étoile :
--
--   DIM_LIGNE ─┐                      ┌─ DIM_EQUIPE_MAINTENANCE
--   DIM_STATION┤                      │
--   DIM_EQUIPEMENT ── FACT_INCIDENT ◄─┴─ FACT_INTERVENTION
--   REF_TYPE_PANNE┘        │
--                   METEO_JOURNALIERE
--
--   REF_TYPE_EQUIPEMENT : référentiel technique (taux de défaillance,
--                         équipe spécialiste) utilisé pour la génération
-- =====================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA DB_YAR.MAINTENANCE;

-- ---------------------------------------------------------------------
-- Lignes du réseau
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_LIGNE (
  LIGNE_ID                 VARCHAR(5)   NOT NULL COMMENT 'Code de la ligne : A, B, C, D (métro), F1, F2 (funiculaire), T1 à T7 (tramway)',
  NOM_LIGNE                VARCHAR(50)  NOT NULL COMMENT 'Nom commercial de la ligne, ex : Métro A, Tram T3',
  MODE_TRANSPORT           VARCHAR(20)  NOT NULL COMMENT 'Mode : Métro, Tramway, Funiculaire',
  TERMINUS_1               VARCHAR(100) COMMENT 'Premier terminus',
  TERMINUS_2               VARCHAR(100) COMMENT 'Second terminus',
  LONGUEUR_KM              NUMBER(5,1)  COMMENT 'Longueur de la ligne en km',
  NB_STATIONS              NUMBER(3)    COMMENT 'Nombre de stations référencées sur la ligne',
  ANNEE_MISE_EN_SERVICE    NUMBER(4)    COMMENT 'Année de mise en service de la ligne',
  CONDUITE_AUTOMATIQUE     BOOLEAN      COMMENT 'TRUE si la ligne est en conduite automatique intégrale (sans conducteur)',
  FREQUENTATION_JOUR_MOY   NUMBER(10)   COMMENT 'Nombre moyen de voyages par jour ouvré',
  INTERVALLE_POINTE_MIN    NUMBER(4,1)  COMMENT 'Intervalle entre deux passages en heure de pointe (minutes)',
  CONSTRAINT PK_DIM_LIGNE PRIMARY KEY (LIGNE_ID)
) COMMENT = 'Référentiel des lignes de métro, tramway et funiculaire du réseau lyonnais';

-- ---------------------------------------------------------------------
-- Stations (une ligne par couple station / ligne)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_STATION (
  STATION_ID          VARCHAR(10)  NOT NULL COMMENT 'Identifiant station-ligne, ex : A03 = Bellecour sur la ligne A',
  NOM_STATION         VARCHAR(100) NOT NULL COMMENT 'Nom de la station (une même station peut exister sur plusieurs lignes)',
  LIGNE_ID            VARCHAR(5)   NOT NULL COMMENT 'Ligne desservant la station',
  ORDRE_SUR_LIGNE     NUMBER(3)    COMMENT 'Rang de la station sur la ligne depuis le terminus 1',
  COMMUNE             VARCHAR(100) COMMENT 'Commune ou arrondissement de Lyon',
  EST_CORRESPONDANCE  BOOLEAN      COMMENT 'TRUE si la station est un pôle de correspondance',
  EST_SOUTERRAINE     BOOLEAN      COMMENT 'TRUE si la station est souterraine',
  CONSTRAINT PK_DIM_STATION PRIMARY KEY (STATION_ID),
  CONSTRAINT FK_STATION_LIGNE FOREIGN KEY (LIGNE_ID) REFERENCES DIM_LIGNE (LIGNE_ID)
) COMMENT = 'Référentiel des stations par ligne';

-- ---------------------------------------------------------------------
-- Référentiel des types d'équipements (technique)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE REF_TYPE_EQUIPEMENT (
  TYPE_EQUIPEMENT       VARCHAR(60)  NOT NULL COMMENT 'Type d''équipement',
  CODE                  VARCHAR(10)  NOT NULL COMMENT 'Code court du type',
  FAMILLE               VARCHAR(60)  COMMENT 'Famille technique',
  NIVEAU                VARCHAR(10)  COMMENT 'STATION = équipement de station, LIGNE = infrastructure de ligne, FLOTTE = matériel roulant',
  MODE_APPLICABLE       VARCHAR(20)  COMMENT 'TOUS, Métro, Tramway, SOUTERRAIN (métro+funiculaire), FERRE_URBAIN (métro+tram)',
  NB_PAR_UNITE          NUMBER(3)    COMMENT 'Nombre d''équipements par station ou par ligne',
  CRITICITE             VARCHAR(10)  COMMENT 'Haute / Moyenne / Faible',
  FABRICANT_PRINCIPAL   VARCHAR(60)  COMMENT 'Fabricant principal',
  POIDS_DEFAILLANCE     FLOAT        COMMENT 'Taux relatif de défaillance unitaire (utilisé pour la simulation)',
  EQUIPE_ID             VARCHAR(5)   COMMENT 'Equipe de maintenance spécialiste',
  CONSTRAINT PK_REF_TYPE_EQUIPEMENT PRIMARY KEY (TYPE_EQUIPEMENT)
) COMMENT = 'Référentiel technique des types d''équipements';

-- ---------------------------------------------------------------------
-- Parc d'équipements
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_EQUIPEMENT (
  EQUIPEMENT_ID         VARCHAR(30)  NOT NULL COMMENT 'Identifiant unique de l''équipement, ex : ESC-D05-01, RAME-A-012, SIG-B-02',
  LIBELLE_EQUIPEMENT    VARCHAR(200) COMMENT 'Libellé lisible de l''équipement',
  TYPE_EQUIPEMENT       VARCHAR(60)  NOT NULL COMMENT 'Type : Rame, Escalator, Ascenseur, Signalisation, Aiguillage, Caténaire...',
  FAMILLE_EQUIPEMENT    VARCHAR(60)  COMMENT 'Famille : Matériel roulant, Equipements de station, Billettique, Signalisation & automatismes, Energie, Voie...',
  LIGNE_ID              VARCHAR(5)   NOT NULL COMMENT 'Ligne de rattachement',
  STATION_ID            VARCHAR(10)  COMMENT 'Station de rattachement (NULL pour le matériel roulant et l''infrastructure de ligne)',
  MODELE                VARCHAR(60)  COMMENT 'Modèle (ex : MPL 75, Citadis 302)',
  FABRICANT             VARCHAR(60)  COMMENT 'Fabricant / constructeur',
  DATE_MISE_EN_SERVICE  DATE         COMMENT 'Date de mise en service de l''équipement',
  CRITICITE             VARCHAR(10)  COMMENT 'Criticité pour l''exploitation : Haute / Moyenne / Faible',
  CONSTRAINT PK_DIM_EQUIPEMENT PRIMARY KEY (EQUIPEMENT_ID),
  CONSTRAINT FK_EQUIP_LIGNE FOREIGN KEY (LIGNE_ID) REFERENCES DIM_LIGNE (LIGNE_ID),
  CONSTRAINT FK_EQUIP_STATION FOREIGN KEY (STATION_ID) REFERENCES DIM_STATION (STATION_ID)
) COMMENT = 'Parc des équipements maintenus : matériel roulant, équipements de station, infrastructure';

-- ---------------------------------------------------------------------
-- Catalogue des types de pannes
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE REF_TYPE_PANNE (
  TYPE_PANNE_ID           VARCHAR(10)  NOT NULL COMMENT 'Code du type de panne',
  TYPE_EQUIPEMENT         VARCHAR(60)  NOT NULL COMMENT 'Type d''équipement concerné',
  LIBELLE_PANNE           VARCHAR(200) NOT NULL COMMENT 'Libellé de la panne / de l''événement',
  CATEGORIE_PANNE         VARCHAR(30)  NOT NULL COMMENT 'Mécanique, Electrique, Electronique, Logiciel, Vandalisme, Externe',
  MODE_APPLICABLE         VARCHAR(20)  COMMENT 'Mode de transport concerné (NULL = tous)',
  GRAVITE_TYPIQUE         NUMBER(1)    COMMENT 'Gravité habituelle de 1 (mineure) à 4 (critique)',
  DUREE_MOYENNE_MIN       NUMBER(6)    COMMENT 'Durée moyenne de résolution (minutes)',
  IMPACT_SERVICE_TYPIQUE  VARCHAR(30)  COMMENT 'Impact habituel sur la circulation',
  CONDITION_DECLENCHANTE  VARCHAR(20)  COMMENT 'Facteur aggravant : GEL, CHALEUR, INTEMPERIES, POINTE, CBTC (utilisé pour la simulation)',
  POIDS                   FLOAT        COMMENT 'Fréquence relative (simulation)',
  CONSTRAINT PK_REF_TYPE_PANNE PRIMARY KEY (TYPE_PANNE_ID)
) COMMENT = 'Catalogue des types de pannes et d''événements d''exploitation';

-- ---------------------------------------------------------------------
-- Equipes de maintenance
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_EQUIPE_MAINTENANCE (
  EQUIPE_ID      VARCHAR(5)   NOT NULL COMMENT 'Identifiant de l''équipe',
  NOM_EQUIPE     VARCHAR(100) NOT NULL COMMENT 'Nom de l''équipe de maintenance',
  SPECIALITE     VARCHAR(60)  COMMENT 'Spécialité technique',
  BASE           VARCHAR(100) COMMENT 'Site de rattachement',
  STATUT_EQUIPE  VARCHAR(20)  COMMENT 'Interne ou Sous-traitant',
  EFFECTIF       NUMBER(4)    COMMENT 'Nombre d''agents',
  CONSTRAINT PK_DIM_EQUIPE PRIMARY KEY (EQUIPE_ID)
) COMMENT = 'Equipes de maintenance (internes et sous-traitants)';

-- ---------------------------------------------------------------------
-- Météo journalière (Lyon)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE METEO_JOURNALIERE (
  DATE_JOUR          DATE        NOT NULL COMMENT 'Jour',
  TEMPERATURE_MIN_C  NUMBER(4,1) COMMENT 'Température minimale (°C)',
  TEMPERATURE_MAX_C  NUMBER(4,1) COMMENT 'Température maximale (°C)',
  PRECIPITATIONS_MM  NUMBER(5,1) COMMENT 'Cumul de précipitations (mm)',
  VENT_RAFALES_KMH   NUMBER(4)   COMMENT 'Rafales de vent maximales (km/h)',
  EVENEMENT_METEO    VARCHAR(30) COMMENT 'Evénement météo dominant : RAS, Pluie, Orage, Gel, Neige, Canicule, Tempête / vent fort',
  CONSTRAINT PK_METEO PRIMARY KEY (DATE_JOUR)
) COMMENT = 'Conditions météo journalières sur l''agglomération lyonnaise';

-- ---------------------------------------------------------------------
-- FAIT : incidents / pannes
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE FACT_INCIDENT (
  INCIDENT_ID            VARCHAR(20)   NOT NULL COMMENT 'Identifiant de l''incident',
  DATE_INCIDENT          DATE          NOT NULL COMMENT 'Date de début de l''incident',
  DATE_HEURE_DEBUT       TIMESTAMP_NTZ NOT NULL COMMENT 'Horodatage de début (détection) de l''incident',
  DATE_HEURE_FIN         TIMESTAMP_NTZ COMMENT 'Horodatage de remise en service (NULL si en cours)',
  DUREE_MINUTES          NUMBER(8)     COMMENT 'Durée de l''incident en minutes, de la détection à la remise en service (NULL si en cours)',
  LIGNE_ID               VARCHAR(5)    NOT NULL COMMENT 'Ligne concernée',
  STATION_ID             VARCHAR(10)   COMMENT 'Station où a eu lieu l''incident (ou station la plus proche)',
  EQUIPEMENT_ID          VARCHAR(30)   NOT NULL COMMENT 'Equipement en défaut',
  TYPE_PANNE_ID          VARCHAR(10)   NOT NULL COMMENT 'Type de panne',
  GRAVITE                NUMBER(1)     COMMENT 'Gravité de 1 (mineure) à 4 (critique)',
  IMPACT_SERVICE         VARCHAR(30)   COMMENT 'Impact sur la circulation : Interruption totale, Interruption partielle, Ralentissement, Aucun',
  NB_VOYAGEURS_IMPACTES  NUMBER(10)    COMMENT 'Estimation du nombre de voyageurs impactés',
  NB_COURSES_SUPPRIMEES  NUMBER(6)     COMMENT 'Nombre de courses (passages) supprimées',
  SOURCE_SIGNALEMENT     VARCHAR(50)   COMMENT 'Origine du signalement : Supervision PCC, Conducteur, Agent de station, Télésurveillance des équipements, Voyageur',
  STATUT                 VARCHAR(20)   COMMENT 'Clos ou En cours',
  CONSTRAINT PK_FACT_INCIDENT PRIMARY KEY (INCIDENT_ID),
  CONSTRAINT FK_INC_LIGNE FOREIGN KEY (LIGNE_ID) REFERENCES DIM_LIGNE (LIGNE_ID),
  CONSTRAINT FK_INC_STATION FOREIGN KEY (STATION_ID) REFERENCES DIM_STATION (STATION_ID),
  CONSTRAINT FK_INC_EQUIP FOREIGN KEY (EQUIPEMENT_ID) REFERENCES DIM_EQUIPEMENT (EQUIPEMENT_ID),
  CONSTRAINT FK_INC_PANNE FOREIGN KEY (TYPE_PANNE_ID) REFERENCES REF_TYPE_PANNE (TYPE_PANNE_ID),
  CONSTRAINT FK_INC_METEO FOREIGN KEY (DATE_INCIDENT) REFERENCES METEO_JOURNALIERE (DATE_JOUR)
) COMMENT = 'Incidents et pannes survenus sur le réseau (une ligne par incident)';

-- ---------------------------------------------------------------------
-- FAIT : interventions de maintenance
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE FACT_INTERVENTION (
  INTERVENTION_ID         VARCHAR(25)   NOT NULL COMMENT 'Identifiant de l''intervention',
  INCIDENT_ID             VARCHAR(20)   NOT NULL COMMENT 'Incident traité',
  EQUIPE_ID               VARCHAR(5)    NOT NULL COMMENT 'Equipe intervenante',
  RANG_INTERVENTION       NUMBER(2)     COMMENT '1 = intervention initiale, 2 = réparation définitive / contrôle',
  TYPE_INTERVENTION       VARCHAR(60)   COMMENT 'Remplacement de pièce, Diagnostic et réparation, Réinitialisation / mise à jour logicielle, Sécurisation et dégagement, Remise en état, Réparation définitive / contrôle post-incident',
  DATE_HEURE_ARRIVEE      TIMESTAMP_NTZ COMMENT 'Arrivée de l''équipe sur site',
  DATE_HEURE_FIN          TIMESTAMP_NTZ COMMENT 'Fin de l''intervention',
  DELAI_INTERVENTION_MIN  NUMBER(8)     COMMENT 'Délai entre le début de l''incident et l''arrivée de l''équipe (minutes)',
  DUREE_INTERVENTION_MIN  NUMBER(8)     COMMENT 'Durée de l''intervention sur site (minutes)',
  NB_AGENTS               NUMBER(2)     COMMENT 'Nombre d''agents mobilisés',
  COUT_MAIN_OEUVRE_EUR    NUMBER(12,2)  COMMENT 'Coût de main d''oeuvre (EUR)',
  COUT_PIECES_EUR         NUMBER(12,2)  COMMENT 'Coût des pièces de rechange (EUR)',
  CONSTRAINT PK_FACT_INTERVENTION PRIMARY KEY (INTERVENTION_ID),
  CONSTRAINT FK_INT_INCIDENT FOREIGN KEY (INCIDENT_ID) REFERENCES FACT_INCIDENT (INCIDENT_ID),
  CONSTRAINT FK_INT_EQUIPE FOREIGN KEY (EQUIPE_ID) REFERENCES DIM_EQUIPE_MAINTENANCE (EQUIPE_ID)
) COMMENT = 'Interventions des équipes de maintenance sur les incidents';
