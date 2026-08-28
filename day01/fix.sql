-- =============================================================================
-- Day 1 — Welcome & The Hook: "The 45-Minute Mystery"
-- fix.sql — the corrective action, and why THIS fix and not an alternative
--
-- ROOT CAUSE (proven in diagnose.sql, Steps H-I): ORDER_ITEMS statistics
-- were locked at values understating the table by ~12x, so the optimizer's
-- cardinality estimate for the ORDER_ITEMS access path is wrong, and it
-- chooses a full scan over the far cheaper indexed nested-loop access.
--
-- WHY THIS FIX: unlock the statistics and gather accurate ones. This
-- repairs the actual defect the optimizer is reasoning from. It is the
-- only fix that also protects every OTHER query that touches ORDER_ITEMS
-- (not just today's reconciliation job) and that keeps working correctly
-- as the table continues to grow.
--
-- WHY NOT THE ALTERNATIVES (say this out loud in class — it's the point):
--   * A SQL hint (e.g. /*+ full(oi) */ or /*+ index(oi ...) */) or a SQL
--     Profile would force a specific plan for THIS statement only, while
--     leaving every other statement against ORDER_ITEMS still reasoning
--     from the same wrong numbers. It treats the symptom, not the cause.
--   * Flushing the whole shared pool would force a reparse but would NOT
--     fix the cardinality estimate — the new hard parse would compute the
--     exact same wrong plan from the same wrong (still locked) statistics.
--   * Adding a NEW index doesn't help — a perfectly good index into
--     ORDER_ITEMS already exists. The optimizer just doesn't trust it
--     because it doesn't trust the table's size.
--   * "Just let the nightly auto-stats job catch it eventually" doesn't
--     work here because the statistics are LOCKED — that's precisely what
--     let this drift silently for weeks in the real-world version of this
--     incident. Unlocking is not optional; it's part of the fix.
-- =============================================================================

SET SERVEROUTPUT ON

-- Show the "before" state one more time, for the room, right before fixing it.
SELECT table_name, num_rows, blocks,
       CASE stattype_locked WHEN 'ALL' THEN 'LOCKED' ELSE 'unlocked' END AS lock_state
FROM   user_tab_statistics
WHERE  table_name = 'ORDER_ITEMS' AND object_type = 'TABLE';

-- Step 1: unlock.
BEGIN
    DBMS_STATS.UNLOCK_TABLE_STATS(ownname => USER, tabname => 'ORDER_ITEMS');
    DBMS_OUTPUT.PUT_LINE('ORDER_ITEMS statistics unlocked.');
END;
/

-- Step 2: gather real, current statistics.
-- no_invalidate => FALSE forces IMMEDIATE invalidation of every cached
-- cursor that depends on ORDER_ITEMS' stats, so the very next execution of
-- the reconciliation job (validate.sql) is guaranteed to hard-parse against
-- the corrected numbers rather than waiting for Oracle's default rolling
-- invalidation window.
BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(
        ownname          => USER,
        tabname          => 'ORDER_ITEMS',
        estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
        method_opt       => 'FOR ALL COLUMNS SIZE AUTO',
        cascade          => TRUE,
        degree           => DBMS_STATS.AUTO_DEGREE,
        no_invalidate    => FALSE
    );
    DBMS_OUTPUT.PUT_LINE('ORDER_ITEMS statistics re-gathered (fresh, unlocked, cursors invalidated).');
END;
/

-- Show the "after" state.
SELECT table_name, num_rows, blocks, last_analyzed,
       CASE stattype_locked WHEN 'ALL' THEN 'LOCKED' ELSE 'unlocked' END AS lock_state
FROM   user_tab_statistics
WHERE  table_name = 'ORDER_ITEMS' AND object_type = 'TABLE';

SELECT COUNT(*) AS actual_row_count FROM order_items;

PROMPT ORDER_ITEMS statistics fixed. Continue with validate.sql to prove the
PROMPT plan and the job's timing actually recovered.
