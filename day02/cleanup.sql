-- =============================================================================
-- Day 2 — Systematic Investigation: From Symptom to SQL
-- cleanup.sql — safety net: stop any lingering load-generator activity
--
-- Use this any time during class if the demo or lab needs to be interrupted
-- (e.g. running long, or a student's load generator got away from them) —
-- it does NOT undo the fix or drop any Day 2 objects. For a full reset back
-- to a re-runnable pristine state, use reset.sql instead.
-- =============================================================================

SET SERVEROUTPUT ON

-- -----------------------------------------------------------------------------
-- Stop and remove any still-running CSR load-generator jobs
-- -----------------------------------------------------------------------------
DECLARE
    v_stopped PLS_INTEGER := 0;
BEGIN
    FOR j IN (
        SELECT job_name
        FROM   user_scheduler_jobs
        WHERE  job_name LIKE 'CSR_LOAD_%'
    )
    LOOP
        BEGIN
            DBMS_SCHEDULER.STOP_JOB(job_name => j.job_name, force => TRUE);
        EXCEPTION
            WHEN OTHERS THEN
                NULL; -- job may have already finished/auto-dropped
        END;
        v_stopped := v_stopped + 1;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Stopped/cleared ' || v_stopped || ' CSR load job(s).');
END;
/

-- Any jobs still listed (e.g. RUNNING at the moment STOP_JOB was issued)
-- will auto-drop on completion because they were created with auto_drop=>TRUE
-- in setup.sql. Confirm nothing is left running:
SELECT job_name, state
FROM   user_scheduler_jobs
WHERE  job_name LIKE 'CSR_LOAD_%';

-- -----------------------------------------------------------------------------
-- Kill any still-active CSR sessions directly, as a last resort
-- -----------------------------------------------------------------------------
-- Only needed if the jobs above didn't fully stop in-flight PL/SQL calls.
-- Review the list before killing anything — never kill sessions blindly.
SELECT s.sid, s.serial#, s.module, s.action, s.status
FROM   v$session s
WHERE  s.username = 'PERF_LAB'
AND    s.module IN ('ORDER_LOOKUP_SCREEN', 'PAYMENT_RECON_SCREEN');

-- Example (uncomment and fill in a real sid/serial# from the query above):
-- ALTER SYSTEM KILL SESSION '&sid,&serial#' IMMEDIATE;

PROMPT Cleanup complete. Demo objects, the fix, and the schema are left in place —
PROMPT use reset.sql to fully rewind Day 2 for a fresh run.
