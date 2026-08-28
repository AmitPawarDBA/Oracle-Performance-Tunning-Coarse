-- =============================================================================
-- Day 3 — Architecture Bootcamp I: Instance vs. Database, Memory at a Glance
-- diagnose.sql
--
-- Purpose : The "what would happen if" investigative queries used live during
--           Practical Demo Step 6. These are architecture questions, not
--           performance questions — each one is designed to make a piece of
--           today's theory undeniable by showing it on screen rather than
--           just asserting it.
--
-- Connect as : DBA-privileged account (e.g. SYSTEM) at the CDB root.
--              Questions 1-2 below switch containers with
--              ALTER SESSION SET CONTAINER. If your account gets
--              ORA-01031: insufficient privileges on that command, either
--              connect AS SYSDBA instead, or run once as a privileged DBA:
--                GRANT SET CONTAINER TO SYSTEM CONTAINER=ALL;
--              PERF_LAB itself (a local user inside PERFPDB) cannot run this
--              script — local users cannot switch containers at all, which is
--              itself a small architecture fact worth mentioning if it comes up.
--
-- ENVIRONMENT DEPENDENT: exact byte counts, process counts, and uptime values
-- below depend on this lab's hardware and how many students are connected at
-- demo time. The conclusion each question proves does not depend on those
-- numbers — only the shape of the comparison does.
-- =============================================================================

SET LINESIZE 150
SET PAGESIZE 100
COLUMN name FORMAT A28


-- =============================================================================
-- QUESTION 1: "If I run the SAME V$SGA query from inside PERFPDB instead of
--              the CDB root, does the SGA total change?"
--
-- Prediction to ask the class for BEFORE running this: some students will
-- guess "yes, PERFPDB has its own smaller SGA." It doesn't — there is exactly
-- one SGA per instance, shared by every container.
-- =============================================================================
PROMPT ================================================================
PROMPT QUESTION 1: Does V$SGA change per container?
PROMPT ================================================================

PROMPT --- V$SGA queried from CDB$ROOT ---
SELECT SYS_CONTEXT('USERENV','CON_NAME') AS queried_from, name, ROUND(value/1024/1024,2) AS size_mb
FROM   v$sga
ORDER  BY name;

ALTER SESSION SET CONTAINER = PERFPDB;

PROMPT --- The SAME V$SGA query, now queried from inside PERFPDB ---
SELECT SYS_CONTEXT('USERENV','CON_NAME') AS queried_from, name, ROUND(value/1024/1024,2) AS size_mb
FROM   v$sga
ORDER  BY name;

-- Expected result: identical NAME/SIZE_MB rows in both queries.
-- Conclusion: the SGA is instance-wide, not per-container. There is one SGA
-- for the whole instance, shared by CDB$ROOT, PDB$SEED, and every PDB.


-- =============================================================================
-- QUESTION 2: "Do background processes exist per-PDB, or per-instance?"
-- (Still inside PERFPDB from Question 1 above.)
-- =============================================================================
PROMPT ================================================================
PROMPT QUESTION 2: Do background processes exist per-PDB?
PROMPT ================================================================

PROMPT --- V$BGPROCESS queried from inside PERFPDB ---
SELECT SYS_CONTEXT('USERENV','CON_NAME') AS queried_from,
       TRIM(name) AS process_name
FROM   v$bgprocess
WHERE  paddr != '00'
ORDER  BY process_name;

-- Compare this row set, by eye, against the CDB$ROOT V$BGPROCESS output from
-- demo.sql Step 5. Expected result: identical process list.
-- Conclusion: background processes belong to the instance, not to any one
-- container — PMON, SMON, DBWn, LGWR, etc. do not get "one per PDB."

-- Return to the root before continuing — good habit, and required for
-- Question 3 below (V$INSTANCE.STATUS is most naturally read from the root).
ALTER SESSION SET CONTAINER = CDB$ROOT;


-- =============================================================================
-- QUESTION 3: "What does 'the instance is up but the database isn't open yet'
--              actually look like?" (NOMOUNT / MOUNT states)
--
-- This step is narrated by the instructor rather than executed against the
-- shared PERF_LAB instance (Day 4 onward depends on it staying OPEN). If a
-- spare, disposable sandbox instance is available, this is the single most
-- convincing live moment in the whole session — see Instructor Notes in
-- day03-content.md. The queries below show WHAT you would see at each state;
-- run them for real only against a throwaway instance, never against the
-- shared lab instance.
-- =============================================================================
PROMPT ================================================================
PROMPT QUESTION 3 (narrated, or run only against a throwaway instance):
PROMPT   What does NOMOUNT / MOUNT actually look like from V$INSTANCE
PROMPT   and V$DATABASE?
PROMPT ================================================================

-- On a throwaway sandbox instance only:
--   SHUTDOWN IMMEDIATE;
--   STARTUP NOMOUNT;
--   SELECT status, database_status FROM v$instance;      -- STATUS = STARTED
--   SELECT * FROM v$database;                              -- returns NO ROWS
--   ALTER DATABASE MOUNT;
--   SELECT status, database_status FROM v$instance;      -- STATUS = MOUNTED
--   SELECT name, open_mode FROM v$database;                -- one row, MOUNTED
--   ALTER DATABASE OPEN;
--   SELECT status, database_status FROM v$instance;      -- STATUS = OPEN

-- On the current (shared) instance, we can at least confirm the state we're
-- actually in right now:
SELECT status, database_status FROM v$instance;
SELECT name, open_mode FROM v$database;

-- Conclusion: STATUS = OPEN and OPEN_MODE = READ WRITE together confirm this
-- instance has already progressed through NOMOUNT and MOUNT to reach where we
-- find it today — those earlier states are real, just rarely observed live.


-- =============================================================================
-- QUESTION 4: "Does the number of foreground processes scale with the number
--              of connections, while the number of background processes
--              stays fixed?"
-- =============================================================================
PROMPT ================================================================
PROMPT QUESTION 4: Foreground process count vs. background process count
PROMPT ================================================================

SELECT
    (SELECT COUNT(*) FROM v$bgprocess WHERE paddr != '00')  AS background_process_count,
    (SELECT COUNT(*) FROM v$process   WHERE background IS NULL) AS foreground_process_count
FROM dual;

-- Live variant for the instructor to run: open one or two extra SQL*Plus/SQLcl
-- connections in separate terminals while this query stays on screen, and
-- re-run it after each new connection. Expected result:
--   background_process_count : constant, does not change
--   foreground_process_count : increases by exactly one per new connection
-- Conclusion: background processes are a fixed roster tied to the instance;
-- foreground/server processes scale with client connections. This is the
-- concept Day 5 builds its full process deep-dive on top of.

PROMPT
PROMPT ================================================================
PROMPT diagnose.sql complete. Proceed to fix.sql to see the "SGA size is
PROMPT NOT database size" misconception disproved with real numbers.
PROMPT ================================================================
