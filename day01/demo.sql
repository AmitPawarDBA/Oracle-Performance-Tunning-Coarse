-- =============================================================================
-- Day 1 — Welcome & The Hook: "The 45-Minute Mystery"
-- demo.sql — the exact commands run LIVE during the Hook, in order
--
-- Prerequisite: setup.sql has already been run (baseline history seeded,
-- stale-stats problem injected) — normally the night before or the morning
-- of class, so the incident already "happened" the way the scenario
-- describes. This script reproduces today's run LIVE in front of the class.
--
-- Stage directions are marked >>> PAUSE <<< at the points where the
-- instructor talks, switches windows, or waits on the OraPub ASH
-- Visualization Tool (AVT) rather than typing the next command immediately.
-- See day01-content.md "Instructor Notes" for what to SAY at each pause.
-- =============================================================================

SET SERVEROUTPUT ON
SET LINESIZE 160
SET PAGESIZE 100
COLUMN run_label       FORMAT A10
COLUMN business_date   FORMAT A11
COLUMN event           FORMAT A32
COLUMN sql_text_snippet FORMAT A60


-- =============================================================================
-- STEP 1 (BASELINE, recap) — "Here's what this job normally looks like"
-- =============================================================================
-- This is real, measured history from setup.sql's baseline seeding — not
-- invented numbers. Every prior day should read as fast and consistent.
SELECT run_label, TO_CHAR(business_date,'YYYY-MM-DD') AS business_date,
       elapsed_seconds, order_count, plan_hash_value
FROM   recon_run_log
WHERE  run_label = 'BASELINE'
ORDER  BY business_date;

-- >>> PAUSE <<< "This reconciliation job has run every night for weeks.
-- Every single time, it looks like this — a few thousand orders, done in
-- well under a minute of DB time. This morning, finance emailed asking why
-- yesterday's numbers were three-quarters of an hour late. Let's find out,
-- live, using the same tool that broke this open the first time it
-- happened to me in production: OraPub's free ASH Visualization Tool."


-- =============================================================================
-- STEP 2 (OBSERVE) — Reproduce today's run live, in the background
-- =============================================================================
-- We kick this off as a one-off DBMS_SCHEDULER job so this SQL*Plus/SQLcl
-- session stays free to run diagnostics WHILE the job is actively running —
-- exactly what you'd do investigating a real in-flight incident.
-- ENVIRONMENT DEPENDENT: wall-clock duration depends entirely on host I/O
-- and CPU throughput; the point is the SHAPE of the wait profile, not a
-- specific number of minutes.
DECLARE
    v_job_name VARCHAR2(128) := 'DAY01_HOOK_JOB_' || TO_CHAR(SYSTIMESTAMP,'HH24MISSFF3');
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name   => v_job_name,
        job_type   => 'PLSQL_BLOCK',
        job_action => 'BEGIN sp_run_daily_reconciliation(TRUNC(SYSDATE), ''TODAY_LIVE''); END;',
        start_date => SYSTIMESTAMP,
        enabled    => TRUE,
        auto_drop  => TRUE);
    DBMS_OUTPUT.PUT_LINE('Launched today''s reconciliation run as job ' || v_job_name || '.');
END;
/

-- >>> PAUSE — open the OraPub ASH Visualization Tool now <<<
-- Point AVT at this instance, last 15 minutes, refresh every few seconds.
-- Show the pre-captured "clean run" screenshot side by side first (captured
-- once, ahead of time, from a BASELINE run — see Instructor Notes), then let
-- AVT's live chart start filling in for the run just launched above:
--   Clean run picture : a solid GREEN band (CPU) for ~1 minute, then done.
--   Today, live        : GREEN for a few seconds, then a widening RED band
--                        (wait event time) that keeps growing as we watch.
-- This is the moment the Hook is built around — say nothing for a few
-- seconds and let the class actually look at the picture.


-- =============================================================================
-- STEP 3 (OBSERVE, in SQL) — DB Time proxy: how busy is the instance RIGHT NOW
-- =============================================================================
-- We haven't taught AWR/ASH internals yet (that's Day 15) — today we only
-- need the idea that DB Time is "the total time the database spent doing
-- work for sessions," and that counting ACTIVE sessions right now is a
-- rough, honest proxy for how much of that time is being spent this second.
SELECT status, COUNT(*) AS session_count
FROM   v$session
WHERE  username = 'PERF_LAB'
AND    type     = 'USER'
GROUP  BY status;

-- Re-run this a few times over the next minute while narrating — the ACTIVE
-- count for our job's session stays pinned at 1 (it's a single-session
-- batch job, not a concurrency problem), but that one session stays ACTIVE
-- far longer than any baseline run ever did. That's the first hard evidence
-- something changed in HOW the work is being done, not HOW MUCH work exists.


-- =============================================================================
-- STEP 4 (INVESTIGATE) — Narrow the picture to one SQL_ID
-- =============================================================================
-- Full explanation and the false leads we rule out along the way live in
-- diagnose.sql — run that file's CHAIN STEPS A-J here, live, in order.
-- The short version, reproduced here so this script is runnable standalone:
SELECT sql_id, COUNT(*) AS ash_samples
FROM   v$active_session_history
WHERE  sample_time >= SYSTIMESTAMP - INTERVAL '15' MINUTE
AND    session_type  = 'FOREGROUND'
AND    sql_id IN (SELECT sql_id FROM v$sql WHERE sql_text LIKE '%DAY01_RECON_QUERY%')
GROUP  BY sql_id
ORDER  BY ash_samples DESC;

-- >>> PAUSE <<< "One SQL_ID. Every ASH sample for the last several minutes
-- points at the same statement — our reconciliation query. Let's see what
-- it's actually waiting on."

@@diagnose.sql


-- =============================================================================
-- STEP 5 (PROVE) — confirmed: root cause is stale, locked ORDER_ITEMS stats
-- =============================================================================
-- diagnose.sql's final steps show the smoking gun: a full scan of
-- ORDER_ITEMS whose ESTIMATED row count is ~12x smaller than its ACTUAL row
-- count, and USER_TAB_STATISTICS confirming ORDER_ITEMS is LOCKED at those
-- understated numbers. That is proof, not guesswork — the fix (fix.sql) is
-- applied only now that the cause is proven.


-- =============================================================================
-- STEP 6-8 — see fix.sql, validate.sql, reset.sql
-- =============================================================================
-- Deliberately kept in separate files: in a real incident you do not fix
-- and validate in the same breath you diagnosed in — you PROVE first, THEN
-- change, THEN validate the change actually worked. Run:
--   @fix.sql       -- unlock + re-gather ORDER_ITEMS statistics
--   @validate.sql  -- re-run the job, compare before/after
-- live, as the last two acts of the Hook.

PROMPT Day 1 live demo script complete through STEP 5 (PROVE).
PROMPT Continue with fix.sql, then validate.sql.
