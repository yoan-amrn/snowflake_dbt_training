-- =====================================================================
-- DEMO CORTEX AGENT - Analyse des pannes réseau Métro / Tram (Lyon)
-- 03 - DONNEES DE REFERENCE
-- ---------------------------------------------------------------------
-- Lignes / stations inspirées du réseau lyonnais réel.
-- Fréquentations, flottes, équipements, fabricants : valeurs FICTIVES.
-- =====================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA DB_YAR.MAINTENANCE;

-- ---------------------------------------------------------------------
-- 1. Lignes
-- ---------------------------------------------------------------------
INSERT INTO DIM_LIGNE
  (LIGNE_ID, NOM_LIGNE, MODE_TRANSPORT, TERMINUS_1, TERMINUS_2, LONGUEUR_KM, NB_STATIONS,
   ANNEE_MISE_EN_SERVICE, CONDUITE_AUTOMATIQUE, FREQUENTATION_JOUR_MOY, INTERVALLE_POINTE_MIN)
VALUES
  ('A',  'Métro A', 'Métro', 'Perrache', 'Vaulx-en-Velin La Soie',            9.2, NULL, 1978, FALSE, 290000,  2.5),
  ('B',  'Métro B', 'Métro', 'Charpennes', 'Saint-Genis-Laval Hôpitaux Sud',  9.6, NULL, 1978, TRUE,  200000,  2.0),
  ('C',  'Métro C', 'Métro', 'Hôtel de Ville', 'Cuire',                       2.5, NULL, 1978, FALSE,  30000,  5.0),
  ('D',  'Métro D', 'Métro', 'Gare de Vaise', 'Gare de Vénissieux',          12.6, NULL, 1991, TRUE,  330000,  2.0),
  ('F1', 'Funiculaire F1', 'Funiculaire', 'Vieux Lyon', 'Saint-Just',         0.8, NULL, 1878, FALSE,   8000, 10.0),
  ('F2', 'Funiculaire F2', 'Funiculaire', 'Vieux Lyon', 'Fourvière',          0.4, NULL, 1900, FALSE,   9000, 10.0),
  ('T1', 'Tram T1', 'Tramway', 'IUT-Feyssine', 'Debourg',                     9.8, NULL, 2001, FALSE,  90000,  5.0),
  ('T2', 'Tram T2', 'Tramway', 'Perrache', 'Saint-Priest Bel Air',           15.0, NULL, 2001, FALSE,  85000,  5.0),
  ('T3', 'Tram T3', 'Tramway', 'Gare Part-Dieu-Villette', 'Meyzieu ZI',      14.8, NULL, 2006, FALSE,  50000,  7.0),
  ('T4', 'Tram T4', 'Tramway', 'Hôpital Feyzin Vénissieux', 'La Doua-Gaston Berger', 16.5, NULL, 2009, FALSE, 85000, 5.0),
  ('T5', 'Tram T5', 'Tramway', 'Grange Blanche', 'Eurexpo',                   7.0, NULL, 2012, FALSE,  15000, 10.0),
  ('T6', 'Tram T6', 'Tramway', 'Debourg', 'Hôpitaux Est-Pinel',               6.7, NULL, 2019, FALSE,  30000,  8.0),
  ('T7', 'Tram T7', 'Tramway', 'Vaulx-en-Velin La Soie', 'Décines OL Vallée', 2.2, NULL, 2021, FALSE,   3000, 15.0);

-- ---------------------------------------------------------------------
-- 2. Stations
-- ---------------------------------------------------------------------
INSERT INTO DIM_STATION
  (STATION_ID, NOM_STATION, LIGNE_ID, ORDRE_SUR_LIGNE, COMMUNE, EST_CORRESPONDANCE, EST_SOUTERRAINE)
SELECT v.id, v.nom, v.ligne, TO_NUMBER(RIGHT(v.id, 2)), v.commune, v.corresp,
       l.MODE_TRANSPORT <> 'Tramway'
