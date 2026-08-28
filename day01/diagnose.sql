-- =============================================================================
-- Day 1 — Welcome & The Hook: "The 45-Minute Mystery"
-- diagnose.sql — the reusable investigation chain
--
--   picture (AVT) -> active session count -> rule out false leads
--   -> SQL_ID -> wait event -> plan line -> proven cardinality misestimate
--
-- Views used are deliberately basic and Day-1-appropriate:
-- V$SESSION, V$SQL/V$SQLAREA, V$ACTIVE_SESSION_HISTORY, DBMS_XPLAN,
-- USER_TAB_STATISTICS. Full AWR/ASH architecture is Day 15's job — today
-- we use these views as tools, without teaching how ASH sampling itself
-- works internally.
--
-- This same chain (steps A-J) is what students reapply, unassisted, against
-- the second injected problem in the Hands-on Lab (see day01-content.md).
-- =============================================================================

SET LINESIZE 160
SET PAGESIZE 100


-- =============================================================================
-- CHAIN STEP A — Confirm the SQL_ID the picture pointed at
-- =============================================================================
SELECT sql_id, COUNT(*) AS ash_samples
FROM   v$active_session_history
WHERE  sample_time  >= SYSTIMESTAMP - INTERVAL '15' MINUTE
AND    session_type  = 'FOREGROUND'
AND    sql_id IN (SELECT sql_id FROM v$sql WHERE sql_text LIKE '%DAY01_RECON_QUERY%')
GROUP  BY sql_id
ORDER  BY ash_samples DESC;

-- RESULT: one SQL_ID, dozens of ASH samples over the last several minutes.
-- Note it down — every step below uses it. (SQL*Plus will prompt for
-- &sql_id below if run interactively; substitute the value directly if
-- running non-interactively.)


-- =============================================================================
-- CHAIN STEP B — FALSE LEAD #1: "it's probably just more data today"
-- =============================================================================
-- The most natural first guess for "a batch job that touches more rows took
-- longer" is more rows. Check it before assuming it — that is the whole
-- discipline this course exists to teach.
SELECT run_label, TO_CHAR(business_date,'YYYY-MM-DD') AS business_date, order_count
FROM   recon_run_log
WHERE  business_date >= TRUNC(SYSDATE) - 7
ORDER  BY business_date;

-- RESULT: today's order_count is in the same range as every BASELINE run —
-- no meaningful volume spike, no promotion, no batch backlog. FALSE LEAD #1
-- RULED OUT. Whatever is wrong, it is not "there is more work to do today."
-- (If order_count HAD spiked, the investigation would branch toward a
-- genuine capacity question instead of continuing below.)


-- =============================================================================
-- CHAIN STEP C — FALSE LEAD #2: "maybe something is blocking it"
-- =============================================================================
-- Second natural guess for "one session, stuck, taking forever": locking.
SELECT s.sid, s.serial#, s.blocking_session, s.event
FROM   v$session s
WHERE  s.username = 'PERF_LAB'
AND    s.type     = 'USER'
AND    s.sql_id IN (SELECT sql_id FROM v$sql WHERE sql_text LIKE '%DAY01_RECON_QUERY%')
AND    s.blocking_session IS NOT NULL;

-- RESULT: zero rows. Our session is not waiting on any other session's
-- lock — it's actively doing (a lot of) work, not stuck behind someone
-- else. FALSE LEAD #2 RULED OUT. This rules out Day 18's territory
-- (concurrency/locking) and confirms we're looking at a single session
-- burning real wait time on its own.


-- =============================================================================
-- CHAIN STEP D — What wait event dominates THIS session's time?
-- =============================================================================
SELECT s.sid, s.event, s.wait_class, s.seconds_in_wait
FROM   v$session s
WHERE  s.username = 'PERF_LAB'
AND    s.type     = 'USER'
AND    s.sql_id IN (SELECT sql_id FROM v$sql WHERE sql_text LIKE '%DAY01_RECON_QUERY%');

-- RESULT: 'db file scattered read' or 'direct path read' dominates —
-- User I/O, not CPU, not concurrency, not network. The textbook signature
-- of a large multiblock table scan.


-- =============================================================================
-- CHAIN STEP E — Cross-check with ASH: same story over the whole run?
-- =============================================================================
SELECT event, session_state, COUNT(*) AS samples
FROM   v$active_session_history
WHERE  sql_id IN (SELECT sql_id FROM v$sql WHERE sql_text LIKE '%DAY01_RECON_QUERY%')
AND    sample_time >= SYSTIMESTAMP - INTERVAL '15' MINUTE
GROUP  BY event, session_state
ORDER  BY samples DESC;

-- RESULT: the same wait event dominates the ASH sample history for the
-- entire run so far — this isn't a brief blip, it's the run's whole shape.
-- This is the RED BAND from the AVT picture, now confirmed in raw numbers.


