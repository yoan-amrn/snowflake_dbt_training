/* =============================================================================
   03 - PARTICIPANTS : 1 user + 1 role + 1 warehouse XS + 1 schema sandbox chacun
   Template Jinja (via deploy.sql) : {{ nb_participants }} participants.
   Idempotent : relancer avec un nombre plus grand ajoute les participants manquants.
   NB : les comptes recents imposent la MFA aux users TYPE=PERSON avec mot de
   passe -> prevoir 5 min en debut de J1 pour l'enrolement (passkey / TOTP).
   ============================================================================= */

USE ROLE ACCOUNTADMIN;

EXECUTE IMMEDIATE $$
DECLARE
  nb_participants INTEGER DEFAULT {{ nb_participants }};
  init_pwd        VARCHAR DEFAULT '{{ init_pwd }}';
  p               VARCHAR;
BEGIN
  FOR i IN 1 TO nb_participants DO
    p := 'P' || LPAD(TO_VARCHAR(i), 2, '0');

    -- Role personnel, rattache a la hierarchie
    EXECUTE IMMEDIATE 'CREATE ROLE IF NOT EXISTS R_' || p;
    EXECUTE IMMEDIATE 'GRANT ROLE FORMATION_PARTICIPANT TO ROLE R_' || p;
    EXECUTE IMMEDIATE 'GRANT ROLE R_' || p || ' TO ROLE SYSADMIN';

    -- Warehouse personnel (attribution des couts par participant -> FinOps)
    EXECUTE IMMEDIATE 'CREATE WAREHOUSE IF NOT EXISTS WH_' || p ||
      ' WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE';
    -- Ownership (et pas seulement USAGE) : le participant doit pouvoir accorder
    -- USAGE sur son warehouse aux roles qu'il cree dans le LAB 1 (RBAC).
    EXECUTE IMMEDIATE 'GRANT OWNERSHIP ON WAREHOUSE WH_' || p || ' TO ROLE R_' || p || ' COPY CURRENT GRANTS';

    -- Schema sandbox dont il est proprietaire
    EXECUTE IMMEDIATE 'CREATE SCHEMA IF NOT EXISTS SANDBOX.' || p;
    EXECUTE IMMEDIATE 'GRANT OWNERSHIP ON SCHEMA SANDBOX.' || p || ' TO ROLE R_' || p || ' COPY CURRENT GRANTS';

    -- Utilisateur
    EXECUTE IMMEDIATE 'CREATE USER IF NOT EXISTS ' || p ||
      ' PASSWORD = ''' || init_pwd || ''' MUST_CHANGE_PASSWORD = TRUE TYPE = PERSON' ||
      ' DEFAULT_ROLE = R_' || p || ' DEFAULT_WAREHOUSE = WH_' || p ||
      ' DEFAULT_NAMESPACE = SANDBOX.' || p;
    EXECUTE IMMEDIATE 'GRANT ROLE R_' || p || ' TO USER ' || p;
  END FOR;
  RETURN 'Participants crees : ' || nb_participants;
END;
$$;

SHOW USERS LIKE 'P%';