FROM VALUES
  -- Métro A
  ('A01','Perrache','A','Lyon 2e',TRUE),
  ('A02','Ampère-Victor Hugo','A','Lyon 2e',FALSE),
  ('A03','Bellecour','A','Lyon 2e',TRUE),
  ('A04','Cordeliers','A','Lyon 2e',FALSE),
  ('A05','Hôtel de Ville-Louis Pradel','A','Lyon 1er',TRUE),
  ('A06','Foch','A','Lyon 6e',FALSE),
  ('A07','Masséna','A','Lyon 6e',FALSE),
  ('A08','Charpennes-Charles Hernu','A','Villeurbanne',TRUE),
  ('A09','République-Villeurbanne','A','Villeurbanne',FALSE),
  ('A10','Gratte-Ciel','A','Villeurbanne',FALSE),
  ('A11','Flachet-Alain Gilles','A','Villeurbanne',FALSE),
  ('A12','Cusset','A','Villeurbanne',FALSE),
  ('A13','Laurent Bonnevay-Astroballe','A','Villeurbanne',FALSE),
  ('A14','Vaulx-en-Velin La Soie','A','Vaulx-en-Velin',TRUE),
  -- Métro B
  ('B01','Charpennes-Charles Hernu','B','Villeurbanne',TRUE),
  ('B02','Brotteaux','B','Lyon 6e',FALSE),
  ('B03','Gare Part-Dieu-Vivier Merle','B','Lyon 3e',TRUE),
  ('B04','Place Guichard-Bourse du Travail','B','Lyon 3e',FALSE),
  ('B05','Saxe-Gambetta','B','Lyon 7e',TRUE),
  ('B06','Jean Macé','B','Lyon 7e',FALSE),
  ('B07','Place Jean Jaurès','B','Lyon 7e',FALSE),
  ('B08','Debourg','B','Lyon 7e',TRUE),
  ('B09','Stade de Gerland-Le LOU','B','Lyon 7e',FALSE),
  ('B10','Gare d''Oullins','B','Oullins-Pierre-Bénite',FALSE),
  ('B11','Oullins Centre','B','Oullins-Pierre-Bénite',FALSE),
  ('B12','Saint-Genis-Laval Hôpitaux Sud','B','Saint-Genis-Laval',FALSE),
  -- Métro C
  ('C01','Hôtel de Ville-Louis Pradel','C','Lyon 1er',TRUE),
  ('C02','Croix-Paquet','C','Lyon 1er',FALSE),
  ('C03','Croix-Rousse','C','Lyon 4e',FALSE),
  ('C04','Hénon','C','Lyon 4e',FALSE),
  ('C05','Cuire','C','Caluire-et-Cuire',FALSE),
  -- Métro D
  ('D01','Gare de Vaise','D','Lyon 9e',FALSE),
  ('D02','Valmy','D','Lyon 9e',FALSE),
  ('D03','Gorge de Loup','D','Lyon 9e',FALSE),
  ('D04','Vieux Lyon-Cathédrale Saint-Jean','D','Lyon 5e',TRUE),
  ('D05','Bellecour','D','Lyon 2e',TRUE),
  ('D06','Guillotière-Gabriel Péri','D','Lyon 7e',FALSE),
  ('D07','Saxe-Gambetta','D','Lyon 7e',TRUE),
  ('D08','Garibaldi','D','Lyon 7e',FALSE),
  ('D09','Sans Souci','D','Lyon 3e',FALSE),
  ('D10','Monplaisir-Lumière','D','Lyon 8e',FALSE),
  ('D11','Grange Blanche','D','Lyon 8e',TRUE),
  ('D12','Laënnec','D','Lyon 8e',FALSE),
  ('D13','Mermoz-Pinel','D','Lyon 8e',TRUE),
  ('D14','Parilly','D','Vénissieux',FALSE),
  ('D15','Gare de Vénissieux','D','Vénissieux',FALSE),
  -- Funiculaires
  ('F101','Vieux Lyon','F1','Lyon 5e',TRUE),
  ('F102','Minimes-Théâtres Romains','F1','Lyon 5e',FALSE),
  ('F103','Saint-Just','F1','Lyon 5e',FALSE),
  ('F201','Vieux Lyon','F2','Lyon 5e',TRUE),
  ('F202','Fourvière','F2','Lyon 5e',FALSE),
  -- Tram T1
  ('T101','IUT-Feyssine','T1','Villeurbanne',FALSE),
  ('T102','La Doua-Gaston Berger','T1','Villeurbanne',TRUE),
  ('T103','Université Lyon 1','T1','Villeurbanne',FALSE),
  ('T104','Charpennes','T1','Villeurbanne',TRUE),
  ('T105','Thiers-Lafayette','T1','Lyon 6e',FALSE),
  ('T106','Gare Part-Dieu-Villette','T1','Lyon 3e',TRUE),
  ('T107','Liberté','T1','Lyon 3e',FALSE),
  ('T108','Saxe-Préfecture','T1','Lyon 3e',FALSE),
  ('T109','Perrache','T1','Lyon 2e',TRUE),
  ('T110','Hôtel de Région-Montrochet','T1','Lyon 2e',FALSE),
  ('T111','Musée des Confluences','T1','Lyon 2e',FALSE),
  ('T112','Halle Tony Garnier','T1','Lyon 7e',FALSE),
  ('T113','Debourg','T1','Lyon 7e',TRUE),
  -- Tram T2
  ('T201','Perrache','T2','Lyon 2e',TRUE),
  ('T202','Centre Berthelot','T2','Lyon 7e',FALSE),
  ('T203','Jet d''Eau-Mendès France','T2','Lyon 8e',TRUE),
  ('T204','Bachut-Mairie du 8e','T2','Lyon 8e',FALSE),
  ('T205','Jean XXIII-Maryse Bastié','T2','Lyon 8e',FALSE),
  ('T206','Boutasse-Camille Rousset','T2','Bron',TRUE),
  ('T207','Essarts-Iris','T2','Bron',FALSE),
  ('T208','Hôtel de Ville Bron','T2','Bron',FALSE),
  ('T209','Parc Technologique','T2','Saint-Priest',FALSE),
  ('T210','Saint-Priest Bel Air','T2','Saint-Priest',FALSE),
  -- Tram T3
  ('T301','Gare Part-Dieu-Villette','T3','Lyon 3e',TRUE),
  ('T302','Dauphiné-Lacassagne','T3','Lyon 3e',FALSE),
  ('T303','Reconnaissance-Balzac','T3','Villeurbanne',FALSE),
  ('T304','Gare de Villeurbanne','T3','Villeurbanne',FALSE),
  ('T305','Bel Air-Les Brosses','T3','Villeurbanne',FALSE),
  ('T306','Vaulx-en-Velin La Soie','T3','Vaulx-en-Velin',TRUE),
  ('T307','Décines Centre','T3','Décines-Charpieu',FALSE),
  ('T308','Meyzieu Gare','T3','Meyzieu',FALSE),
  ('T309','Meyzieu ZI','T3','Meyzieu',FALSE),
  -- Tram T4
  ('T401','Hôpital Feyzin Vénissieux','T4','Feyzin',FALSE),
  ('T402','Vénissieux-Croizat','T4','Vénissieux',FALSE),
  ('T403','Lycée Jacques Brel','T4','Vénissieux',FALSE),
  ('T404','Etats-Unis-Musée Tony Garnier','T4','Lyon 8e',FALSE),
  ('T405','Jet d''Eau-Mendès France','T4','Lyon 8e',TRUE),
  ('T406','Manufacture-Montluc','T4','Lyon 3e',FALSE),
  ('T407','Gare Part-Dieu-Villette','T4','Lyon 3e',TRUE),
  ('T408','Charpennes','T4','Villeurbanne',TRUE),
  ('T409','La Doua-Gaston Berger','T4','Villeurbanne',TRUE),
  -- Tram T5
  ('T501','Grange Blanche','T5','Lyon 8e',TRUE),
  ('T502','Ambroise Paré','T5','Lyon 8e',FALSE),
  ('T503','Boutasse-Camille Rousset','T5','Bron',TRUE),
  ('T504','Hôtel de Ville Bron','T5','Bron',FALSE),
  ('T505','Parc du Chêne','T5','Bron',FALSE),
  ('T506','Eurexpo','T5','Chassieu',FALSE),
  -- Tram T6
  ('T601','Debourg','T6','Lyon 7e',TRUE),
  ('T602','Challemel-Lacour-Artillerie','T6','Lyon 7e',FALSE),
  ('T603','Moulin à Vent','T6','Lyon 8e',FALSE),
  ('T604','Beauvisage-Pressensé','T6','Lyon 8e',FALSE),
  ('T605','Mermoz-Moselle','T6','Lyon 8e',FALSE),
  ('T606','Mermoz-Pinel','T6','Lyon 8e',TRUE),
  ('T607','Hôpitaux Est-Pinel','T6','Bron',FALSE),
  -- Tram T7
  ('T701','Vaulx-en-Velin La Soie','T7','Vaulx-en-Velin',TRUE),
  ('T702','Décines Grand Large','T7','Décines-Charpieu',FALSE),
  ('T703','Décines OL Vallée','T7','Décines-Charpieu',FALSE)
