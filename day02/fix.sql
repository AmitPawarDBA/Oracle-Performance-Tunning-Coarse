-- =============================================================================
-- Day 2 — Systematic Investigation: From Symptom to SQL
-- fix.sql — the corrective action, applied deliberately and separately
--
-- RATIONALE (must be stated BEFORE running any DDL — this is the point of
-- the whole day): diagnose.sql proved, with evidence from V$SESSION,
-- V$SQLAREA, V$SESSION_WAIT and V$ACTIVE_SESSION_HISTORY, that:
--   1. There is no locking/blocking involved (false lead #1, ruled out).
--   2. The dominant wait is real database User I/O, not network (false lead
--      #2, ruled out).
--   3. One SQL_ID — the product-lookup query — accounts for nearly all
--      active sessions and shows buffer_gets consistent with a full scan.
--   4. The wait event is db file scattered read / direct path read.
--   5. The plan confirms TABLE ACCESS FULL on ORDER_ITEMS, and Step 4 of
--      demo.sql confirmed Oracle has no alternative access path available
--      because PRODUCT_ID has no supporting index.
--
-- The fix that matches the proven root cause is therefore an index on
-- ORDER_ITEMS(PRODUCT_ID) — nothing more exotic, and nothing applied on
-- instinct. We are NOT bumping PGA/SGA, NOT adding parallelism, and NOT
-- killing sessions — none of those would address the actual root cause,
-- and the course explicitly teaches distrust of those reflexive "fixes."
-- =============================================================================

SET TIMING ON

-- -----------------------------------------------------------------------------
-- Step 1: create the index
-- -----------------------------------------------------------------------------
-- ONLINE so it does not block the (already struggling) concurrent readers
-- while it builds. Named to match this course's convention: ix_<table>_<col>.
CREATE INDEX ix_order_items_product_id
    ON order_items (product_id)
    ONLINE;

-- ENVIRONMENT DEPENDENT: build time depends entirely on host I/O throughput
-- and how much of ORDER_ITEMS is already cached. On a 20M-row table this can
-- range from under a minute to several minutes — do not assert a number here.

-- -----------------------------------------------------------------------------
-- Step 2: gather statistics on the new index
-- -----------------------------------------------------------------------------
-- A very common first-timer mistake: creating an index and assuming the CBO
-- will use it immediately. ONLINE index creation gathers statistics
-- automatically as of 12c+, but we do this explicitly and visibly here as
-- a teaching point — never assume, always verify (Step 3 does the verifying).
EXEC DBMS_STATS.GATHER_INDEX_STATS(ownname => 'PERF_LAB', indname => 'IX_ORDER_ITEMS_PRODUCT_ID');

-- -----------------------------------------------------------------------------
-- Step 3: verify the CBO will actually pick up the new access path
-- -----------------------------------------------------------------------------
EXPLAIN PLAN FOR
SELECT oi.order_id, oi.product_id, oi.quantity, oi.unit_price
FROM   order_items oi
WHERE  oi.product_id = 4471;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(FORMAT => 'BASIC +PREDICATE'));

-- EXPECTED: TABLE ACCESS BY INDEX ROWID BATCHED on ORDER_ITEMS, driven by
-- INDEX RANGE SCAN on IX_ORDER_ITEMS_PRODUCT_ID — no more TABLE ACCESS FULL.
-- If this still shows a full scan, do NOT proceed to validate.sql — check
-- for a stale cached cursor for the exact same SQL_ID (old plan still in the
-- shared pool) or a stats-gathering failure first.

PROMPT Fix applied: ix_order_items_product_id created and verified. Proceed to validate.sql.
