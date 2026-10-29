/* =============================================================================
   99 - TEARDOWN : supprime tout ce que le repo a cree (fin de session / remise a zero)
   Template Jinja, en ACCOUNTADMIN :
     EXECUTE IMMEDIATE FROM @ADMIN.GIT.TRAINING_REPO/branches/main/setup/99_teardown.sql
       USING (nb_participants => 10, drop_git => FALSE);
   drop_git = TRUE supprime aussi le repo Git et l'API integration (il faudra
   rejouer 00_bootstrap_git.sql).  /!\ IRREVERSIBLE (hors time travel des bases).
   ============================================================================= */

USE ROLE ACCOUNTADMIN;

-- Demos eventuelles
DROP SHARE IF EXISTS SH_FORMATION;

-- Participants : users, warehouses, roles personnels et roles crees au LAB 1
EXECUTE IMMEDIATE $$
DECLARE
  nb_participants INTEGER DEFAULT {{ nb_participants }};
  p VARCHAR;
BEGIN
  FOR i IN 1 TO nb_participants DO
    p := 'P' || LPAD(TO_VARCHAR(i), 2, '0');
    EXECUTE IMMEDIATE 'DROP USER IF EXISTS ' || p;
    EXECUTE IMMEDIATE 'DROP WAREHOUSE IF EXISTS WH_' || p;
    EXECUTE IMMEDIATE 'DROP ROLE IF EXISTS ' || p || '_ANALYST';
    EXECUTE IMMEDIATE 'DROP ROLE IF EXISTS ' || p || '_PII_READER';
    EXECUTE IMMEDIATE 'DROP ROLE IF EXISTS R_' || p;
  END FOR;
  RETURN 'Participants supprimes : ' || nb_participants;
END;
$$;

-- Bases (schemas, tables, policies, tasks, apps Streamlit...)
DROP DATABASE IF EXISTS SANDBOX;
DROP DATABASE IF EXISTS FORMATION;

-- Warehouses et roles partages
DROP WAREHOUSE IF EXISTS WH_ADMIN;
DROP WAREHOUSE IF EXISTS WH_PERF_DEMO;
EXECUTE IMMEDIATE $$
DECLARE
  schemas ARRAY DEFAULT ['COMMON', 'RAW', 'CURATED', 'ICEBERG', 'DBT'];
BEGIN
  FOR i IN 0 TO ARRAY_SIZE(schemas) - 1 DO
    EXECUTE IMMEDIATE 'DROP ROLE IF EXISTS _FORMATION_' || schemas[i]::VARCHAR || '_SFULL';
    EXECUTE IMMEDIATE 'DROP ROLE IF EXISTS _FORMATION_' || schemas[i]::VARCHAR || '_SW';
    EXECUTE IMMEDIATE 'DROP ROLE IF EXISTS _FORMATION_' || schemas[i]::VARCHAR || '_SR';
  END FOR;
  RETURN 'Roles techniques FORMATION supprimes';
END;
$$;
DROP ROLE IF EXISTS FORMATION_PARTICIPANT;

ALTER ACCOUNT UNSET RESOURCE_MONITOR;
DROP RESOURCE MONITOR IF EXISTS RM_FORMATION;

-- Git / ADMIN (optionnel)
{% if drop_git %}
DROP DATABASE IF EXISTS ADMIN;
DROP API INTEGRATION IF EXISTS API_GITHUB_FORMATION;
DROP ROLE IF EXISTS _ADMIN_GIT_SFULL;
DROP ROLE IF EXISTS _ADMIN_GIT_SW;
DROP ROLE IF EXISTS _ADMIN_GIT_SR;
DROP ROLE IF EXISTS _ADMIN_SECURITY_SFULL;
DROP ROLE IF EXISTS _ADMIN_SECURITY_SW;
DROP ROLE IF EXISTS _ADMIN_SECURITY_SR;
DROP ROLE IF EXISTS FORMATION_ADMIN;
{% endif %}

SELECT 'Teardown termine' AS STATUS;