AS v(id, nom, ligne, commune, corresp)
JOIN DIM_LIGNE l ON l.LIGNE_ID = v.ligne;

-- Nombre de stations par ligne
UPDATE DIM_LIGNE
SET NB_STATIONS = c.nb
FROM (SELECT LIGNE_ID, COUNT(*) AS nb FROM DIM_STATION GROUP BY LIGNE_ID) c
WHERE DIM_LIGNE.LIGNE_ID = c.LIGNE_ID;

-- ---------------------------------------------------------------------
-- 3. Equipes de maintenance
-- ---------------------------------------------------------------------
INSERT INTO DIM_EQUIPE_MAINTENANCE (EQUIPE_ID, NOM_EQUIPE, SPECIALITE, BASE, STATUT_EQUIPE, EFFECTIF)
VALUES
  ('EQ01', 'Maintenance matériel roulant métro',     'Matériel roulant',          'Atelier métro de la Poudrette (Vaulx-en-Velin)', 'Interne',      24),
  ('EQ02', 'Maintenance matériel roulant tramway',   'Matériel roulant',          'Dépôt tramway de Saint-Priest',                  'Interne',      20),
  ('EQ03', 'Signalisation & automatismes',           'Signalisation',             'Poste de Commande Centralisé (PCC)',             'Interne',      14),
  ('EQ04', 'Energie & traction électrique',          'Energie',                   'Centre technique de Gerland',                    'Interne',      16),
  ('EQ05', 'Voie & appareils de voie',               'Voie',                      'Centre technique de Gerland',                    'Interne',      18),
  ('EQ06', 'Escaliers mécaniques & ascenseurs',      'Equipements de station',    'Prestataire ascensoriste',                       'Sous-traitant',10),
  ('EQ07', 'Billettique & information voyageurs',    'Billettique',               'Centre technique de la Part-Dieu',               'Interne',       8),
  ('EQ08', 'Equipements techniques de station',      'Equipements de station',    'Centre technique de Gerland',                    'Interne',       9),
  ('EQ09', 'Equipe d''intervention rapide (astreinte)','Intervention rapide',     'Poste de Commande Centralisé (PCC)',             'Interne',      12);

