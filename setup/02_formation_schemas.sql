/* =============================================================================
   02 - SCHEMAS FORMATION + privileges compte des labs
   A executer en ACCOUNTADMIN (via deploy.sql). Idempotent.
   ============================================================================= */

--------------------------------------------------------------------------------------------------------------
-- Schemas FORMATION : meme logique que ADMIN.GIT / ADMIN.SECURITY (01_account.sql)
--   - schema MANAGED ACCESS, proprietaire SYSADMIN
--   - roles techniques _FORMATION_<SCHEMA>_SR / _SW / _SFULL  (SR -> SW -> SFULL -> SYSADMIN)
--   - _SFULL -> FORMATION_ADMIN, _SR -> FORMATION_PARTICIPANT
--------------------------------------------------------------------------------------------------------------
use role sysadmin;

create schema if not exists FORMATION.COMMON  with managed access comment = 'Stages, file formats, secrets, integrations';
create schema if not exists FORMATION.RAW     with managed access comment = 'Donnees brutes ingerees';
create schema if not exists FORMATION.CURATED with managed access comment = 'Donnees transformees';
create schema if not exists FORMATION.ICEBERG with managed access comment = 'Tables Iceberg (stockage Snowflake-managed)';
create schema if not exists FORMATION.DBT     with managed access comment = 'Modeles du projet dbt (demo dbt Projects on Snowflake)';


-- SECURITYADMIN (MANAGE GRANTS) : creation des roles techniques + grants SR / SW / SFULL
use role securityadmin;

EXECUTE IMMEDIATE $$
DECLARE
  schemas ARRAY DEFAULT ['COMMON', 'RAW', 'CURATED', 'ICEBERG', 'DBT'];
  s       VARCHAR;  -- FORMATION.<SCHEMA>
  r       VARCHAR;  -- _FORMATION_<SCHEMA>
  owned   ARRAY DEFAULT ['TABLES', 'VIEWS', 'STAGES', 'FILE FORMATS', 'STREAMS', 'PROCEDURES',
                         'FUNCTIONS', 'SEQUENCES', 'TASKS', 'MATERIALIZED VIEWS', 'DYNAMIC TABLES',
                         'ICEBERG TABLES', 'PIPES'];
