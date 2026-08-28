-- =============================================================================
-- Day 1 — Welcome & The Hook: "The 45-Minute Mystery"
-- setup.sql
--
-- Assumes the PERF_LAB schema already exists (CUSTOMERS, PRODUCTS, ORDERS,
-- ORDER_ITEMS, PAYMENTS, TRANSACTIONS, EMPLOYEES, DEPARTMENTS, SALES,
-- LOG_EVENTS) at Standard tier, built by setup/01-06 at the repo root, with
-- current, unlocked statistics already gathered. This script adds ONLY what
-- Day 1 needs on top of that schema:
--
--   1. RECON_RUN_LOG / RECON_RESULTS  — a small logging schema standing in
--      for the real batch reconciliation job's own audit trail.
--   2. SP_RUN_DAILY_RECONCILIATION    — the batch job itself: for one
--      business date, join ORDERS -> ORDER_ITEMS -> PAYMENTS and reconcile
--      order totals against completed payments, logging elapsed time and
--      the plan hash actually used.
--   3. SP_SEED_RECON_BASELINE_HISTORY — runs several prior days' worth of
--      the job to build genuine (not fabricated) "every prior run was fast"
--      history in RECON_RUN_LOG.
--   4. SP_INJECT_STALE_STATS_PROBLEM  — the Hook's injected root cause: it
--      backs up ORDER_ITEMS' real statistics, replaces them with statistics
--      that understate the table by ~12x, and LOCKS them — reproducing a
--      table whose stats were accurate long ago and then frozen by a
--      forgotten DBMS_STATS.LOCK_TABLE_STATS, silently drifting stale as
--      the table grew through normal operation.
--   5. SP_INJECT_INVISIBLE_INDEX_PROBLEM / SP_RESET_INVISIBLE_INDEX_PROBLEM
--      — a second, structurally different but symptom-similar problem
--      (PAYMENTS' ORDER_ID index made INVISIBLE) used for the Hands-on Lab,
--      so students investigate a genuinely new problem, not a rerun of the
--      instructor's demo. The index is located dynamically by column, not
--      by a hardcoded name, since PERF_LAB's exact index names are set by
--      the parallel schema build.
--
-- This script deliberately performs BASELINE (seed history) and BREAK IT
-- (inject the stale-stats problem) as environment prep — run this once,
-- before class, so the incident already "happened this morning" the way
-- the Real-World Scenario describes. demo.sql then reproduces today's run
-- LIVE, in front of the class, while V$ACTIVE_SESSION_HISTORY and the
-- OraPub ASH Visualization Tool watch it happen.
--
-- Run connected as PERF_LAB (or a DBA account with
-- ALTER SESSION SET CURRENT_SCHEMA = PERF_LAB already issued).
--
-- Requires (same privilege set Day 2 already needs, plus DBMS_STATS write
-- access on your own schema's objects, which schema owners have by
-- default):
--   GRANT CREATE JOB TO perf_lab;              -- for DBMS_SCHEDULER (demo.sql)
--   GRANT SELECT ON v_$sql TO perf_lab;          -- to capture plan_hash_value
--   (or SELECT_CATALOG_ROLE / SELECT ANY DICTIONARY, whichever your site's
--    security policy grants to lab accounts)
-- =============================================================================

SET SERVEROUTPUT ON
WHENEVER SQLERROR CONTINUE

-- -----------------------------------------------------------------------------
-- 1. Logging tables
-- -----------------------------------------------------------------------------
BEGIN
    EXECUTE IMMEDIATE q'[
        CREATE TABLE recon_run_log (
            log_id           NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            run_label        VARCHAR2(30)   NOT NULL,
            business_date    DATE           NOT NULL,
            start_ts         TIMESTAMP,
            end_ts           TIMESTAMP,
            elapsed_seconds  NUMBER,
            order_count      NUMBER,
            variance_count   NUMBER,
            plan_hash_value  NUMBER,
            notes            VARCHAR2(200)
        )
    ]';
    DBMS_OUTPUT.PUT_LINE('Created RECON_RUN_LOG.');
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -955 THEN RAISE; END IF;   -- -955 = name already used
        DBMS_OUTPUT.PUT_LINE('RECON_RUN_LOG already exists — skipped.');
END;
/

BEGIN
    EXECUTE IMMEDIATE q'[
        CREATE TABLE recon_results (
            business_date    DATE,
            order_id         NUMBER,
            order_total      NUMBER(12,2),
            items_total      NUMBER(12,2),
            payments_total   NUMBER(12,2),
            variance_amount  NUMBER(12,2)
        )
    ]';
    EXECUTE IMMEDIATE
        'CREATE INDEX ix_recon_results_bdate ON recon_results(business_date)';
    DBMS_OUTPUT.PUT_LINE('Created RECON_RESULTS.');
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -955 THEN RAISE; END IF;
        DBMS_OUTPUT.PUT_LINE('RECON_RESULTS already exists — skipped.');
