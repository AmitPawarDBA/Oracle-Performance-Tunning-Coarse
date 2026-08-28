-- =============================================================================
-- Day 1 — Welcome & The Hook: "The 45-Minute Mystery"
-- validate.sql — before/after proof that the fix actually worked
--
-- Never declare victory because "it feels faster." Re-run the exact same
-- job and compare it, quantitatively, against both today's broken run and
-- the BASELINE history — elapsed time, plan shape, and wait profile all
-- have to agree the problem is gone.
-- =============================================================================

SET SERVEROUTPUT ON
SET LINESIZE 160
COLUMN run_label     FORMAT A12
COLUMN business_date FORMAT A11
COLUMN event         FORMAT A32

-- Re-run the job now that statistics are corrected.
BEGIN
    sp_run_daily_reconciliation(TRUNC(SYSDATE), 'TODAY_FIXED');
END;
/

-- -----------------------------------------------------------------------------
-- Comparison 1: elapsed time and plan_hash_value, broken run vs. fixed run vs. baseline
-- -----------------------------------------------------------------------------
SELECT run_label, TO_CHAR(business_date,'YYYY-MM-DD') AS business_date,
       elapsed_seconds, order_count, plan_hash_value
FROM   recon_run_log
WHERE  business_date >= TRUNC(SYSDATE) - 7
ORDER  BY start_ts;

-- EXPECTED RESULT (ENVIRONMENT DEPENDENT for the exact seconds, not for the
-- shape): TODAY_FIXED's elapsed_seconds lands back in the same range as
-- every BASELINE row, and its plan_hash_value matches the BASELINE rows'
-- plan_hash_value — NOT the TODAY_LIVE row's. Same query, same data,
-- different (correct) plan, because the optimizer now trusts accurate
-- cardinality.


-- -----------------------------------------------------------------------------
-- Comparison 2: the plan itself
-- -----------------------------------------------------------------------------
SELECT * FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        sql_id => (SELECT sql_id FROM v$sql
                   WHERE sql_text LIKE '%DAY01_RECON_QUERY%'
                   AND   plan_hash_value = (SELECT plan_hash_value FROM recon_run_log
                                             WHERE run_label = 'TODAY_FIXED'
                                             ORDER BY log_id DESC FETCH FIRST 1 ROW ONLY)
                   AND   ROWNUM = 1),
        format => 'ALLSTATS LAST'
    )
);

-- EXPECTED RESULT: NESTED LOOPS driving off partition-pruned ORDERS into an
-- INDEX RANGE SCAN on ORDER_ITEMS — E-Rows and A-Rows now agree closely at
-- every plan line, because the optimizer's inputs are finally accurate.


-- -----------------------------------------------------------------------------
-- Comparison 3: wait profile for the fixed run
-- -----------------------------------------------------------------------------
SELECT NVL(session_state,'ON CPU') AS session_state, event, COUNT(*) AS samples
FROM   v$active_session_history
WHERE  sql_id IN (SELECT sql_id FROM v$sql WHERE sql_text LIKE '%DAY01_RECON_QUERY%')
AND    sample_time >= SYSTIMESTAMP - INTERVAL '5' MINUTE
GROUP  BY NVL(session_state,'ON CPU'), event
ORDER  BY samples DESC;

-- EXPECTED RESULT: the fixed run's ASH samples are overwhelmingly ON CPU,
-- not User I/O wait — the same GREEN-band shape every BASELINE run had in
-- the AVT picture. Point the class back at the AVT screen one more time:
-- pull the live chart forward past the TODAY_FIXED run and the red band
-- should stop growing and the chart should return to green.

PROMPT Validation complete: elapsed time, plan_hash_value, and wait profile
PROMPT for TODAY_FIXED all match BASELINE, not TODAY_LIVE. Root cause proven,
PROMPT fix proven. This IS the loop: Measure -> Observe -> Hypothesize ->
PROMPT Prove -> Change -> Validate.
