-- =============================================================================
-- Day 2 — Systematic Investigation: From Symptom to SQL
-- demo.sql — exact commands run live, in order
--
-- Story: the "Order Lookup by Product" CSR screen used to be a quiet, rarely
-- used report. A recall notice on one product just went out and call volume
-- spiked — many CSRs are now running the same lookup at once, and the
-- helpdesk queue is filling up with "the system is frozen" tickets.
--
-- Run setup.sql once before this script. Each numbered step below is narrated
-- in day02-content.md's Practical Demo section (Baseline / Break It / Observe
-- / Investigate / Prove / Fix / Validate / Reset) — this file is just the SQL.
-- =============================================================================

-- =============================================================================
-- STEP 1 — BASELINE: what does the screen cost when only ONE person runs it?
-- =============================================================================
-- Run this from its own session/window and leave the session connected —
-- we will look it up again in a moment.
ALTER SESSION SET STATISTICS_LEVEL = ALL;

SET TIMING ON
SET AUTOTRACE OFF

EXEC perf_lab.sp_csr_order_lookup_by_product(p_product_id => 4471);

SET TIMING OFF

-- Grab the SQL_ID and baseline cost of the query that ran inside the
-- procedure, so we have a documented "before" number to compare against later.
-- (Match on a fragment of the SQL text rather than the whole thing, since
-- bind values differ run to run.)
SELECT sql_id, executions, buffer_gets, disk_reads,
       ROUND(elapsed_time/1e6, 2)      AS elapsed_sec,
       ROUND(elapsed_time/executions/1e3, 1) AS ms_per_exec
FROM   v$sql
WHERE  UPPER(sql_text) LIKE '%FROM ORDER_ITEMS OI%'
AND    UPPER(sql_text) LIKE '%JOIN ORDERS O%'
ORDER  BY last_active_time DESC
FETCH FIRST 5 ROWS ONLY;

-- ENVIRONMENT DEPENDENT: on this lab host, one execution against a 20M-row
-- ORDER_ITEMS table doing a full scan will typically run a few seconds —
-- annoying but tolerable for an occasional lookup. Record whatever your
-- environment actually shows; do not assume the number above.


-- =============================================================================
-- STEP 2 — BREAK IT: simulate the recall-notice spike (25 concurrent CSRs)
-- =============================================================================
-- Run this once. It launches 25 background sessions that will each hammer
-- the same product lookup for about 90 seconds — reproducing "everyone is
-- calling about the recalled product at the same time."
EXEC perf_lab.sp_generate_csr_load_product(p_sessions => 25, p_duration_seconds => 90, p_product_id => 4471);

-- Give the jobs a few seconds to actually start before observing.
-- (In class: talk through the business story while this settles.)


-- =============================================================================
-- STEP 3 — OBSERVE: is anything actually wrong right now?
-- =============================================================================
-- The single highest-value first query of any investigation: how many
-- sessions are ACTUALLY active (on CPU or waiting), not just connected?
SELECT COUNT(*) AS active_sessions
FROM   v$session
WHERE  status = 'ACTIVE'
AND    type   = 'USER';

-- Break that count down by wait class — CPU vs. specific wait types —
-- this is the Day 1 vocabulary recap in action.
SELECT NVL(wait_class, 'ON CPU') AS wait_class, COUNT(*) AS session_count
FROM   v$session
WHERE  status = 'ACTIVE'
AND    type   = 'USER'
GROUP BY wait_class
ORDER BY session_count DESC;

-- >>> From here on, the full chain lives in diagnose.sql <<<
-- (kept in a separate file because it's the reusable pattern students will
--  run against ANY future symptom, not just this one)

@@diagnose.sql


-- =============================================================================
-- STEP 4 — PROVE the hypothesis in isolation (safe, read-only, non-invasive)
-- =============================================================================
-- Hypothesis from diagnose.sql: the lookup does a full scan of ORDER_ITEMS
-- because PRODUCT_ID has no supporting index, and that full scan is cheap
-- enough at ONE concurrent execution but collapses under 25+ concurrent
-- executions competing for the same buffer cache / I/O.
--
-- Prove it cheaply: build a throwaway index in an isolated way is risky to
-- do live against a loaded table, so we instead prove the *access path* is
-- the culprit with a controlled comparison using an index hint against a
-- SMALL sample first, confirming the CBO's only alternative to a full scan
-- would in fact be an indexed access — before touching production DDL.
EXPLAIN PLAN FOR
SELECT /*+ INDEX(oi) */
       oi.order_id, oi.product_id, oi.quantity, oi.unit_price
FROM   order_items oi
WHERE  oi.product_id = 4471;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(FORMAT => 'BASIC +PREDICATE'));

-- Expected result at this point: Oracle IGNORES the hint and still shows
-- TABLE ACCESS FULL, because no index on PRODUCT_ID exists to use — which
-- is itself the proof. This is intentional: it demonstrates that the full
-- scan is not a bad optimizer choice, it is the ONLY choice available.


-- =============================================================================
-- STEP 5 — FIX: see fix.sql for the corrective action and its rationale
-- =============================================================================
-- @@fix.sql   (run separately and deliberately — never bundle a schema change
--              into the same script as the investigation)


-- =============================================================================
-- STEP 6 — VALIDATE: see validate.sql for the before/after proof
-- =============================================================================
-- @@validate.sql


-- =============================================================================
-- STEP 7 — RESET: see reset.sql to restore the lab for the next run
-- =============================================================================
-- @@reset.sql