END;
/

-- -----------------------------------------------------------------------------
-- 2. The batch job itself: SP_RUN_DAILY_RECONCILIATION
-- -----------------------------------------------------------------------------
-- Shape of the query matters: ORDERS is filtered/pruned to one business date
-- first (a small driving row source — normally a few thousand rows, thanks
-- to range partitioning on ORDER_DATE), then joined to ORDER_ITEMS by
-- ORDER_ID. Under correct statistics this is exactly the shape a
-- NESTED LOOPS / INDEX RANGE SCAN plan wants: small driver, indexed probe
-- into the big table, once per order. That is the whole point of the demo:
-- the query never changes — only whether the optimizer trusts a cheap,
-- targeted plan or falls back to reading all of ORDER_ITEMS.
--
-- The /*+ gather_plan_statistics */ hint guarantees DBMS_XPLAN.DISPLAY_CURSOR
-- with 'ALLSTATS LAST' shows real actual-row counts (A-Rows) later in
-- diagnose.sql regardless of the instance's STATISTICS_LEVEL setting — this
-- is what lets the class SEE the cardinality misestimate, not just infer it.
-- The trailing DAY01_RECON_QUERY comment is a stable marker so diagnose.sql
-- can find this exact statement in V$SQL without guessing at SQL text.
CREATE OR REPLACE PROCEDURE sp_run_daily_reconciliation (
    p_business_date IN DATE,
    p_run_label     IN VARCHAR2 DEFAULT 'RUN'
) AUTHID DEFINER
IS
    v_start     TIMESTAMP := SYSTIMESTAMP;
    v_end       TIMESTAMP;
    v_orders    PLS_INTEGER;
    v_variance  PLS_INTEGER;
    v_plan_hash NUMBER;
BEGIN
    DELETE FROM recon_results WHERE business_date = p_business_date;

    INSERT INTO recon_results
        (business_date, order_id, order_total, items_total, payments_total, variance_amount)
    SELECT /*+ gather_plan_statistics */ -- DAY01_RECON_QUERY
           p_business_date,
           o.order_id,
           o.order_total,
           SUM(oi.line_total)                              AS items_total,
           NVL(MAX(pm.payments_total), 0)                   AS payments_total,
           o.order_total - NVL(MAX(pm.payments_total), 0)   AS variance_amount
    FROM   orders o
           JOIN order_items oi
             ON oi.order_id = o.order_id
           LEFT JOIN (SELECT p.order_id, SUM(p.amount) AS payments_total
                      FROM   payments p
                      WHERE  p.payment_status = 'COMPLETED'
                      GROUP BY p.order_id) pm
             ON pm.order_id = o.order_id
    WHERE  o.order_date >= p_business_date
    AND    o.order_date <  p_business_date + 1
    GROUP  BY o.order_id, o.order_total;

    v_orders := SQL%ROWCOUNT;
    COMMIT;

    SELECT COUNT(*) INTO v_variance
    FROM   recon_results
    WHERE  business_date = p_business_date
    AND    ABS(NVL(variance_amount, 0)) > 0.01;

    BEGIN
        SELECT plan_hash_value INTO v_plan_hash
        FROM   (SELECT plan_hash_value
                FROM   v$sql
                WHERE  sql_text LIKE '%DAY01_RECON_QUERY%'
                AND    parsing_schema_name = USER
                ORDER  BY last_active_time DESC)
        WHERE  ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN v_plan_hash := NULL;
    END;

    v_end := SYSTIMESTAMP;

    INSERT INTO recon_run_log
        (run_label, business_date, start_ts, end_ts, elapsed_seconds,
         order_count, variance_count, plan_hash_value)
    VALUES (p_run_label, p_business_date, v_start, v_end,
            ROUND(EXTRACT(SECOND FROM (v_end - v_start)) +
                  EXTRACT(MINUTE FROM (v_end - v_start)) * 60 +
                  EXTRACT(HOUR   FROM (v_end - v_start)) * 3600, 1),
            v_orders, v_variance, v_plan_hash);
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('sp_run_daily_reconciliation[' || p_run_label || ']: business_date=' ||
        TO_CHAR(p_business_date,'YYYY-MM-DD') || ', orders=' || v_orders ||
        ', variances=' || v_variance || ', plan_hash=' || NVL(TO_CHAR(v_plan_hash),'?'));
END sp_run_daily_reconciliation;
/
SHOW ERRORS PROCEDURE sp_run_daily_reconciliation