BEGIN
  FOR i IN 0 TO ARRAY_SIZE(schemas) - 1 DO
    s := 'FORMATION.' || schemas[i]::VARCHAR;
    r := '_FORMATION_' || schemas[i]::VARCHAR;

    /*object technical roles*/
    EXECUTE IMMEDIATE 'CREATE ROLE IF NOT EXISTS ' || r || '_SR';
    EXECUTE IMMEDIATE 'CREATE ROLE IF NOT EXISTS ' || r || '_SW';
    EXECUTE IMMEDIATE 'CREATE ROLE IF NOT EXISTS ' || r || '_SFULL';

    EXECUTE IMMEDIATE 'GRANT ROLE ' || r || '_SR TO ROLE ' || r || '_SW';
    EXECUTE IMMEDIATE 'GRANT ROLE ' || r || '_SW TO ROLE ' || r || '_SFULL';
    EXECUTE IMMEDIATE 'GRANT ROLE ' || r || '_SFULL TO ROLE SYSADMIN';

    /*user role*/
    EXECUTE IMMEDIATE 'GRANT ROLE ' || r || '_SR TO ROLE FORMATION_PARTICIPANT';
    EXECUTE IMMEDIATE 'GRANT ROLE ' || r || '_SFULL TO ROLE FORMATION_ADMIN';

    /*SR for read access*/
    EXECUTE IMMEDIATE 'GRANT USAGE ON DATABASE FORMATION TO ROLE ' || r || '_SR';
    EXECUTE IMMEDIATE 'GRANT USAGE ON SCHEMA ' || s || ' TO ROLE ' || r || '_SR';
    -- objets deja presents (relance du script)
    EXECUTE IMMEDIATE 'GRANT SELECT ON ALL TABLES IN SCHEMA ' || s || ' TO ROLE ' || r || '_SR';
    EXECUTE IMMEDIATE 'GRANT SELECT ON ALL VIEWS IN SCHEMA ' || s || ' TO ROLE ' || r || '_SR';
    EXECUTE IMMEDIATE 'GRANT SELECT ON FUTURE TABLES IN SCHEMA ' || s || ' TO ROLE ' || r || '_SR';
    EXECUTE IMMEDIATE 'GRANT SELECT ON FUTURE VIEWS IN SCHEMA ' || s || ' TO ROLE ' || r || '_SR';
    EXECUTE IMMEDIATE 'GRANT SELECT ON FUTURE STREAMS IN SCHEMA ' || s || ' TO ROLE ' || r || '_SR';
    EXECUTE IMMEDIATE 'GRANT SELECT ON FUTURE MATERIALIZED VIEWS IN SCHEMA ' || s || ' TO ROLE ' || r || '_SR';
    EXECUTE IMMEDIATE 'GRANT SELECT ON FUTURE DYNAMIC TABLES IN SCHEMA ' || s || ' TO ROLE ' || r || '_SR';
    EXECUTE IMMEDIATE 'GRANT SELECT ON FUTURE ICEBERG TABLES IN SCHEMA ' || s || ' TO ROLE ' || r || '_SR';
    EXECUTE IMMEDIATE 'GRANT USAGE, READ ON FUTURE STAGES IN SCHEMA ' || s || ' TO ROLE ' || r || '_SR';
    EXECUTE IMMEDIATE 'GRANT USAGE ON FUTURE FILE FORMATS IN SCHEMA ' || s || ' TO ROLE ' || r || '_SR';
    EXECUTE IMMEDIATE 'GRANT USAGE ON FUTURE PROCEDURES IN SCHEMA ' || s || ' TO ROLE ' || r || '_SR';
    EXECUTE IMMEDIATE 'GRANT USAGE ON FUTURE FUNCTIONS IN SCHEMA ' || s || ' TO ROLE ' || r || '_SR';
    EXECUTE IMMEDIATE 'GRANT USAGE ON FUTURE SEQUENCES IN SCHEMA ' || s || ' TO ROLE ' || r || '_SR';
    -- Demos : secrets et repos Git eventuels
    EXECUTE IMMEDIATE 'GRANT USAGE ON FUTURE SECRETS IN SCHEMA ' || s || ' TO ROLE ' || r || '_SR';
    EXECUTE IMMEDIATE 'GRANT READ ON FUTURE GIT REPOSITORIES IN SCHEMA ' || s || ' TO ROLE ' || r || '_SR';

    /*SW for write access*/
    EXECUTE IMMEDIATE 'GRANT INSERT, UPDATE, TRUNCATE, REFERENCES, DELETE ON FUTURE TABLES IN SCHEMA ' || s || ' TO ROLE ' || r || '_SW';
    EXECUTE IMMEDIATE 'GRANT READ, WRITE ON FUTURE STAGES IN SCHEMA ' || s || ' TO ROLE ' || r || '_SW';
    EXECUTE IMMEDIATE 'GRANT MONITOR, OPERATE ON FUTURE TASKS IN SCHEMA ' || s || ' TO ROLE ' || r || '_SW';

    /*SFULL for full access*/
    -- Liste plus large que ADMIN.SECURITY : le formateur cree stages, pipes, tasks,
    -- secrets, network rules, UDF EAI, repo Git et tables Iceberg dans ces schemas.
    EXECUTE IMMEDIATE 'GRANT CREATE TABLE, CREATE VIEW, CREATE FILE FORMAT, CREATE STAGE, CREATE PIPE,'
      || ' CREATE STREAM, CREATE TASK, CREATE SEQUENCE, CREATE FUNCTION, CREATE PROCEDURE,'
      || ' CREATE MATERIALIZED VIEW, CREATE DYNAMIC TABLE, CREATE ICEBERG TABLE,'
      || ' CREATE SECRET, CREATE NETWORK RULE, CREATE GIT REPOSITORY'
      || ' ON SCHEMA ' || s || ' TO ROLE ' || r || '_SFULL';
    -- Future OWNERSHIP : "already exists" a la relance -> ignore (idempotence)
    FOR j IN 0 TO ARRAY_SIZE(owned) - 1 DO
      BEGIN
        EXECUTE IMMEDIATE 'GRANT OWNERSHIP ON FUTURE ' || owned[j]::VARCHAR
          || ' IN SCHEMA ' || s || ' TO ROLE ' || r || '_SFULL';
      EXCEPTION
        WHEN STATEMENT_ERROR THEN
          IF (NOT CONTAINS(SQLERRM, 'already exists')) THEN RAISE; END IF;
      END;
    END FOR;
  END FOR;
  RETURN 'Schemas FORMATION configures : ' || ARRAY_TO_STRING(schemas, ', ');
