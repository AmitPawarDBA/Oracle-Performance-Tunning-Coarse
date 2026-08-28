-- =============================================================================
-- Day 5 — Architecture Bootcamp III: Process Architecture & Connections
-- demo.sql — exact live-demo command sequence
--
-- *** SAFETY NOTE — READ BEFORE RUNNING ANY KILL COMMAND IN THIS FILE ***
-- Only ever kill a session created specifically for this demo, and only after
-- re-confirming its MODULE tag ('DAY05_DEMO_SESSION') immediately beforehand.
-- NEVER run ALTER SYSTEM KILL SESSION, ALTER SYSTEM DISCONNECT SESSION, or an
-- OS-level `kill` against any session you did not personally start for this
-- exercise. In a real environment this is exactly how DBAs cause real
-- incidents. Step 6's OS-level kill -9 variant is INSTRUCTOR-ONLY.
--
-- This file has two logical "seats": SESSION A (instructor/DBA, runs
-- everything except where marked) and SESSION B (a second, separate
-- connection that plays the disposable demo session). Open two terminals.
--
-- NOTE: no live Oracle instance was available while writing this script.
-- Verify against a real 19c instance before class (ENVIRONMENT DEPENDENT
-- items are flagged inline).
-- =============================================================================


-- =============================================================================
-- STEP 1 — ORIENT (Session A)
-- =============================================================================
SELECT instance_name, host_name, version, status, database_status
FROM   v$instance;

SELECT banner FROM v$version WHERE banner LIKE 'Oracle Database%';

-- Confirm we're looking at a normal, healthy instance before doing anything else.


-- =============================================================================
-- STEP 2 — CREATE A DISPOSABLE DEDICATED-SERVER SESSION (Session B)
-- Run this block in a SEPARATE terminal/session, connected as PERF_LAB,
-- e.g.:  sqlplus perf_lab/<password>@perfpdb
-- =============================================================================
-- ---- SESSION B ----
BEGIN
   DBMS_APPLICATION_INFO.SET_MODULE(
      module_name => 'DAY05_DEMO_SESSION',
      action_name => 'disposable-kill-target'
   );
END;
/

-- Leave this session connected and idle. Do not close this terminal — the
-- instructor will identify and terminate this exact session from Session A.


-- =============================================================================
-- STEP 3 — IDENTIFY SESSION B (Session A)
-- =============================================================================
SELECT sid, serial#, username, server, status, program, machine, logon_time
FROM   v$session
WHERE  module = 'DAY05_DEMO_SESSION';

-- Confirm SERVER = 'DEDICATED' — this is a standard dedicated-server session,
-- exactly like the vast majority of connections most DBAs ever deal with.


-- =============================================================================
-- STEP 4 — MAP SESSION B TO ITS OS PROCESS (Session A)
-- =============================================================================
SELECT s.sid, s.serial#, s.username, s.server,
       p.spid       AS os_pid,
       p.program,
       p.pga_alloc_mem
FROM   v$session s
JOIN   v$process p ON p.addr = s.paddr
WHERE  s.module = 'DAY05_DEMO_SESSION';

-- Take note of OS_PID from the result above, then at the OS shell
-- (ENVIRONMENT DEPENDENT — exact ps columns/format vary by platform):
--
--   ps -ef | grep <os_pid>
--
-- On Linux you should see a process such as:
--   oracle    <os_pid>  1  0 10:14 ?  00:00:00 oracleORCLCDB (LOCAL=NO)
-- confirming this is a real, separate OS process dedicated to Session B.


-- =============================================================================
-- STEP 5 — KILL SESSION B SAFELY (Session A)
-- =============================================================================
-- *** Re-verify the target before killing anything ***
SELECT sid, serial#, module, program
FROM   v$session
WHERE  module = 'DAY05_DEMO_SESSION';

-- Replace <SID> and <SERIAL#> below with the exact values just confirmed above.
-- Do NOT run this against any SID/SERIAL# you have not personally verified.

ALTER SYSTEM KILL SESSION '<SID>,<SERIAL#>' IMMEDIATE;

-- Observe the transition:
SELECT sid, serial#, status
FROM   v$session
WHERE  module = 'DAY05_DEMO_SESSION';
-- Immediately after the ALTER SYSTEM command you may briefly see STATUS =
-- 'KILLED' before the row disappears entirely once cleanup finishes.