-- ---------------------------------------------------------------------
-- 4. Types d'équipements (référentiel technique)
-- ---------------------------------------------------------------------
INSERT INTO REF_TYPE_EQUIPEMENT
  (TYPE_EQUIPEMENT, CODE, FAMILLE, NIVEAU, MODE_APPLICABLE, NB_PAR_UNITE, CRITICITE, FABRICANT_PRINCIPAL, POIDS_DEFAILLANCE, EQUIPE_ID)
VALUES
  ('Rame',                                'RAME', 'Matériel roulant',              'FLOTTE',  'TOUS',         NULL, 'Haute',   NULL,               1.00, 'EQ01'),
  ('Escalator',                           'ESC',  'Equipements de station',        'STATION', 'Métro',        2,    'Moyenne', 'Schindler',        1.50, 'EQ06'),
  ('Ascenseur',                           'ASC',  'Equipements de station',        'STATION', 'Métro',        1,    'Moyenne', 'Otis',             1.60, 'EQ06'),
  ('Ventilation / désenfumage',           'VENT', 'Equipements de station',        'STATION', 'Métro',        1,    'Haute',   'Systemair',        0.40, 'EQ08'),
  ('Distributeur automatique de titres',  'DAT',  'Billettique',                   'STATION', 'TOUS',         1,    'Faible',  'Thales',           0.90, 'EQ07'),
  ('Portillon de contrôle d''accès',      'PORT', 'Billettique',                   'STATION', 'SOUTERRAIN',   2,    'Faible',  'Conduent',         0.70, 'EQ07'),
  ('Ecran d''information voyageurs',      'SIV',  'Information voyageurs',         'STATION', 'TOUS',         1,    'Faible',  'Hanover Displays', 0.35, 'EQ07'),
  ('Signalisation',                       'SIG',  'Signalisation & automatismes',  'LIGNE',   'TOUS',         4,    'Haute',   'Alstom',           2.30, 'EQ03'),
  ('Sous-station d''alimentation',        'ALIM', 'Energie',                       'LIGNE',   'TOUS',         3,    'Haute',   'Alstom',           1.50, 'EQ04'),
  ('Caténaire',                           'CAT',  'Energie',                       'LIGNE',   'Tramway',      4,    'Haute',   'Alstom',           1.40, 'EQ04'),
  ('Rail de traction',                    'RAIL', 'Energie',                       'LIGNE',   'Métro',        2,    'Haute',   'Alstom',           1.20, 'EQ04'),
  ('Aiguillage',                          'AIG',  'Voie',                          'LIGNE',   'FERRE_URBAIN', 4,    'Haute',   'Vossloh',          1.10, 'EQ05'),
  ('Voie',                                'VOIE', 'Voie',                          'LIGNE',   'TOUS',         3,    'Haute',   'Vossloh',          1.00, 'EQ05');