END;
$$;

-- Demo dbt Projects on Snowflake (demos/J2_dbt_projects.sql)
GRANT CREATE DBT PROJECT ON SCHEMA FORMATION.DBT TO ROLE _FORMATION_DBT_SFULL;

-- Droits communs des participants hors schemas FORMATION (lecture FORMATION.* portee par les _SR)
use role sysadmin;
GRANT USAGE ON DATABASE SANDBOX TO ROLE FORMATION_PARTICIPANT;

-- -----------------------------------------------------------------------------
-- Privileges compte necessaires aux labs
-- -----------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;
-- Gouvernance (LAB 1) : tag-based masking necessite APPLY MASKING POLICY au niveau compte
GRANT APPLY MASKING POLICY    ON ACCOUNT TO ROLE FORMATION_PARTICIPANT;
GRANT APPLY ROW ACCESS POLICY ON ACCOUNT TO ROLE FORMATION_PARTICIPANT;
GRANT APPLY TAG               ON ACCOUNT TO ROLE FORMATION_PARTICIPANT;
-- RBAC : permettre aux participants de creer leurs propres roles (acceptable sur un trial)
GRANT CREATE ROLE ON ACCOUNT TO ROLE FORMATION_PARTICIPANT;
-- Monitoring / FinOps : vues ACCOUNT_USAGE en lecture
GRANT DATABASE ROLE SNOWFLAKE.USAGE_VIEWER      TO ROLE FORMATION_PARTICIPANT;
GRANT DATABASE ROLE SNOWFLAKE.GOVERNANCE_VIEWER TO ROLE FORMATION_PARTICIPANT;
-- Cortex : SNOWFLAKE.CORTEX_USER est accorde a PUBLIC par defaut. Si retire :
-- GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE FORMATION_PARTICIPANT;
-- Tasks (LAB 2) : tasks sur warehouse + tasks serverless
GRANT EXECUTE TASK         ON ACCOUNT TO ROLE FORMATION_PARTICIPANT;
GRANT EXECUTE MANAGED TASK ON ACCOUNT TO ROLE FORMATION_PARTICIPANT;
-- Tasks serverless du formateur : leur proprietaire est le role _SFULL du schema (future grants)
GRANT EXECUTE MANAGED TASK ON ACCOUNT TO ROLE _FORMATION_RAW_SFULL;   -- T_SIMULATED_SNOWPIPE
GRANT EXECUTE MANAGED TASK ON ACCOUNT TO ROLE _FORMATION_DBT_SFULL;   -- demo dbt
-- Les roles crees par les participants (LAB 1) heritent de PUBLIC :
-- ils doivent pouvoir "voir" la base SANDBOX pour atteindre le schema du participant.
GRANT USAGE ON DATABASE SANDBOX TO ROLE PUBLIC;
