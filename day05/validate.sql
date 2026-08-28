-- =============================================================================
-- Day 5 — Architecture Bootcamp III: Process Architecture & Connections
-- validate.sql — confirms the fix / confirms the architecture understanding
--
-- Two validation tracks:
--   (A) Real-World Scenario validation — the corrected tnsnames.ora now
--       connects immediately instead of hanging.
--   (B) Demo/lab understanding validation — clean observation of the
--       kill/PMON-cleanup behavior and the LGWR/DBWn write-workload
--       behavior, confirming the concepts actually held up under
--       observation, not just as claims.
--
-- NOTE: no live Oracle instance was available while writing this script.
-- Verify against a real 19c instance before class.
-- =============================================================================


-- =============================================================================
-- (A1) Client-side check, run on the APP SERVER after fixing tnsnames.ora
-- (Step 2 of fix.sql). Not SQL — a shell command:
--
--     tnsping perfpdb
--
-- Expected BEFORE the fix: the command would hang for an extended period
-- (mirroring the app's own symptom) before eventually timing out.
-- Expected AFTER the fix: an immediate, fast response, e.g.:
--
--   Used TNSNAMES adapter to resolve the alias
--   Attempting to contact (DESCRIPTION=(ADDRESS=(PROTOCOL=tcp)
--     (HOST=dbhost01.lab.local)(PORT=1521))(CONNECT_DATA=(SERVER=DEDICATED)
--     (SERVICE_NAME=perfpdb)))
--   OK (10 msec)
--
-- Response time is ENVIRONMENT DEPENDENT but should be milliseconds, not the
-- long hang from before the fix.
-- =============================================================================


-- =============================================================================
-- (A2) Confirm a fresh connection actually completes and shows up correctly
-- on the database side, connected as PERF_LAB from the app server after the
-- tnsnames.ora fix:
--
--     sqlplus perf_lab/<password>@perfpdb
-- =============================================================================
SELECT s.sid, s.serial#, s.username, s.server, s.status,
       s.machine, s.program,
       p.spid AS os_pid
FROM   v$session s
JOIN   v$process p ON p.addr = s.paddr
WHERE  s.username = 'PERF_LAB'
ORDER BY s.logon_time DESC
FETCH FIRST 5 ROWS ONLY;
-- Expect: the new session appears immediately with SERVER = 'DEDICATED' and
-- a fresh LOGON_TIME, and a real OS_PID.


-- =============================================================================
-- (B1) Validate the kill/PMON-cleanup demo left no orphaned session behind.
-- =============================================================================
SELECT sid, serial#, module
FROM   v$session
WHERE  module = 'DAY05_DEMO_SESSION';
-- Expect: no rows. If a row IS returned, the "killed" session either wasn't
-- actually killed, or cleanup hasn't completed yet — re-check before moving
-- on, and never assume a kill worked without confirming here.


-- =============================================================================
-- (B2) Validate PMON itself is still healthy and running (it should never
-- be affected by cleaning up a killed session — it's a permanent background
-- process, not a one-shot worker).
-- =============================================================================
SELECT b.pname, p.spid AS os_pid
FROM   v$bgprocess b
JOIN   v$process p ON p.addr = b.paddr
WHERE  b.pname = 'PMON';
-- Expect: exactly one row, with a valid OS PID.


-- =============================================================================
-- (B3) Validate the write-workload demo actually produced observable
-- LGWR/DBWn activity — re-derive the delta explicitly rather than eyeballing
-- two separate query outputs.
-- =============================================================================
WITH before_stats AS (
   SELECT name, value FROM v$sysstat
   WHERE name IN ('redo size', 'redo writes', 'physical writes', 'user commits')
)
SELECT 'Run this BEFORE the workload and again AFTER; compare VALUE for each NAME. '
       || 'All four should show a clear increase after PERF_LAB.DAY05_GENERATE_WRITE_LOAD '
       || 'runs. Exact magnitude is ENVIRONMENT DEPENDENT.' AS instructions
FROM   dual;

SELECT name, value
FROM   v$sysstat
WHERE  name IN ('redo size', 'redo writes', 'physical writes', 'user commits')
ORDER BY name;


-- =============================================================================
-- (B4) Validate the disposable table itself reflects the expected row count
-- from the demo's default parameters (10 batches x 500 rows = 5000 rows),
-- as an independent sanity check that the workload actually ran.
-- =============================================================================
SELECT COUNT(*) AS row_count,
       COUNT(DISTINCT batch_no) AS batch_count
FROM   PERF_LAB.DAY05_WRITE_DEMO;
-- Expect: row_count = 5000 and batch_count = 10 with the default call in
-- demo.sql's Step 7c. Adjust the expected numbers if the instructor changed
-- p_batches / p_rows_per_batch.
