-- =============================================================================
-- Day 1 — Welcome & The Hook: "The 45-Minute Mystery"
-- cleanup.sql — FULL teardown of Day 1's demo-specific objects
--
-- Run this only when decommissioning the Day 1 lab entirely (end of course,
-- environment rebuild, moving to a fresh PERF_LAB). This does NOT touch the
-- shared PERF_LAB tables (ORDERS/ORDER_ITEMS/PAYMENTS/etc.) beyond
-- guaranteeing their statistics/index state is left healthy for other days.
-- For a routine between-cohort refresh, use reset.sql instead — it keeps
-- these objects and just resets their state.
-- =============================================================================

SET SERVEROUTPUT ON
WHENEVER SQLERROR CONTINUE

-- 1. Any leftover scheduler jobs.
BEGIN
    FOR j IN (SELECT job_name FROM user_scheduler_jobs
              WHERE job_name LIKE 'DAY01_HOOK_JOB%') LOOP
        DBMS_SCHEDULER.DROP_JOB(job_name => j.job_name, force => TRUE);
    END LOOP;
END;
/

-- 2. Guarantee ORDER_ITEMS is left unlocked and accurately statted for
--    whichever day/schema-build step runs next.
BEGIN
    DBMS_STATS.UNLOCK_TABLE_STATS(ownname => USER, tabname => 'ORDER_ITEMS');
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

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
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

-- 3. Restore the PAYMENTS index visibility.
BEGIN
    sp_reset_invisible_index_problem;
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

-- 4. Drop Day 1's procedures.
DROP PROCEDURE sp_reset_invisible_index_problem;
DROP PROCEDURE sp_inject_invisible_index_problem;
DROP PROCEDURE sp_inject_stale_stats_problem;
DROP PROCEDURE sp_seed_recon_baseline_history;
DROP PROCEDURE sp_run_daily_reconciliation;

-- 5. Drop Day 1's tables.
DROP TABLE recon_results PURGE;
DROP TABLE recon_run_log PURGE;

-- 6. Drop the DBMS_STATS backup table.
BEGIN
    DBMS_STATS.DROP_STAT_TABLE(ownname => USER, stattab => 'RECON_STATS_BACKUP');
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

PROMPT Day 1 objects fully removed. PERF_LAB's shared tables are untouched
PROMPT except for ORDER_ITEMS statistics, which are left unlocked and fresh.
