-- =============================================================================
-- PERF_LAB Setup — Script 01 of 7
-- 01_create_user.sql
--
-- Purpose: create the PERF_LAB schema/user, its dedicated tablespace, and
-- the MINIMUM privileges needed to run this course end to end. This is
-- deliberately NOT a DBA account — see the privilege list below.
--
-- Run connected as a DBA-privileged account (e.g. SYSTEM), against the
-- target PDB (this course's convention: PERFPDB) or non-CDB instance —
-- run 00_environment_check.sql first and resolve any FAIL there.
--
-- Usage:
--   sqlplus system/<password>@//localhost:1521/PERFPDB @01_create_user.sql
--
-- ENVIRONMENT DEPENDENT: the DATAFILE path below almost certainly needs to
-- change for your environment (OS filesystem layout, ASM diskgroup, or
-- Oracle Managed Files). The script prompts for it interactively with
-- ACCEPT so you are not silently pointed at a path that doesn't exist on
-- your server; press Enter to accept the shown default only if it is
-- actually valid on your instance.
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK ON
SET VERIFY OFF
SET ECHO OFF

PROMPT
PROMPT ================================================================================
PROMPT  PERF_LAB Setup — Step 1: create user, tablespace, and minimum privileges
PROMPT ================================================================================
PROMPT

-- -----------------------------------------------------------------------------
-- Prompt for the datafile destination. Defaults shown are typical for a
-- filesystem-based single-instance install; ASM/OMF users should point this
-- at their diskgroup (e.g. '+DATA') instead — Oracle accepts a diskgroup
-- name in place of a filesystem path in the DATAFILE clause.
-- -----------------------------------------------------------------------------
ACCEPT datafile_dir CHAR DEFAULT '/u01/app/oracle/oradata/PERFPDB' PROMPT 'Datafile directory (or ASM diskgroup, e.g. +DATA) [/u01/app/oracle/oradata/PERFPDB]: '

-- -----------------------------------------------------------------------------
-- 1. Dedicated tablespace for the PERF_LAB schema.
--
-- Sized generously for the Standard tier (see 04_generate_data.sql for the
-- Small/Standard/Large row-count profiles). ENVIRONMENT DEPENDENT: the
-- initial SIZE and MAXSIZE below are reasonable starting points for a
-- 4-8 CPU / 16-32GB Standard-tier lab VM with typical row widths in this
-- schema, but actual space consumed depends on your platform's block
-- size, PCTFREE defaults, and how compressible your storage is. Watch
-- DBA_DATA_FILES / DBA_FREE_SPACE during 04_generate_data.sql and grow
-- the datafile (or add another) if you hit ORA-01653/ORA-01654.
-- -----------------------------------------------------------------------------
PROMPT Creating tablespace PERF_LAB_DATA ...

CREATE TABLESPACE perf_lab_data
  DATAFILE '&datafile_dir/perf_lab_data01.dbf'
  SIZE 4G
  AUTOEXTEND ON NEXT 1G MAXSIZE 60G
  EXTENT MANAGEMENT LOCAL AUTOALLOCATE
  SEGMENT SPACE MANAGEMENT AUTO;

-- If your instance is configured with Oracle Managed Files (OMF), you can
-- omit the DATAFILE clause entirely and let Oracle place the file:
--   CREATE TABLESPACE perf_lab_data
--     SIZE 4G AUTOEXTEND ON NEXT 1G MAXSIZE 60G
--     EXTENT MANAGEMENT LOCAL AUTOALLOCATE
--     SEGMENT SPACE MANAGEMENT AUTO;

-- -----------------------------------------------------------------------------
-- 2. The PERF_LAB user.
--
-- *** PASSWORD BELOW IS A PLACEHOLDER — CHANGE THIS ***
-- Do not use this password for anything beyond a disposable local sandbox.
-- For a shared classroom/lab server, generate a unique password per
-- environment and store it outside this script (e.g. via ACCEPT ... HIDE,
-- an OS environment variable, or your organization's secrets manager).
-- -----------------------------------------------------------------------------
PROMPT Creating user PERF_LAB ...

CREATE USER perf_lab
  IDENTIFIED BY "ChangeMe_PerfLab#2026"   -- *** CHANGE THIS PASSWORD ***
  DEFAULT TABLESPACE perf_lab_data
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON perf_lab_data
  ACCOUNT UNLOCK;

-- If your instance uses a dedicated TEMP tablespace group or a
-- non-default temporary tablespace name, adjust the TEMPORARY TABLESPACE
-- clause above accordingly (query DATABASE_PROPERTIES for
-- DEFAULT_TEMP_TABLESPACE if unsure what your instance's default is).

-- -----------------------------------------------------------------------------
-- 3. Minimum privileges to RUN this course — not a DBA account.
--
-- This is deliberately the smallest set that lets a student create and
-- populate the PERF_LAB schema and run every stage of the course (SQL
-- tuning, PL/SQL objects, sequences). It does NOT include DBA, ANY-scoped
-- privileges, or the ability to alter the instance. Individual days will
-- occasionally need one more narrow privilege for that day's specific
-- lab mechanics (documented examples already in this course: Day 2 needs
-- CREATE JOB for its load-generator jobs; Day 4 needs quota on two extra
-- day-specific tablespaces) — grant those additions when that day's
-- setup script asks for them, rather than front-loading everything here.
-- -----------------------------------------------------------------------------
PROMPT Granting minimum system privileges ...

GRANT CREATE SESSION    TO perf_lab;   -- connect to the database
GRANT CREATE TABLE      TO perf_lab;   -- build the PERF_LAB schema (script 02)
GRANT CREATE PROCEDURE  TO perf_lab;   -- PL/SQL procedures/functions/packages used across many days
GRANT CREATE SEQUENCE   TO perf_lab;   -- sequences for any manual (non-IDENTITY) numbering later days introduce
GRANT CREATE VIEW       TO perf_lab;   -- several days build views as part of investigation/demo mechanics
GRANT CREATE TRIGGER    TO perf_lab;   -- occasionally used for demo instrumentation (e.g. audit-style triggers)
GRANT CREATE SYNONYM    TO perf_lab;   -- convenience synonyms some days' scripts use

-- Optional, commonly needed by SPECIFIC later days — left as clearly-labeled
-- commented-out grants rather than applied blindly here, so each is a
-- deliberate instructor decision made when that day actually calls for it:
--   GRANT CREATE JOB  TO perf_lab;   -- DBMS_SCHEDULER jobs (needed starting Day 2's load generators)
--   GRANT CREATE TYPE TO perf_lab;   -- object types, if a later day introduces them

-- -----------------------------------------------------------------------------
-- 4. SELECT on the V$/DBA_HIST views this course needs.
--
-- Rather than grant dozens of individual V_$/DBA_HIST_% object privileges,
-- this course grants the standard Oracle-supplied SELECT_CATALOG_ROLE,
-- which provides read-only SELECT access to the data dictionary (DBA_*
-- views) AND the V$/GV$ fixed views used throughout this course
-- (V$SESSION, V$SQL, V$ACTIVE_SESSION_HISTORY, V$SYSTEM_EVENT, and so on).
-- SELECT_CATALOG_ROLE carries NO DDL/DML/administrative privilege — it is
-- read-only, and is the standard, supported way to give a non-DBA account
-- broad read access to performance/diagnostic views. This matches what a
-- real performance-engineering role is normally granted in a shared
-- non-production lab.
--
-- *** LICENSE DEPENDENCY ***
-- SELECT_CATALOG_ROLE technically permits querying the DBA_HIST_* views
-- (Automatic Workload Repository history: DBA_HIST_SNAPSHOT,
-- DBA_HIST_ACTIVE_SESS_HISTORY, DBA_HIST_SQLSTAT, DBA_HIST_SYSSTAT,
-- DBA_HIST_SYS_TIME_MODEL, and others), but the RIGHT to actually rely on
-- that data in a real environment requires the Oracle Diagnostics Pack
-- license on Enterprise Edition (and SQL Tuning Advisor / SQL Access
-- Advisor additionally require the Tuning Pack). Oracle Database Free/XE
-- and Standard Edition 2 do not include these packs at all. Being able to
-- run a query against DBA_HIST_* in this lab does not mean your
-- organization is licensed to do so in a production or shared environment
-- — verify your organization's license position before relying on
-- DBA_HIST_*, AWR, ADDM, or SQL Monitor outside a personal/training
-- sandbox. This course's day-by-day material marks every LICENSE
-- DEPENDENCY day and, per the course design, provides an unlicensed
-- alternative for each one:
--   - V$ACTIVE_SESSION_HISTORY (in-memory ASH) instead of DBA_HIST_ACTIVE_SESS_HISTORY
--   - Statspack (free, all editions) instead of AWR snapshot/report workflows
--   - manual point-in-time V$SESSION/V$SQL sampling (snapper-style) instead of ASH
-- -----------------------------------------------------------------------------
PROMPT Granting SELECT_CATALOG_ROLE (covers V$/GV$ and DBA_*/DBA_HIST_* read access) ...

GRANT SELECT_CATALOG_ROLE TO perf_lab;

-- -----------------------------------------------------------------------------
-- 5. Confirm the grant landed as expected.
-- -----------------------------------------------------------------------------
PROMPT
PROMPT Verifying grants ...
COLUMN username FORMAT A12
COLUMN granted_role FORMAT A24
SELECT grantee AS username, granted_role
FROM   dba_role_privs
WHERE  grantee = 'PERF_LAB'
ORDER  BY granted_role;

COLUMN privilege FORMAT A24
SELECT grantee AS username, privilege
FROM   dba_sys_privs
WHERE  grantee = 'PERF_LAB'
ORDER  BY privilege;

COLUMN tablespace_name FORMAT A16
COLUMN max_bytes FORMAT 999,999,999,999
SELECT username, tablespace_name, max_bytes
FROM   dba_ts_quotas
WHERE  username = 'PERF_LAB';

PROMPT
PROMPT ================================================================================
PROMPT  PERF_LAB user and PERF_LAB_DATA tablespace created.
PROMPT  *** REMINDER: the password set above is a placeholder — CHANGE IT. ***
PROMPT  Next step: 02_create_tables.sql (run connected AS perf_lab).
PROMPT ================================================================================
PROMPT
