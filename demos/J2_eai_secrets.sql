/* =============================================================================
   DEMO J2 matin - EXTERNAL ACCESS INTEGRATION & SECRETS
   Compte : PAID (les EAI ne sont pas disponibles sur un compte trial)
   Role   : ACCOUNTADMIN pour l'integration, SYSADMIN pour le reste
   API    : open-meteo.com (gratuite, sans cle) ; le secret illustre le pattern "cle d'API".
   Ancien LAB 2 exercice 7, joue en demo.
   ============================================================================= */

USE ROLE SYSADMIN;
CREATE WAREHOUSE IF NOT EXISTS WH_DEMO WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 INITIALLY_SUSPENDED = TRUE;
USE WAREHOUSE WH_DEMO;
CREATE DATABASE IF NOT EXISTS DEMO_FORMATION;
CREATE SCHEMA IF NOT EXISTS DEMO_FORMATION.COMMON;
USE SCHEMA DEMO_FORMATION.COMMON;

-- -----------------------------------------------------------------------------
-- 1. Network rule : liste blanche des hotes joignables (objet de schema)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE NETWORK RULE NR_OPEN_METEO
  MODE = EGRESS TYPE = HOST_PORT
  VALUE_LIST = ('api.open-meteo.com');

-- -----------------------------------------------------------------------------
-- 2. Secret : la valeur n'est jamais lisible en SQL, seulement depuis le code autorise
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SECRET SEC_API_DEMO
  TYPE = GENERIC_STRING
  SECRET_STRING = 'cle-api-fictive-formation';
DESCRIBE SECRET SEC_API_DEMO;            -- pas de valeur affichee

-- -----------------------------------------------------------------------------
-- 3. External access integration (objet compte) : network rules + secrets autorises
-- -----------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION EAI_FORMATION
  ALLOWED_NETWORK_RULES = (DEMO_FORMATION.COMMON.NR_OPEN_METEO)
  ALLOWED_AUTHENTICATION_SECRETS = (DEMO_FORMATION.COMMON.SEC_API_DEMO)
  ENABLED = TRUE
  COMMENT = 'Demo formation : appels API open-meteo';
GRANT USAGE ON INTEGRATION EAI_FORMATION TO ROLE SYSADMIN;
USE ROLE SYSADMIN;

-- -----------------------------------------------------------------------------
-- 4. UDF Python qui appelle l'API
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION DEMO_FORMATION.COMMON.GET_WEATHER(LAT FLOAT, LON FLOAT)
  RETURNS VARIANT
  LANGUAGE PYTHON
  RUNTIME_VERSION = '3.11'
  HANDLER = 'main'
  EXTERNAL_ACCESS_INTEGRATIONS = (EAI_FORMATION)
  PACKAGES = ('requests')
AS
$$
import requests

def main(lat, lon):
    r = requests.get(
        "https://api.open-meteo.com/v1/forecast",
        params={"latitude": lat, "longitude": lon, "current_weather": "true"},
        timeout=10,
    )
    r.raise_for_status()
    return r.json()["current_weather"]
$$;

SELECT DEMO_FORMATION.COMMON.GET_WEATHER(48.86, 2.35) AS METEO_PARIS;

