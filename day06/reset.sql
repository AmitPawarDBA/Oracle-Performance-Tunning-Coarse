-- =============================================================================
-- Day 06 -- Architecture Bootcamp IV: How Oracle Executes a Statement
-- reset.sql -- INSTRUCTOR-RUN, full cross-cohort reset
--
-- Purpose: return the shared lab instance to a clean state so the NEXT
-- student or cohort gets a genuinely fresh hard-parse-then-soft-parse demo,
-- with no leftover cursors, stats, or session tags from a prior run.
--
-- Run connected as SYS/SYSTEM or another account with SYSDBA/ALTER SYSTEM
-- privileges. Do NOT run this mid-class while other students still need
-- their own cached cursors from earlier labs -- this is an instance-wide
-- operation. Best run between sessions/cohorts, not between steps of one
-- student's own demo (use cleanup.sql for that, session-scoped).
--
-- ENVIRONMENT DEPENDENT: flushing the shared pool on a busy shared training
-- instance briefly increases parsing load for every connected session as
-- their cursors get reloaded. Prefer running this when no demo is actively
-- mid-flight.
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200

PROMPT ================================================================
PROMPT Day 06 FULL RESET -- instance-wide. Confirm no other student/cohort
PROMPT is mid-demo before proceeding.
PROMPT ================================================================

-- 1. Flush the entire shared pool: clears every cursor from the library
--    cache instance-wide, including all Day 06 demo cursors and their
--    LOADS/PARSE_CALLS/EXECUTIONS history, plus PL/SQL and other cached
--    objects. This is the cleanest possible guarantee that the next run's
--    "cold run" (Step 2 of demo.sql) really is a fresh hard parse, even if
--    the unique-tag technique in demo.sql were somehow skipped.
ALTER SYSTEM FLUSH SHARED_POOL;

-- 2. Flush the buffer cache: clears cached data blocks instance-wide, so
--    the next cohort's "trace block access" step (demo.sql Step 6) starts
--    from a cold cache too, rather than reusing blocks a previous cohort
--    already warmed.
ALTER SYSTEM FLUSH BUFFER_CACHE;

-- 3. Confirm no lingering Day 06 demo cursors remain anywhere in the shared
--    pool (should return zero rows after the flush above).
COLUMN sql_id FORMAT A15
COLUMN sql_text FORMAT A60 WORD_WRAPPED
SELECT sql_id, sql_text
FROM   v$sqlarea
WHERE  sql_text LIKE '%DAY06\_%' ESCAPE '\';

PROMPT ================================================================
PROMPT Day 06 full reset complete: shared pool and buffer cache flushed.
PROMPT The environment is ready for the next student or cohort to run
PROMPT setup.sql -> demo.sql from a genuinely clean state.
PROMPT ================================================================
