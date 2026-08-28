-- =============================================================================
-- Day 3 — Architecture Bootcamp I: Instance vs. Database, Memory at a Glance
-- demo.sql
--
-- Purpose : Exact live-demo query sequence for the Practical Demo section of
--           day03-content.md (Steps 1-5: Baseline/Orient, then the four view
--           walks). Step 6 ("what would happen if") lives in diagnose.sql;
--           Step 8 (Reset) lives in reset.sql.
--
-- Connect as : DBA-privileged account (e.g. SYSTEM) at the CDB root, per
--              setup.sql. Read-only throughout — nothing here modifies state.
--
-- ENVIRONMENT DEPENDENT: every byte/row-count value returned below depends on
-- this lab's actual hardware sizing (SGA_TARGET, memory allocated to the VM,
-- how long the instance has been up, how many students are connected). The
-- *shape* of the output (which views return what) is what matters, not the
-- exact numbers — call this out live whenever a number appears on screen.
-- =============================================================================

SET LINESIZE 150
SET PAGESIZE 100
COLUMN instance_name  FORMAT A15
COLUMN host_name      FORMAT A25
COLUMN db_name        FORMAT A12
COLUMN name            FORMAT A28
COLUMN pdb_name        FORMAT A15
COLUMN open_mode       FORMAT A12
COLUMN program          FORMAT A30
COLUMN spid              FORMAT A8
COLUMN description       FORMAT A55


-- =============================================================================
-- STEP 1 — Baseline / Orient: where am I, right now, before looking at anything
-- =============================================================================
PROMPT ================================================================
PROMPT STEP 1: Baseline / Orient
PROMPT ================================================================

SELECT SYS_CONTEXT('USERENV','CON_NAME')  AS current_container,
       SYS_CONTEXT('USERENV','CURRENT_USER') AS current_user,
       SYS_CONTEXT('USERENV','SESSION_USER') AS session_user
FROM   dual;


-- =============================================================================
-- STEP 2 — Walk V$INSTANCE: instance identity and state
-- =============================================================================
PROMPT ================================================================
PROMPT STEP 2: V$INSTANCE — the instance itself
PROMPT ================================================================

SELECT instance_name,
       host_name,
       version,
       startup_time,
       status,               -- STARTED / MOUNTED / OPEN
       database_status,
       instance_role,
       parallel
FROM   v$instance;

-- How long has this instance been up? (uptime, not a performance metric today
-- — just another instance-identity fact)
SELECT instance_name,
       startup_time,
       ROUND((SYSDATE - startup_time) * 24, 1) AS uptime_hours
FROM   v$instance;


-- =============================================================================
-- STEP 3 — Walk V$DATABASE and V$PDBS: the database and its containers
-- =============================================================================
PROMPT ================================================================
PROMPT STEP 3: V$DATABASE — the physical database (the CDB as a whole)
PROMPT ================================================================

SELECT name AS db_name,
       dbid,
       created,
       cdb,                  -- YES confirms multitenant architecture
       log_mode,             -- ARCHIVELOG / NOARCHIVELOG
       open_mode,
       database_role,
       platform_name
FROM   v$database;

PROMPT ================================================================
PROMPT STEP 3b: V$PDBS — every pluggable database container
PROMPT ================================================================

SELECT con_id,
       pdb_name,
       status,
       open_mode,
       restricted,
       open_time
FROM   v$pdbs
ORDER  BY con_id;

-- V$CONTAINERS additionally shows CDB$ROOT itself as CON_ID = 1
PROMPT ================================================================
PROMPT STEP 3c: V$CONTAINERS — the full container list, including CDB$ROOT
PROMPT ================================================================

SELECT con_id, name, open_mode
FROM   v$containers
ORDER  BY con_id;


-- =============================================================================
-- STEP 4 — Walk V$SGA and V$SGAINFO: what's in shared memory
-- =============================================================================
PROMPT ================================================================
PROMPT STEP 4: V$SGA — coarse SGA breakdown (four components)
PROMPT ================================================================

SELECT name, ROUND(value / 1024 / 1024, 2) AS size_mb
FROM   v$sga
ORDER  BY name;

PROMPT ================================================================
PROMPT STEP 4b: V$SGAINFO — fine-grained SGA component sizes
PROMPT ================================================================

SELECT name,
       ROUND(bytes / 1024 / 1024, 2) AS size_mb,
       resizeable
FROM   v$sgainfo
ORDER  BY name;

-- Instance-identifying and memory-related parameters, side by side
PROMPT ================================================================
PROMPT STEP 4c: V$PARAMETER — instance identity + memory sizing parameters
PROMPT ================================================================

SELECT name, value, display_value
FROM   v$parameter
WHERE  name IN ('instance_name','db_name','db_unique_name','service_names',
                'sga_target','sga_max_size','pga_aggregate_target')
ORDER  BY name;

-- PGA total, tracked entirely separately from V$SGA above — proof PGA is not
-- part of the SGA at all
PROMPT ================================================================
PROMPT STEP 4d: V$PGASTAT — PGA is a completely separate memory pool
PROMPT ================================================================

SELECT name, ROUND(value / 1024 / 1024, 2) AS value_mb
FROM   v$pgastat
WHERE  name IN ('total PGA allocated','total PGA used by SQL workareas',
                'total freeable PGA memory');


-- =============================================================================
-- STEP 5 — Walk V$PROCESS and V$BGPROCESS: background vs. foreground processes
-- =============================================================================
PROMPT ================================================================
PROMPT STEP 5: V$BGPROCESS — every background process slot this instance owns
PROMPT ================================================================

SELECT TRIM(bg.name) AS process_name,
       bg.description,
       CASE WHEN bg.paddr = '00' THEN 'NOT RUNNING' ELSE 'RUNNING' END AS status
FROM   v$bgprocess bg
WHERE  bg.paddr != '00'
ORDER  BY process_name;

PROMPT ================================================================
PROMPT STEP 5b: V$PROCESS joined to V$BGPROCESS — background processes, from
PROMPT           the OS-process side (shows the real OS PID for each one)
PROMPT ================================================================

SELECT TRIM(bg.name) AS process_name,
       p.pid,
       p.spid       AS os_pid,
       p.program
FROM   v$bgprocess bg
JOIN   v$process p ON p.addr = bg.paddr
ORDER  BY process_name;

PROMPT ================================================================
PROMPT STEP 5c: V$PROCESS filtered to foreground (server) processes only
PROMPT           — BACKGROUND IS NULL means "not a background process"
PROMPT ================================================================

SELECT p.pid,
       p.spid       AS os_pid,
       p.program,
       ROUND(p.pga_used_mem  / 1024, 1) AS pga_used_kb,
       ROUND(p.pga_alloc_mem / 1024, 1) AS pga_alloc_kb
FROM   v$process p
WHERE  p.background IS NULL
ORDER  BY p.pid;

-- Tie a foreground process back to the session/user it's serving
PROMPT ================================================================
PROMPT STEP 5d: Foreground processes joined to their sessions — who is each
PROMPT           server process actually working for?
PROMPT ================================================================

SELECT s.sid,
       s.serial#,
       s.username,
       s.program AS client_program,
       p.spid    AS server_os_pid
FROM   v$session s
JOIN   v$process p ON p.addr = s.paddr
WHERE  p.background IS NULL
  AND  s.username IS NOT NULL
ORDER  BY s.sid;

PROMPT
PROMPT ================================================================
PROMPT Demo complete. Proceed to diagnose.sql for the two live
PROMPT "what would happen if" architecture questions.
PROMPT ================================================================