-- ---------------------------------------------------------------------
-- 5. Catalogue des pannes
-- ---------------------------------------------------------------------
INSERT INTO REF_TYPE_PANNE
  (TYPE_PANNE_ID, TYPE_EQUIPEMENT, LIBELLE_PANNE, CATEGORIE_PANNE, MODE_APPLICABLE,
   GRAVITE_TYPIQUE, DUREE_MOYENNE_MIN, IMPACT_SERVICE_TYPIQUE, CONDITION_DECLENCHANTE, POIDS)
VALUES
  -- Matériel roulant
  ('P-RAM-01','Rame','Panne de traction','Electrique',NULL,4,55,'Interruption totale',NULL,1.0),
  ('P-RAM-02','Rame','Défaut du système de freinage','Mécanique',NULL,3,45,'Interruption partielle',NULL,0.8),
  ('P-RAM-03','Rame','Défaut de fermeture des portes','Mécanique',NULL,2,12,'Ralentissement','POINTE',1.5),
  ('P-RAM-04','Rame','Panne de climatisation','Electrique',NULL,1,180,'Aucun','CHALEUR',0.8),
  ('P-RAM-05','Rame','Malaise voyageur à bord','Externe',NULL,2,18,'Ralentissement','POINTE',1.2),
  ('P-RAM-06','Rame','Tirage abusif du signal d''alarme','Vandalisme',NULL,2,10,'Ralentissement',NULL,0.8),
  ('P-RAM-07','Rame','Défaut du pilote automatique embarqué','Logiciel','Métro',3,30,'Interruption partielle',NULL,0.6),
  ('P-RAM-08','Rame','Usure du câble de traction - arrêt de sécurité','Mécanique','Funiculaire',4,240,'Interruption totale',NULL,3.0),
  ('P-RAM-09','Rame','Défaut de pantographe','Electrique','Tramway',3,60,'Interruption partielle','INTEMPERIES',0.8),
  -- Escalators
  ('P-ESC-01','Escalator','Rupture de chaîne de marches','Mécanique',NULL,2,720,'Aucun',NULL,0.6),
  ('P-ESC-02','Escalator','Défaut moteur / variateur','Electrique',NULL,2,300,'Aucun',NULL,1.0),
  ('P-ESC-03','Escalator','Objet coincé dans le peigne','Externe',NULL,1,60,'Aucun',NULL,1.2),
  ('P-ESC-04','Escalator','Arrêt d''urgence actionné','Vandalisme',NULL,1,25,'Aucun',NULL,1.5),
  ('P-ESC-05','Escalator','Infiltration d''eau / court-circuit','Electrique',NULL,2,480,'Aucun','INTEMPERIES',0.4),
  -- Ascenseurs
  ('P-ASC-01','Ascenseur','Porte palière bloquée','Mécanique',NULL,2,180,'Aucun',NULL,1.2),
  ('P-ASC-02','Ascenseur','Défaut de carte de commande','Electronique',NULL,2,360,'Aucun',NULL,0.8),
  ('P-ASC-03','Ascenseur','Personne bloquée en cabine','Externe',NULL,3,40,'Aucun',NULL,0.5),
  ('P-ASC-04','Ascenseur','Dégradation de cabine','Vandalisme',NULL,1,240,'Aucun',NULL,0.8),
  -- Ventilation
  ('P-VEN-01','Ventilation / désenfumage','Arrêt d''un ventilateur de désenfumage','Electrique',NULL,3,300,'Aucun',NULL,1.0),
  ('P-VEN-02','Ventilation / désenfumage','Vibrations anormales / roulement usé','Mécanique',NULL,2,480,'Aucun','CHALEUR',0.8),
  -- Billettique
  ('P-DAT-01','Distributeur automatique de titres','Lecteur carte bancaire hors service','Electronique',NULL,1,240,'Aucun',NULL,1.2),
  ('P-DAT-02','Distributeur automatique de titres','Ecran figé / plantage logiciel','Logiciel',NULL,1,90,'Aucun',NULL,1.0),
  ('P-DAT-03','Distributeur automatique de titres','Effraction / dégradation','Vandalisme',NULL,2,720,'Aucun',NULL,0.5),
  ('P-DAT-04','Distributeur automatique de titres','Monnayeur bloqué','Mécanique',NULL,1,180,'Aucun',NULL,1.0),
  ('P-POR-01','Portillon de contrôle d''accès','Vantail bloqué','Mécanique',NULL,1,90,'Aucun',NULL,1.0),
  ('P-POR-02','Portillon de contrôle d''accès','Valideur sans contact hors service','Electronique',NULL,1,120,'Aucun',NULL,1.0),
  ('P-POR-03','Portillon de contrôle d''accès','Dégradation / forçage','Vandalisme',NULL,1,240,'Aucun','POINTE',0.7),
  -- Information voyageurs
  ('P-SIV-01','Ecran d''information voyageurs','Perte de connexion au système d''information','Logiciel',NULL,1,120,'Aucun',NULL,1.2),
  ('P-SIV-02','Ecran d''information voyageurs','Ecran éteint / dalle hors service','Electronique',NULL,1,600,'Aucun',NULL,0.8),
  -- Signalisation
  ('P-SIG-01','Signalisation','Défaut de circuit de voie','Electronique',NULL,4,45,'Interruption totale',NULL,1.0),
  ('P-SIG-02','Signalisation','Perte de communication CBTC / pilotage automatique','Logiciel','Métro',4,35,'Interruption totale','CBTC',1.0),
  ('P-SIG-03','Signalisation','Feu de signalisation hors service','Electrique',NULL,3,40,'Ralentissement',NULL,1.0),
  ('P-SIG-04','Signalisation','Coupure de câble lors de travaux tiers','Externe',NULL,4,200,'Interruption totale',NULL,0.3),
  ('P-SIG-05','Signalisation','Défaut de priorité tram aux carrefours','Electronique','Tramway',2,90,'Ralentissement',NULL,1.5),
  -- Energie
  ('P-ALI-01','Sous-station d''alimentation','Disjonction en sous-station','Electrique',NULL,4,30,'Interruption totale','INTEMPERIES',1.0),
  ('P-ALI-02','Sous-station d''alimentation','Défaut transformateur / redresseur','Electrique',NULL,3,150,'Interruption partielle','CHALEUR',0.6),
  ('P-ALI-03','Sous-station d''alimentation','Coupure du réseau électrique amont','Externe',NULL,4,50,'Interruption totale','INTEMPERIES',0.4),
  ('P-CAT-01','Caténaire','Rupture du fil de contact','Electrique',NULL,4,210,'Interruption totale',NULL,0.4),
  ('P-CAT-02','Caténaire','Objet accroché à la caténaire (branche, ballon)','Externe',NULL,3,45,'Interruption partielle','INTEMPERIES',1.0),
  ('P-CAT-03','Caténaire','Givre sur caténaire / perte de captage','Externe',NULL,2,60,'Ralentissement','GEL',1.0),
  ('P-RAI-01','Rail de traction','Défaut d''isolement du rail de traction','Electrique',NULL,3,90,'Interruption partielle',NULL,1.0),
  ('P-RAI-02','Rail de traction','Coupure d''urgence du courant traction','Externe',NULL,4,25,'Interruption totale',NULL,1.0),
  -- Voie
  ('P-AIG-01','Aiguillage','Aiguillage mal positionné / perte de contrôle','Mécanique',NULL,3,40,'Interruption partielle',NULL,1.0),
  ('P-AIG-02','Aiguillage','Gel / givre sur aiguillage','Externe',NULL,3,55,'Interruption partielle','GEL',1.0),
  ('P-AIG-03','Aiguillage','Défaut du moteur d''aiguille','Electrique',NULL,3,70,'Interruption partielle',NULL,0.8),
  ('P-VOI-01','Voie','Collision avec un véhicule routier','Externe','Tramway',4,80,'Interruption totale','POINTE',1.5),
  ('P-VOI-02','Voie','Véhicule stationné gênant sur la plateforme','Externe','Tramway',2,35,'Interruption partielle',NULL,1.5),
  ('P-VOI-03','Voie','Intrusion de personne sur les voies','Externe','Métro',4,25,'Interruption totale',NULL,1.5),
  ('P-VOI-04','Voie','Rail cassé / défaut de géométrie de voie','Mécanique',NULL,3,240,'Interruption partielle',NULL,0.5),
  ('P-VOI-05','Voie','Colis suspect','Externe',NULL,3,50,'Interruption totale',NULL,1.0);

