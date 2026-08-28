-- =============================================================================
-- Day 3 — Architecture Bootcamp I: Instance vs. Database, Memory at a Glance
-- setup.sql
--
-- Purpose : Confirm the environment this day depends on already exists and is
--           in the expected shape. Day 3 is purely observational (dictionary /
--           V$ views only) — it does NOT create, modify, or drop any PERF_LAB
--           objects, so this script has nothing to build. It only VERIFIES:
--             1. We are on Oracle Database 19c.
--             2. This is a multitenant CDB (per the standard lab design).
--             3. The PERFPDB application container exists and is open READ WRITE.
--             4. The PERF_LAB schema exists inside PERFPDB.
--           If PERF_LAB / PERFPDB do not exist yet, that is a prerequisite lab
--           build step OWNED BY THE MAIN SETUP (setup/01_create_user.sql etc.)
--           — this script only checks, it never creates the base lab.
--
-- Connect as : a DBA-privileged account at the CDB root (e.g. SYSTEM, or SYS
--              AS SYSDBA). PERF_LAB itself is an ordinary local application
--              schema inside PERFPDB and is not expected to have V$/CDB_ view
--              access — every Day 3 script (demo/diagnose/fix/validate) is run
--              from this same DBA-privileged account, at the CDB root, unless
--              a step explicitly says otherwise.
--
-- ENVIRONMENT DEPENDENT: exact instance name, host name, container name(s),
-- and PDB service names below are illustrative (PERFCDB1 / PERFPDB) — replace
-- with your lab's actual values if they differ. Nothing in this script assumes
-- a specific value; it only checks structure and state.
-- =============================================================================

SET LINESIZE 150
SET PAGESIZE 100
COLUMN name           FORMAT A15
COLUMN db_name        FORMAT A12
COLUMN pdb_name       FORMAT A15
COLUMN open_mode      FORMAT A12
COLUMN instance_name  FORMAT A15
COLUMN host_name      FORMAT A25

PROMPT
PROMPT === Day 3 setup: environment verification (no objects created) ===
PROMPT

-- 1. Confirm Oracle version (19c baseline for this course)
PROMPT --- 1. Oracle version ---
SELECT banner_full FROM v$version WHERE banner_full LIKE 'Oracle Database%';

-- 2. Confirm we're connected to the CDB root and this is a CDB
PROMPT --- 2. Current container and CDB status ---
SELECT SYS_CONTEXT('USERENV','CON_NAME') AS current_container,
       SYS_CONTEXT('USERENV','CON_ID')   AS current_con_id
FROM   dual;

SELECT name AS db_name, cdb, open_mode, log_mode, platform_name
FROM   v$database;

-- 3. Confirm the PERFPDB application container exists and is open READ WRITE
PROMPT --- 3. PERFPDB container status (expect OPEN_MODE = READ WRITE) ---
SELECT con_id, pdb_name, status, open_mode, restricted
FROM   v$pdbs
ORDER  BY con_id;

-- If PERFPDB is not READ WRITE, open it before proceeding with any Day 3 script:
--   ALTER PLUGGABLE DATABASE PERFPDB OPEN;
-- (This is exactly the Troubleshooting Challenge scenario in day03-content.md —
--  do not "fix" it silently here; if you hit it, that's a teaching moment, not
--  a setup bug.)

-- 4. Confirm PERF_LAB exists inside PERFPDB (built by the main course setup,
--    not by this script). This step only queries CDB_USERS from the root, so
--    it does not require switching containers.
PROMPT --- 4. Confirm PERF_LAB schema exists inside PERFPDB ---
SELECT con_id, username, account_status, created
FROM   cdb_users
WHERE  username = 'PERF_LAB'
ORDER  BY con_id;

PROMPT
PROMPT If all four checks above returned rows as expected, the environment is
PROMPT ready for Day 3 — proceed to demo.sql. No grants, tables, or other
PROMPT objects are required for this day.
PROMPT