-- -----------------------------------------------------------------------------
-- 3. Baseline history builder
-- -----------------------------------------------------------------------------
-- Runs the REAL job for each of the last N business days so RECON_RUN_LOG
-- holds genuine measured timings, not invented ones. Each day's run touches
-- only that day's (partition-pruned) slice of ORDERS/ORDER_ITEMS, so this is
-- cheap relative to a full-table operation — ENVIRONMENT DEPENDENT exactly
-- how many seconds each historical run takes, but it should be consistently
-- fast on any reasonably provisioned Standard-tier lab host.
CREATE OR REPLACE PROCEDURE sp_seed_recon_baseline_history (
    p_days_back IN PLS_INTEGER DEFAULT 7
) AUTHID DEFINER
IS
BEGIN
    FOR i IN 1 .. p_days_back LOOP
        sp_run_daily_reconciliation(
            p_business_date => TRUNC(SYSDATE) - i,
            p_run_label     => 'BASELINE'
        );
    END LOOP;
END sp_seed_recon_baseline_history;
/
SHOW ERRORS PROCEDURE sp_seed_recon_baseline_history

-- -----------------------------------------------------------------------------
-- 4. THE INJECTED PROBLEM — stale, locked statistics on ORDER_ITEMS
-- -----------------------------------------------------------------------------
-- Backs up ORDER_ITEMS' real (current, accurate) statistics via
-- DBMS_STATS.EXPORT_TABLE_STATS, then overwrites them with statistics that
-- understate the table's real size by roughly 12x, and locks them so no
-- auto-stats job can silently "fix" the demo before class. This reproduces,
-- deterministically and safely (only metadata changes — no data is touched),
-- the real-world failure mode of "stats were accurate months ago, someone
-- locked them for an unrelated reason, and organic growth since then made
-- them badly wrong without anyone noticing."
CREATE OR REPLACE PROCEDURE sp_inject_stale_stats_problem AUTHID DEFINER
IS
    v_real_numrows NUMBER;
    v_real_blocks  NUMBER;
    v_real_avgrlen NUMBER;
    v_fake_numrows NUMBER;
    v_fake_blocks  NUMBER;
BEGIN
    BEGIN
        DBMS_STATS.DROP_STAT_TABLE(ownname => USER, stattab => 'RECON_STATS_BACKUP');
    EXCEPTION
        WHEN OTHERS THEN NULL;  -- backup table doesn't exist yet on first run
    END;
    DBMS_STATS.CREATE_STAT_TABLE(ownname => USER, stattab => 'RECON_STATS_BACKUP');
    DBMS_STATS.EXPORT_TABLE_STATS(
        ownname => USER, tabname => 'ORDER_ITEMS',
        stattab => 'RECON_STATS_BACKUP', statid => 'PRE_DAY01_DEMO');

    SELECT num_rows, blocks, avg_row_len
      INTO v_real_numrows, v_real_blocks, v_real_avgrlen
      FROM user_tables
     WHERE table_name = 'ORDER_ITEMS';

    IF v_real_numrows IS NULL THEN
        RAISE_APPLICATION_ERROR(-20001,
            'ORDER_ITEMS has no statistics yet. Gather real stats first ' ||
            '(setup/05_create_statistics.sql) before running the Day 1 demo.');
    END IF;

    v_fake_numrows := ROUND(v_real_numrows / 12);
    v_fake_blocks  := ROUND(v_real_blocks  / 12);

    DBMS_STATS.SET_TABLE_STATS(
        ownname       => USER,
        tabname       => 'ORDER_ITEMS',
        numrows       => v_fake_numrows,
        numblks       => v_fake_blocks,
        avgrlen       => v_real_avgrlen,
        no_invalidate => FALSE,
        force         => TRUE);

    DBMS_STATS.LOCK_TABLE_STATS(ownname => USER, tabname => 'ORDER_ITEMS');

    DBMS_OUTPUT.PUT_LINE('sp_inject_stale_stats_problem: ORDER_ITEMS real stats backed up ' ||
        'to RECON_STATS_BACKUP (statid=PRE_DAY01_DEMO).');
    DBMS_OUTPUT.PUT_LINE('  Real stats : num_rows=' || v_real_numrows || ', blocks=' || v_real_blocks);
    DBMS_OUTPUT.PUT_LINE('  Injected   : num_rows=' || v_fake_numrows || ', blocks=' || v_fake_blocks ||
        '  (LOCKED — auto-stats will not touch this table)');
END sp_inject_stale_stats_problem;
/
SHOW ERRORS PROCEDURE sp_inject_stale_stats_problem

