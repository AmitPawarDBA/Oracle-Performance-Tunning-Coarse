-- =============================================================================
-- Day 1 — Welcome & The Hook: "The 45-Minute Mystery"
-- reset.sql — between-cohort reset: get the lab back to "ready to teach
-- Day 1 again" state. Keeps all Day 1 objects; resets their DATA/STATE only.
-- =============================================================================

SET SERVEROUTPUT ON
WHENEVER SQLERROR CONTINUE

-- 1. Drop any leftover live-demo scheduler job (job names carry a timestamp
--    suffix, so match by prefix).
BEGIN
    FOR j IN (SELECT job_name FROM user_scheduler_jobs
              WHERE job_name LIKE 'DAY01_HOOK_JOB%') LOOP
        DBMS_SCHEDULER.DROP_JOB(job_name => j.job_name, force => TRUE);
        DBMS_OUTPUT.PUT_LINE('Dropped leftover job: ' || j.job_name);
    END LOOP;
END;
/

-- 2. Guarantee ORDER_ITEMS stats are unlocked and accurate — belt-and-
--    suspenders in case the instructor jumped straight to reset without
--    running fix.sql first.
BEGIN
    DBMS_STATS.UNLOCK_TABLE_STATS(ownname => USER, tabname => 'ORDER_ITEMS');
EXCEPTION
    WHEN OTHERS THEN NULL;  -- already unlocked
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
END;
/

-- 3. Restore the PAYMENTS index used in the Hands-on Lab's second problem.
BEGIN
    sp_reset_invisible_index_problem;
END;
/

-- 4. Clear this cohort's run history and results.
TRUNCATE TABLE recon_results;
TRUNCATE TABLE recon_run_log;

-- 5. Re-seed a week of genuine baseline history for the next cohort.
BEGIN
    sp_seed_recon_baseline_history(p_days_back => 7);
END;
/

-- 6. Re-inject the stale-stats problem so the instructor can open with the
--    Hook again for the next cohort.
BEGIN
    sp_inject_stale_stats_problem;
END;
/

-- 7. Confirm clean state.
SELECT run_label, COUNT(*) AS run_count
FROM   recon_run_log
GROUP  BY run_label;

SELECT table_name, num_rows, blocks,
       CASE stattype_locked WHEN 'ALL' THEN 'LOCKED' ELSE 'unlocked' END AS lock_state
FROM   user_tab_statistics
WHERE  table_name = 'ORDER_ITEMS' AND object_type = 'TABLE';

PROMPT Day 1 lab reset complete — ready for the next cohort.
