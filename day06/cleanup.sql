-- =============================================================================
-- Day 06 -- Architecture Bootcamp IV: How Oracle Executes a Statement
-- cleanup.sql
--
-- Session-scoped cleanup after the demo. No PERF_LAB data was modified by
-- this day (every demo/diagnose/fix statement was a SELECT), so there is no
-- data to roll back. This script:
--   1. Purges the specific demo cursors this session created out of the
--      shared pool, so they do not linger and confuse the NEXT run of this
--      same lab (by this student or the next cohort) with stale LOADS/
--      PARSE_CALLS history.
--   2. Clears the session's MODULE/ACTION tag and statistics level (belt
--      and suspenders -- demo.sql Step 8 already does this).
--
-- Requires: EXECUTE on DBMS_SHARED_POOL (grants PURGE), typically a DBA-
-- level privilege. If this session does not have it, skip straight to
-- reset.sql, which an instructor/DBA account runs instead.
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200

-- Purge every child cursor whose SQL text carries today's DAY06_ tag family
-- (both the main demo statement and the fix.sql COUNT(*) statement).
DECLARE
  l_purged NUMBER := 0;
BEGIN
  FOR rec IN (
    SELECT DISTINCT sql_id, address, hash_value
    FROM   v$sqlarea
    WHERE  sql_text LIKE '%DAY06\_%' ESCAPE '\'
  ) LOOP
    BEGIN
      DBMS_SHARED_POOL.PURGE(rec.address || ',' || rec.hash_value, 'C');
      l_purged := l_purged + 1;
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Could not purge SQL_ID ' || rec.sql_id
                              || ' (insufficient privilege or already aged out): '
                              || SQLERRM);
    END;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('Purged ' || l_purged || ' Day 06 demo cursor(s) from the shared pool.');
END;
/

-- Reset this session's own state, defensively (idempotent with demo.sql Step 8).
ALTER SESSION SET STATISTICS_LEVEL = TYPICAL;

BEGIN
  DBMS_APPLICATION_INFO.SET_MODULE(module_name => NULL, action_name => NULL);
END;
/

PROMPT ================================================================
PROMPT Day 06 session-level cleanup complete.
PROMPT No PERF_LAB data was changed by this day (all demo SQL was SELECT).
PROMPT For a full shared-pool flush ahead of the NEXT cohort, run reset.sql
PROMPT as an instructor/DBA account.
PROMPT ================================================================