-- ---------------------------------------------------------------------
-- 6. Parc d'équipements (généré)
-- ---------------------------------------------------------------------
INSERT INTO DIM_EQUIPEMENT
  (EQUIPEMENT_ID, LIBELLE_EQUIPEMENT, TYPE_EQUIPEMENT, FAMILLE_EQUIPEMENT, LIGNE_ID, STATION_ID,
   MODELE, FABRICANT, DATE_MISE_EN_SERVICE, CRITICITE)
WITH seq AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 50))
),
flotte AS (
  SELECT * FROM VALUES
    ('A',  32, 'MPL 75',              'Alstom',    '1978-04-28'::DATE),
    ('B',  30, 'MPL 16',              'Alstom',    '2022-06-01'::DATE),
    ('C',   6, 'MCL 80',              'SLM',       '1984-12-09'::DATE),
    ('D',  31, 'MPL 85',              'Alstom',    '1991-09-09'::DATE),
    ('F1',  2, 'Voiture funiculaire', 'Von Roll',  '1999-01-01'::DATE),
    ('F2',  2, 'Voiture funiculaire', 'Von Roll',  '1999-01-01'::DATE),
    ('T1', 16, 'Citadis 302',         'Alstom',    '2001-01-02'::DATE),
    ('T2', 20, 'Citadis 302',         'Alstom',    '2001-01-02'::DATE),
    ('T3', 14, 'Citadis 302',         'Alstom',    '2006-12-04'::DATE),
    ('T4', 16, 'Citadis 302',         'Alstom',    '2009-04-20'::DATE),
    ('T5',  6, 'Citadis 402',         'Alstom',    '2012-10-29'::DATE),
    ('T6',  8, 'Citadis X05',         'Alstom',    '2019-11-25'::DATE),
    ('T7',  3, 'Citadis 302',         'Alstom',    '2021-02-01'::DATE)
  AS f(ligne_id, nb_rames, modele, fabricant, date_livraison)
),
applicable AS (
  SELECT l.LIGNE_ID, l.MODE_TRANSPORT, l.ANNEE_MISE_EN_SERVICE, r.*
  FROM DIM_LIGNE l
  JOIN REF_TYPE_EQUIPEMENT r
    ON r.MODE_APPLICABLE = 'TOUS'
    OR r.MODE_APPLICABLE = l.MODE_TRANSPORT
    OR (r.MODE_APPLICABLE = 'SOUTERRAIN'   AND l.MODE_TRANSPORT IN ('Métro','Funiculaire'))
    OR (r.MODE_APPLICABLE = 'FERRE_URBAIN' AND l.MODE_TRANSPORT IN ('Métro','Tramway'))
)
-- Matériel roulant
SELECT 'RAME-' || f.ligne_id || '-' || LPAD(s.n, 3, '0'),
       'Rame ' || f.modele || ' n°' || s.n || ' - Ligne ' || f.ligne_id,
       'Rame', 'Matériel roulant', f.ligne_id, NULL, f.modele, f.fabricant,
       DATEADD(day, UNIFORM(0, 900, RANDOM()), f.date_livraison),
       'Haute'
