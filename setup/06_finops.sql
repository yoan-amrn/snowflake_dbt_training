/* =============================================================================
   06 - GARDE-FOU FINOPS : resource monitor au niveau compte
   Template Jinja (via deploy.sql) : quota = {{ credit_quota }} credits / mois.
   Trial = 400 $ (~130 credits Enterprise selon region). Quota volontairement bas.
   ============================================================================= */

USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE RESOURCE MONITOR RM_FORMATION
  WITH CREDIT_QUOTA = {{ credit_quota }}
       FREQUENCY = MONTHLY
       START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 50 PERCENT DO NOTIFY
           ON 75 PERCENT DO NOTIFY
           ON 90 PERCENT DO SUSPEND
           ON 98 PERCENT DO SUSPEND_IMMEDIATE;
ALTER ACCOUNT SET RESOURCE_MONITOR = RM_FORMATION;

-- NB : un resource monitor ne couvre que les warehouses utilisateur, pas le
-- serverless (tasks managees, SOS, clustering, Cortex) -> voir demos/J1_finops.sql (budgets).
SHOW RESOURCE MONITORS LIKE 'RM_FORMATION';