-- -----------------------------------------------------------------------------
-- 5. Cas d'usage : enrichir TPCH avec la meteo des capitales (ancien exercice de lab)
-- -----------------------------------------------------------------------------
USE SCHEMA DEMO_FORMATION.COMMON;
CREATE OR REPLACE TABLE NATION_GEO (N_NAME STRING, CAPITALE STRING, LAT FLOAT, LON FLOAT);
INSERT INTO NATION_GEO VALUES
  ('ALGERIA','Alger',36.75,3.06), ('ARGENTINA','Buenos Aires',-34.60,-58.38),
  ('BRAZIL','Brasilia',-15.79,-47.88), ('CANADA','Ottawa',45.42,-75.70),
  ('EGYPT','Le Caire',30.04,31.24), ('ETHIOPIA','Addis-Abeba',9.03,38.74),
  ('FRANCE','Paris',48.86,2.35), ('GERMANY','Berlin',52.52,13.40),
  ('INDIA','New Delhi',28.61,77.21), ('INDONESIA','Jakarta',-6.21,106.85),
  ('IRAN','Teheran',35.69,51.39), ('IRAQ','Bagdad',33.31,44.37),
  ('JAPAN','Tokyo',35.68,139.69), ('JORDAN','Amman',31.95,35.93),
  ('KENYA','Nairobi',-1.29,36.82), ('MOROCCO','Rabat',34.02,-6.83),
  ('MOZAMBIQUE','Maputo',-25.97,32.57), ('PERU','Lima',-12.05,-77.04),
  ('CHINA','Pekin',39.90,116.41), ('ROMANIA','Bucarest',44.43,26.10),
  ('SAUDI ARABIA','Riyad',24.71,46.68), ('VIETNAM','Hanoi',21.03,105.85),
  ('RUSSIA','Moscou',55.76,37.62), ('UNITED KINGDOM','Londres',51.51,-0.13),
  ('UNITED STATES','Washington',38.91,-77.04);

SELECT N_NAME, CAPITALE, DEMO_FORMATION.COMMON.GET_WEATHER(LAT, LON) AS METEO
FROM NATION_GEO LIMIT 5;

CREATE OR REPLACE FUNCTION GET_TEMP_MAX_DEMAIN(LAT FLOAT, LON FLOAT)
  RETURNS FLOAT
  LANGUAGE PYTHON
  RUNTIME_VERSION = '3.11'
  HANDLER = 'main'
  EXTERNAL_ACCESS_INTEGRATIONS = (EAI_FORMATION)
  SECRETS = ('api_key' = DEMO_FORMATION.COMMON.SEC_API_DEMO)
  PACKAGES = ('requests')
AS
$$
import requests
import _snowflake

def main(lat, lon):
    _ = _snowflake.get_generic_secret_string('api_key')   # ex. headers={"Authorization": f"Bearer {_}"}
    r = requests.get(
        "https://api.open-meteo.com/v1/forecast",
        params={"latitude": lat, "longitude": lon,
                "daily": "temperature_2m_max", "forecast_days": 2, "timezone": "auto"},
        timeout=10,
    )
    r.raise_for_status()
    return r.json()["daily"]["temperature_2m_max"][1]
$$;

WITH CA AS (
  SELECT n.N_NAME, SUM(o.O_TOTALPRICE) AS CA
  FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS o
  JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER c ON c.C_CUSTKEY = o.O_CUSTKEY
  JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION   n ON n.N_NATIONKEY = c.C_NATIONKEY
  GROUP BY 1
)
SELECT ca.N_NAME, g.CAPITALE, ROUND(ca.CA / 1e6, 1) AS CA_MEUR,
       GET_TEMP_MAX_DEMAIN(g.LAT, g.LON) AS TEMP_MAX_DEMAIN
FROM CA ca JOIN NATION_GEO g USING (N_NAME)
ORDER BY CA_MEUR DESC;

-- Point 5 : un appel vers air-quality-api.open-meteo.com echoue (erreur de
-- connexion / host non autorise) : seuls les hotes de la NETWORK RULE sont
-- joignables. La securite reseau est declaree par l'admin, pas par le developpeur.

-- Cle de lecture pour le public : la securite reseau (quels hotes, quels secrets)
-- est decidee par l'admin dans l'EAI ; le developpeur ne fait que l'utiliser.
-- Autres usages : appels d'API metier, LLM externes, envoi vers un webhook, dbt deps.

-- Nettoyage
-- DROP FUNCTION DEMO_FORMATION.COMMON.GET_TEMP_MAX_DEMAIN(FLOAT, FLOAT);
-- DROP FUNCTION DEMO_FORMATION.COMMON.GET_WEATHER(FLOAT, FLOAT);
-- USE ROLE ACCOUNTADMIN; DROP INTEGRATION EAI_FORMATION;
