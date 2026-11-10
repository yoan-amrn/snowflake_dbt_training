# Démo Cortex Agent : analyse des pannes du réseau métro / tram de Lyon

Phase 1 : agent sur **données structurées** (Cortex Analyst + semantic view).

## Ordre d'exécution (worksheet Snowsight)

Objets existants réutilisés : base `DB_YAR` (propriété de `SYSADMIN`) et warehouse `COMPUTE_WH`.
Seuls deux schémas sont créés : `DB_YAR.MAINTENANCE` (données + semantic view) et `DB_YAR.AGENTS` (agent).
Tous les scripts s'exécutent avec le rôle `SYSADMIN`.

| Script | Contenu |
|---|---|
| `01_setup.sql` | Création des schémas `DB_YAR.MAINTENANCE` et `DB_YAR.AGENTS`, vérification des droits Cortex |
| `02_tables.sql` | Modèle en étoile (8 tables) |
| `03_donnees_referentiel.sql` | 13 lignes, 112 stations, ~900 équipements, 50 types de pannes, 9 équipes, 24 mois de météo |
| `04_generation_incidents.sql` | ~7 500 incidents + ~9 000 interventions sur les 24 derniers mois |
| `05_semantic_view.sql` | Semantic view `DB_YAR.MAINTENANCE.SV_PANNES_RESEAU` (dimensions, faits, métriques, synonymes) |
| `06_agent.sql` | Agent `DB_YAR.AGENTS.AGENT_PANNES_RESEAU_LYON` |
| `07_streamlit_app.sql` | Pré-requis runtime conteneur (accès PyPI, compute pool), schéma `DB_YAR.APPS`, déploiement de l'app `COCKPIT_PANNES_RESEAU` (projet Snowflake CLI dans `streamlit/`, `snow streamlit deploy`) |
| `99_nettoyage.sql` | Suppression des schémas de la démo |

## App Streamlit « Cockpit fiabilité réseau »

Les chiffres sont calculés en SQL ; l'agent est appelé (API REST `agent:run`) uniquement pour expliquer.

| Onglet | Contenu | Lien avec l'agent |
|---|---|---|
| 📊 Cockpit | KPI vs période précédente, tendance mensuelle par ligne, incidents par famille, synthèse par ligne | Bouton **« Pourquoi ? »** : périmètre + angle d'analyse → question pré-remplie |
| 🚨 Alertes de la semaine | Détection d'anomalies (z-score vs 26 semaines précédentes) par ligne ou station × type d'équipement | **« Diagnostiquer »** par alerte + **synthèse** de toutes les alertes |
| 🌦️ Préparation météo | Facteur de risque par équipement / ligne / panne selon l'événement prévu (gel, canicule…) et incidents attendus | **« Générer le plan de préparation »** |
| 💬 Question libre | Chat multi-tours en bas de page | Conversation directe |

Astuce démo : dans l'onglet Alertes, le bouton **« Exemple démo : pic ligne B »** positionne la semaine de référence sur le pic CBTC.

Les dates sont relatives à `CURRENT_DATE()` : rejouer les scripts 03 et 04 juste avant la démo pour avoir des données « fraîches ».

## Modèle de données

```
DIM_LIGNE ─────┐
DIM_STATION ───┤
DIM_EQUIPEMENT ┼──► FACT_INCIDENT ◄── FACT_INTERVENTION ──► DIM_EQUIPE_MAINTENANCE
REF_TYPE_PANNE ┤
METEO_JOURNALIERE
```

## Les « histoires » cachées dans les données

1. **Ligne B, migration CBTC** : il y a 18 mois, le nouveau système de pilotage automatique a provoqué un pic de pannes de signalisation pendant ~8 mois, puis la situation est revenue à la normale.
2. **Ligne D, escalators** : défaillances chroniques, surtout à Bellecour, avec des délais d'intervention plus longs (prestataire sous-traitant).
3. **Ligne A, rames MPL 75** : matériel vieillissant, plus de pannes de traction.
4. **Météo** : le gel et la neige touchent les aiguillages et caténaires du tram, les orages les caténaires et sous-stations, la canicule la climatisation des rames.
5. **Heures de pointe** : plus d'incidents (portes, malaises, collisions tram) et beaucoup plus de voyageurs impactés.

## Déroulé de démo suggéré (Snowflake Intelligence)

1. *« Donne-moi une vue d'ensemble des pannes sur le réseau ces 12 derniers mois par ligne : nombre, MTTR et voyageurs impactés. »*
2. *« Comment a évolué le nombre de pannes de signalisation sur la ligne B depuis 2 ans ? Montre-moi un graphique. »* → pic CBTC
3. *« Quels types de pannes expliquent ce pic ? »* → perte de communication CBTC
4. *« Quelles sont les 10 stations avec le plus de pannes d'escalators ? Compare le délai d'intervention du prestataire avec les équipes internes. »* → ligne D / Bellecour
5. *« Quel est l'impact du gel sur les pannes du tramway ? »* → aiguillages / caténaires
6. *« Les rames de la ligne A tombent-elles plus souvent en panne que celles des autres lignes de métro ? Rapporte au nombre de rames. »*
7. *« Quels types d'équipements nous coûtent le plus cher en maintenance corrective, et où faut-il prioriser la maintenance préventive ? »*

## Phase 2 (données non structurées)

- Générer des **comptes rendus d'intervention** en texte libre (`AI_COMPLETE` sur les interventions) et des **procédures de maintenance PDF**, puis les indexer avec **Cortex Search**.
- Ajouter un outil `cortex_search` à l'agent pour répondre à des questions comme « quelle est la procédure en cas de gel d'aiguillage ? » ou « que disent les techniciens sur les pannes CBTC de la ligne B ? ».