-- -----------------------------------------------------------------------------
-- 5. Second, independent problem for the Hands-on Lab — invisible index
-- -----------------------------------------------------------------------------
-- Makes the leading index on PAYMENTS(ORDER_ID) invisible to the optimizer,
-- flipping the reconciliation job's join to PAYMENTS from an indexed lookup
-- to a full scan of a 5,000,000-row table. Same SYMPTOM FAMILY as the
-- instructor's demo (a join that used to be cheap is now a full scan,
-- DB Time and wait time balloon) but a DIFFERENT ROOT CAUSE (an invisible
-- index, not stale/locked statistics) — students must run the same
-- investigative loop, not remember the instructor's answer. The index is
-- located dynamically by column so this works regardless of the exact name
-- the parallel PERF_LAB schema build gave it.
CREATE OR REPLACE PROCEDURE sp_inject_invisible_index_problem AUTHID DEFINER
IS
    v_index_name VARCHAR2(128);
BEGIN
    SELECT ic.index_name INTO v_index_name
    FROM   user_ind_columns ic
           JOIN user_indexes ui ON ui.index_name = ic.index_name
    WHERE  ic.table_name      = 'PAYMENTS'
    AND    ic.column_name     = 'ORDER_ID'
    AND    ic.column_position = 1
    AND    ROWNUM = 1;

    EXECUTE IMMEDIATE 'ALTER INDEX ' || v_index_name || ' INVISIBLE';
    DBMS_OUTPUT.PUT_LINE('sp_inject_invisible_index_problem: index ' || v_index_name ||
        ' on PAYMENTS(ORDER_ID) is now INVISIBLE.');
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('sp_inject_invisible_index_problem: no leading index on ' ||
            'PAYMENTS(ORDER_ID) found — check the PERF_LAB schema build before class.');
END sp_inject_invisible_index_problem;
/
SHOW ERRORS PROCEDURE sp_inject_invisible_index_problem

CREATE OR REPLACE PROCEDURE sp_reset_invisible_index_problem AUTHID DEFINER
IS
    v_index_name VARCHAR2(128);
BEGIN
    SELECT ic.index_name INTO v_index_name
    FROM   user_ind_columns ic
           JOIN user_indexes ui ON ui.index_name = ic.index_name
    WHERE  ic.table_name      = 'PAYMENTS'
    AND    ic.column_name     = 'ORDER_ID'
    AND    ic.column_position = 1
    AND    ROWNUM = 1;

    EXECUTE IMMEDIATE 'ALTER INDEX ' || v_index_name || ' VISIBLE';
    DBMS_OUTPUT.PUT_LINE('sp_reset_invisible_index_problem: index ' || v_index_name ||
        ' on PAYMENTS(ORDER_ID) is now VISIBLE again.');
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('sp_reset_invisible_index_problem: no leading index on ' ||
            'PAYMENTS(ORDER_ID) found — nothing to reset.');
END sp_reset_invisible_index_problem;
/
SHOW ERRORS PROCEDURE sp_reset_invisible_index_problem

-- -----------------------------------------------------------------------------
-- 6. Prepare the environment: seed baseline history, then break it
-- -----------------------------------------------------------------------------
-- This is what makes the incident already "have happened this morning" by
-- the time class starts. Run this script once before each cohort (reset.sql
-- re-runs the equivalent at the end of class to prep the NEXT cohort).
BEGIN
    sp_seed_recon_baseline_history(p_days_back => 7);
END;
/

BEGIN
    sp_inject_stale_stats_problem;
END;
/

-- Note: sp_inject_invisible_index_problem is NOT run here — the instructor
-- triggers it live, right before releasing students into the Hands-on Lab
-- (see day01-content.md, Hands-on Lab section, and demo.sql's closing step).

-- -----------------------------------------------------------------------------
-- 7. Verification
-- -----------------------------------------------------------------------------
SELECT object_name, object_type, status
FROM   user_objects
WHERE  object_name IN (
         'SP_RUN_DAILY_RECONCILIATION', 'SP_SEED_RECON_BASELINE_HISTORY',
         'SP_INJECT_STALE_STATS_PROBLEM', 'SP_INJECT_INVISIBLE_INDEX_PROBLEM',
         'SP_RESET_INVISIBLE_INDEX_PROBLEM', 'RECON_RUN_LOG', 'RECON_RESULTS')
ORDER BY object_type, object_name;

SELECT run_label, business_date, elapsed_seconds, order_count, plan_hash_value
FROM   recon_run_log
ORDER  BY business_date;

SELECT table_name, num_rows, blocks,
       CASE stattype_locked WHEN 'ALL' THEN 'LOCKED' ELSE NVL(stattype_locked,'unlocked') END AS lock_state
FROM   user_tab_statistics
WHERE  table_name = 'ORDER_ITEMS'
AND    object_type = 'TABLE';

PROMPT Day 1 setup complete. ORDER_ITEMS statistics are injected and LOCKED —
PROMPT the environment is ready for the live demo in demo.sql.
