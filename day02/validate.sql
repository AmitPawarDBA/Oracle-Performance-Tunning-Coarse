-- =============================================================================
-- Day 2 — Systematic Investigation: From Symptom to SQL
-- validate.sql — before/after proof the fix actually worked
--
-- "It feels faster" is not validation. Re-run the exact same chain used to
-- diagnose the problem and show the same evidence has changed for the
-- better — this closes the Measure -> Observe -> Hypothesize -> Prove ->
-- Change -> VALIDATE loop.
-- =============================================================================

SET TIMING ON

-- -----------------------------------------------------------------------------
-- Step 1: single-session timing, same call as the Baseline in demo.sql
-- -----------------------------------------------------------------------------
EXEC perf_lab.sp_csr_order_lookup_by_product(p_product_id => 4471);

SET TIMING OFF

SELECT sql_id, executions, buffer_gets, disk_reads,
       ROUND(elapsed_time/executions/1e3, 1) AS ms_per_exec
FROM   v$sql
WHERE  UPPER(sql_text) LIKE '%FROM ORDER_ITEMS OI%'
AND    UPPER(sql_text) LIKE '%JOIN ORDERS O%'
ORDER  BY last_active_time DESC
FETCH FIRST 5 ROWS ONLY;

-- COMPARE against the Step 1 baseline captured in demo.sql:
--   BEFORE: buffer_gets in the tens of thousands (full scan), ms_per_exec
--           in the low thousands (ENVIRONMENT DEPENDENT, but "seconds").
--   AFTER:  buffer_gets in the tens to low hundreds (indexed access),
--           ms_per_exec typically well under 100ms (ENVIRONMENT DEPENDENT,
--           but the order-of-magnitude drop is what to look for — not a
--           specific millisecond figure).


-- -----------------------------------------------------------------------------
-- Step 2: re-run the concurrency spike and confirm it no longer collapses
-- -----------------------------------------------------------------------------
EXEC perf_lab.sp_generate_csr_load_product(p_sessions => 25, p_duration_seconds => 90, p_product_id => 4471);

-- Wait a few seconds for the jobs to start, then re-check active session
-- count and wait class breakdown — same query as diagnose.sql Step A/C.
SELECT NVL(wait_class, 'ON CPU') AS wait_class, COUNT(*) AS session_count
FROM   v$session
WHERE  username = 'PERF_LAB'
AND    type     = 'USER'
AND    status   = 'ACTIVE'
GROUP  BY wait_class
ORDER  BY session_count DESC;

-- EXPECTED: with the index in place, the same 25-session spike either
-- resolves almost immediately (most sessions found not ACTIVE because each
-- execution completes fast) or shows a small residual CPU-bound population
-- instead of a large User I/O-bound population. The dramatic swing from
-- "mostly User I/O, dozens of active sessions for a sustained period" to
-- "brief CPU blips" is the validation signal — not a specific number.


-- -----------------------------------------------------------------------------
-- Step 3: confirm the plan change one more time, from the shared pool itself
-- -----------------------------------------------------------------------------
-- Reuse Chain Step D from diagnose.sql to find the current SQL_ID, then:
SELECT * FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(sql_id => '&sql_id', format => 'BASIC')
);
-- EXPECTED: INDEX RANGE SCAN on IX_ORDER_ITEMS_PRODUCT_ID, TABLE ACCESS BY
-- INDEX ROWID BATCHED on ORDER_ITEMS — no TABLE ACCESS FULL.


-- -----------------------------------------------------------------------------
-- Step 4: write down the before/after summary (fill in from your own run —
-- ENVIRONMENT DEPENDENT, values deliberately left as placeholders)
-- -----------------------------------------------------------------------------
-- | Metric                          | Before (full scan) | After (indexed) |
-- |----------------------------------|---------------------|------------------|
-- | Buffer gets per execution        | ~tens of thousands  | ~tens-hundreds   |
-- | Dominant wait event               | db file scattered   | none / minimal  |
-- |                                    | read / direct path  |                 |
-- |                                    | read                |                 |
-- | Active sessions during 25-user spike | dozens, sustained | brief, few      |
-- | Plan operation on ORDER_ITEMS     | TABLE ACCESS FULL   | INDEX RANGE SCAN|
--
-- Bring your actual captured numbers into the incident write-up — see
-- day02-content.md's Real-World Scenario "lesson learned" and the Homework.

PROMPT Validation complete. If all three checks above match expectations, proceed to reset.sql (or cleanup.sql if class continues).