-- =============================================================================
-- STEP 6 — OBSERVE PMON'S CLEANUP (Session A)
-- =============================================================================
SELECT sid, serial#, status
FROM   v$session
WHERE  module = 'DAY05_DEMO_SESSION';
-- Expect: no rows. Session B's server process and its resources have been
-- released. PMON is the background process that just did this work.

-- Confirm PMON itself is alive and doing its normal job (it did not "use
-- itself up" cleaning this session — it's a permanent background process):
SELECT pname, description
FROM   v$bgprocess
WHERE  pname = 'PMON';

-- ---------------------------------------------------------------------------
-- OPTIONAL, INSTRUCTOR-ONLY VARIANT — hard OS-level kill to show the
-- crash-cleanup path instead of a graceful Oracle-initiated kill.
-- Requires OS shell access to the database host. DO NOT hand this step to
-- students to run against arbitrary PIDs.
-- ---------------------------------------------------------------------------
-- 1. In Session B's terminal, reconnect and re-tag a fresh disposable session
--    exactly as in Step 2.
-- 2. Repeat Steps 3-4 to get the new session's SID/SERIAL#/SPID.
-- 3. At the OS shell, as the instructor, terminate the OS process directly:
--        kill -9 <spid>
--    (ENVIRONMENT DEPENDENT — requires appropriate OS privileges on the DB host)
-- 4. Re-run the Step 6 query against v$session — the row still disappears,
--    but this time PMON detected a dead process rather than acting on an
--    explicit Oracle-level kill request. Point out to students: this is why
--    ALTER SYSTEM KILL SESSION (a clean, Oracle-aware request) is always
--    preferable to an OS-level kill -9 in a real environment — it avoids
--    forcing PMON into the harder, crash-style cleanup path unnecessarily.


-- =============================================================================
-- STEP 7 — GENERATE A WRITE-HEAVY WORKLOAD AND WATCH LGWR/DBWn (Session A)
-- =============================================================================

-- 7a. Baseline system stats before the workload.
SELECT name, value
FROM   v$sysstat
WHERE  name IN ('redo size', 'redo entries', 'redo writes',
                'physical writes', 'user commits', 'db block changes')
ORDER BY name;

-- 7b. Identify LGWR and every started DBWn right now, with their live OS PIDs.
SELECT b.pname, b.description, p.spid AS os_pid
FROM   v$bgprocess b
JOIN   v$process p ON p.addr = b.paddr
WHERE  b.pname LIKE 'LGWR%' OR b.pname LIKE 'DBW%'
ORDER BY b.pname;

-- Optional, ENVIRONMENT DEPENDENT: in a separate terminal, watch those PIDs
-- live while the workload runs, e.g.:
--   watch -n 1 'ps -o pid,pcpu,pmem,etime,cmd -p <lgwr_spid>,<dbw0_spid>'

-- 7c. Run the controlled write workload (defined in setup.sql).
EXEC PERF_LAB.DAY05_GENERATE_WRITE_LOAD(p_batches => 10, p_rows_per_batch => 500);

-- 7d. Stats again — compare against the 7a baseline. Redo-related figures
-- (redo size, redo entries, redo writes, user commits) should show a clear
-- jump because of LGWR's commit-driven flushing; physical writes will grow
-- as DBWn eventually writes dirtied buffers back (may lag slightly behind
-- the redo numbers, since DBWn is lazy/asynchronous by design).
SELECT name, value
FROM   v$sysstat
WHERE  name IN ('redo size', 'redo entries', 'redo writes',
                'physical writes', 'user commits', 'db block changes')
ORDER BY name;

-- Exact deltas are ENVIRONMENT DEPENDENT (CPU/storage speed, concurrent lab
-- load from other students). What matters pedagogically is the direction and
-- relative size of the change, not a specific absolute number.


-- =============================================================================
-- STEP 8 — RESET (Session A)
-- =============================================================================
-- See cleanup.sql for the full teardown. Quick inline check that nothing
-- disposable is left connected:
SELECT sid, serial#, module
FROM   v$session
WHERE  module IN ('DAY05_DEMO_SESSION', 'DAY05_LAB_SESSION');
-- Expect: no rows before moving on.
