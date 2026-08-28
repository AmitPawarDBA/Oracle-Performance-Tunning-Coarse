-- =============================================================================
-- Day 5 — Architecture Bootcamp III: Process Architecture & Connections
-- reset.sql — full reset: clean up, then rebuild Day 5's objects fresh
--
-- Use this between class runs (or between practice sessions) to guarantee a
-- known-good starting state: no orphaned demo sessions, no leftover data
-- from a previous run's write-workload, and the demo objects freshly
-- rebuilt and ready to go.
--
-- Equivalent to running cleanup.sql followed by setup.sql, in one script.
--
-- NOTE: no live Oracle instance was available while writing this script.
-- Verify against a real 19c instance before class.
-- =============================================================================

PROMPT === Day 5 reset: step 1 of 2 — cleanup ===
@cleanup.sql

PROMPT === Day 5 reset: step 2 of 2 — rebuild ===
@setup.sql

-- -----------------------------------------------------------------------------
-- Final confirmation: lab is in a clean, re-runnable state.
-- -----------------------------------------------------------------------------
SELECT 'Orphaned demo/lab sessions' AS check_name,
       COUNT(*) AS found_count
FROM   v$session
WHERE  module IN ('DAY05_DEMO_SESSION', 'DAY05_LAB_SESSION')
UNION ALL
SELECT 'DAY05_WRITE_DEMO row count', COUNT(*)
FROM   PERF_LAB.DAY05_WRITE_DEMO
UNION ALL
SELECT 'DAY05_GENERATE_WRITE_LOAD compiled OK',
       COUNT(*)
FROM   dba_objects
WHERE  owner = 'PERF_LAB'
AND    object_name = 'DAY05_GENERATE_WRITE_LOAD'
AND    status = 'VALID';

-- Expected after a clean reset:
--   Orphaned demo/lab sessions            -> 0
--   DAY05_WRITE_DEMO row count            -> 0  (table exists, freshly empty)
--   DAY05_GENERATE_WRITE_LOAD compiled OK -> 1  (procedure exists and is VALID)

PROMPT Day 5 reset complete — lab is ready for the next run.