-- =============================================================================
-- CHAIN STEP F — How expensive is this SQL_ID, in Oracle's own numbers?
-- =============================================================================
SELECT sql_id, executions, buffer_gets, disk_reads,
       ROUND(buffer_gets / GREATEST(executions,1)) AS gets_per_exec,
       ROUND(elapsed_time / GREATEST(executions,1) / 1e6, 1) AS sec_per_exec
FROM   v$sqlarea
WHERE  sql_id IN (SELECT sql_id FROM v$sql WHERE sql_text LIKE '%DAY01_RECON_QUERY%');

-- RESULT: buffer_gets is orders of magnitude higher than any BASELINE run
-- would need for a few thousand indexed lookups — consistent with reading
-- a large fraction of ORDER_ITEMS wholesale rather than probing it
-- selectively per order.


-- =============================================================================
-- CHAIN STEP G — Look at the plan: full scan or indexed access?
-- =============================================================================
SELECT * FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        sql_id => (SELECT sql_id FROM v$sql WHERE sql_text LIKE '%DAY01_RECON_QUERY%' AND ROWNUM = 1),
        format => 'BASIC +PARTITION'
    )
);

-- RESULT: TABLE ACCESS FULL on ORDER_ITEMS feeding a HASH JOIN, where every
-- BASELINE run's plan_hash_value (see recon_run_log) instead shows a
-- NESTED LOOPS driving off partition-pruned ORDERS into an INDEX RANGE SCAN
-- on ORDER_ITEMS. The plan itself changed. Now we need to know WHY.


-- =============================================================================
-- CHAIN STEP H — WHY did the plan flip? Estimated vs. Actual rows
-- =============================================================================
-- This is the step that turns "it's a full scan" into a PROVEN root cause
-- rather than a guess. ALLSTATS LAST needs actual execution statistics,
-- which the /*+ gather_plan_statistics */ hint in sp_run_daily_reconciliation
-- guarantees were collected for this run.
SELECT * FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        sql_id => (SELECT sql_id FROM v$sql WHERE sql_text LIKE '%DAY01_RECON_QUERY%' AND ROWNUM = 1),
        format => 'ALLSTATS LAST'
    )
);

-- RESULT: on the TABLE ACCESS FULL ORDER_ITEMS line, E-Rows (estimated) is
-- roughly 12x smaller than A-Rows (actual). The optimizer thinks
-- ORDER_ITEMS is a much smaller table than it really is — cheap enough to
-- just read the whole thing rather than do thousands of small indexed
-- lookups. That single ratio IS the root cause, in the optimizer's own
-- output.


-- =============================================================================
-- CHAIN STEP I — Confirm it in the statistics themselves
-- =============================================================================
SELECT table_name, num_rows, blocks, last_analyzed,
       CASE stattype_locked WHEN 'ALL' THEN 'LOCKED' ELSE 'unlocked' END AS lock_state
FROM   user_tab_statistics
WHERE  table_name  = 'ORDER_ITEMS'
AND    object_type = 'TABLE';

SELECT COUNT(*) AS actual_row_count FROM order_items;

-- RESULT: USER_TAB_STATISTICS.NUM_ROWS is far below the real COUNT(*), and
-- LOCK_STATE reads LOCKED. The optimizer isn't being irrational — it is
-- correctly computing a cost estimate from statistics that are simply
-- wrong, and locked so nothing has been able to correct them.
--
--   ROOT CAUSE (proven, not hypothesized): ORDER_ITEMS statistics were
--   frozen at values that understate the table by roughly 12x. Every plan
--   decision the optimizer makes for any query touching ORDER_ITEMS is
--   built on that wrong number until the stats are unlocked and refreshed.
--
-- This is tested against a corrective action in fix.sql, and the fix is
-- validated quantitatively — not "it feels faster" — in validate.sql.


-- =============================================================================
-- CHAIN STEP J — Same chain, applied independently (Hands-on Lab)
-- =============================================================================
-- After the instructor runs sp_inject_invisible_index_problem, students
-- re-run Steps A, D, E, F, G against the PAYMENTS side of the SAME query
-- (sql_text still matches '%DAY01_RECON_QUERY%' — it's still one statement,
-- now with two plan lines to examine instead of one). The wait event and
-- V$SQLAREA numbers will look structurally identical to today's demo; the
-- plan (Step G) and the missing-index check below are where the root cause
-- diverges from the instructor's:
--
--   SELECT index_name, visibility, status
--   FROM   user_indexes
--   WHERE  table_name = 'PAYMENTS';
--
-- Students should be able to state, unaided: "the plan line changed from
-- an indexed access to PAYMENTS to a full scan, and the index that used to
-- be used is INVISIBLE" — the same shape of proof as Step H/I above, a
-- different concrete defect.