FROM flotte f
JOIN seq s ON s.n <= f.nb_rames
UNION ALL
-- Equipements de station
SELECT a.CODE || '-' || st.STATION_ID || '-' || LPAD(s.n, 2, '0'),
       a.TYPE_EQUIPEMENT || ' n°' || s.n || ' - ' || st.NOM_STATION || ' (ligne ' || st.LIGNE_ID || ')',
       a.TYPE_EQUIPEMENT, a.FAMILLE, st.LIGNE_ID, st.STATION_ID, NULL, a.FABRICANT_PRINCIPAL,
       LEAST(DATEADD(day, UNIFORM(0, 7000, RANDOM()),
                     GREATEST(DATE_FROM_PARTS(a.ANNEE_MISE_EN_SERVICE, 1, 1), '2000-01-01'::DATE)),
             DATEADD(year, -1, CURRENT_DATE())),
       a.CRITICITE
FROM applicable a
JOIN DIM_STATION st ON st.LIGNE_ID = a.LIGNE_ID
JOIN seq s ON s.n <= a.NB_PAR_UNITE
WHERE a.NIVEAU = 'STATION'
UNION ALL
-- Infrastructure de ligne
SELECT a.CODE || '-' || a.LIGNE_ID || '-' || LPAD(s.n, 2, '0'),
       a.TYPE_EQUIPEMENT || ' - secteur ' || s.n || ' - Ligne ' || a.LIGNE_ID,
       a.TYPE_EQUIPEMENT, a.FAMILLE, a.LIGNE_ID, NULL,
       CASE WHEN a.CODE = 'SIG' AND a.LIGNE_ID IN ('B','D') THEN 'CBTC' ELSE NULL END,
       CASE WHEN a.CODE = 'SIG' AND a.LIGNE_ID IN ('B','D') THEN 'Siemens Mobility' ELSE a.FABRICANT_PRINCIPAL END,
       CASE WHEN a.CODE = 'SIG' AND a.LIGNE_ID = 'B'
            THEN DATEADD(month, -18, CURRENT_DATE())   -- nouveau système CBTC ligne B
            ELSE LEAST(DATEADD(day, UNIFORM(0, 6000, RANDOM()),
                               DATE_FROM_PARTS(GREATEST(a.ANNEE_MISE_EN_SERVICE, 1995), 1, 1)),
                       DATEADD(year, -1, CURRENT_DATE()))
       END,
       a.CRITICITE
