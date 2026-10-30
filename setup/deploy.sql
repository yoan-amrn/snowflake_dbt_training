/* =============================================================================
   DEPLOY - orchestrateur du socle formation (template Jinja)
   Lance depuis 00_bootstrap_git.sql ou a la main, en ACCOUNTADMIN :

     ALTER GIT REPOSITORY ADMIN.GIT.TRAINING_REPO FETCH;
     EXECUTE IMMEDIATE FROM @ADMIN.GIT.TRAINING_REPO/branches/main/setup/deploy.sql
       USING (nb_participants => 10, init_pwd => '<mot_de_passe_initial>', credit_quota => 100);

   Parametres :
     nb_participants : nombre d'utilisateurs P01..Pnn
     init_pwd        : mot de passe initial (change a la 1re connexion)
     credit_quota    : quota mensuel du resource monitor compte
   Verifier le rendu sans rien executer : ajouter DRY_RUN = TRUE.
   Le script 05_lab_prep.sql (tables volumineuses, ~3-5 credits) se lance a part, la veille.
   ============================================================================= */

USE ROLE ACCOUNTADMIN;

EXECUTE IMMEDIATE FROM './01_account.sql';
EXECUTE IMMEDIATE FROM './02_formation_schemas.sql';
EXECUTE IMMEDIATE FROM './03_participants.sql'
  USING (nb_participants => {{ nb_participants }}, init_pwd => '{{ init_pwd }}');
EXECUTE IMMEDIATE FROM './04_data.sql';
EXECUTE IMMEDIATE FROM './06_finops.sql'
  USING (credit_quota => {{ credit_quota }});

USE ROLE ACCOUNTADMIN;
SELECT 'Socle formation deploye pour {{ nb_participants }} participants' AS STATUS;