FROM applicable a
JOIN seq s ON s.n <= a.NB_PAR_UNITE
WHERE a.NIVEAU = 'LIGNE';

-- ---------------------------------------------------------------------
-- 7. Météo journalière (24 derniers mois, simulée sur le climat lyonnais)
-- ---------------------------------------------------------------------
INSERT INTO METEO_JOURNALIERE
  (DATE_JOUR, TEMPERATURE_MIN_C, TEMPERATURE_MAX_C, PRECIPITATIONS_MM, VENT_RAFALES_KMH, EVENEMENT_METEO)
WITH jours AS (
  SELECT DATEADD(day, ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, DATEADD(month, -24, CURRENT_DATE())) AS d
  FROM TABLE(GENERATOR(ROWCOUNT => 800))
),
base AS (
  SELECT d,
         13 - 9.5 * COS(2 * PI() * (DAYOFYEAR(d) - 15) / 365) + NORMAL(0, 2.5, RANDOM()) AS t_moy,
         UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS u_pluie,
         UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS u_intensite,
         UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS u_vent
  FROM jours
  WHERE d <= CURRENT_DATE()
),
calc AS (
  SELECT d,
         ROUND(t_moy - 4.5 + NORMAL(0, 1.2, RANDOM()), 1) AS tmin,
         ROUND(t_moy + 6.0 + NORMAL(0, 1.5, RANDOM()), 1) AS tmax,
         IFF(u_pluie < 0.32, ROUND(0.5 + POW(u_intensite, 2.5) * 40, 1), 0) AS precip,
         ROUND(15 + POW(u_vent, 3) * 75) AS vent
  FROM base
)
SELECT d, tmin, tmax, precip, vent,
       CASE
         WHEN tmax < 4 AND tmin < 0 AND precip >= 2           THEN 'Neige'
         WHEN tmin < -1                                       THEN 'Gel'
         WHEN tmax >= 33                                      THEN 'Canicule'
         WHEN precip >= 15 AND MONTH(d) BETWEEN 5 AND 9       THEN 'Orage'
         WHEN vent >= 75                                      THEN 'Tempête / vent fort'
         WHEN precip >= 5                                     THEN 'Pluie'
         ELSE 'RAS'
       END
FROM calc;

-- ---------------------------------------------------------------------
-- Contrôles
-- ---------------------------------------------------------------------
SELECT 'DIM_LIGNE' AS table_name, COUNT(*) AS nb FROM DIM_LIGNE
UNION ALL SELECT 'DIM_STATION', COUNT(*) FROM DIM_STATION
UNION ALL SELECT 'DIM_EQUIPEMENT', COUNT(*) FROM DIM_EQUIPEMENT
UNION ALL SELECT 'REF_TYPE_PANNE', COUNT(*) FROM REF_TYPE_PANNE
UNION ALL SELECT 'DIM_EQUIPE_MAINTENANCE', COUNT(*) FROM DIM_EQUIPE_MAINTENANCE
UNION ALL SELECT 'METEO_JOURNALIERE', COUNT(*) FROM METEO_JOURNALIERE;

SELECT TYPE_EQUIPEMENT, COUNT(*) AS nb FROM DIM_EQUIPEMENT GROUP BY 1 ORDER BY 2 DESC;
SELECT EVENEMENT_METEO, COUNT(*) AS nb_jours FROM METEO_JOURNALIERE GROUP BY 1 ORDER BY 2 DESC;
