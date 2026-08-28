-- =============================================================================
-- Day 5 — Architecture Bootcamp III: Process Architecture & Connections
-- cleanup.sql — returns the lab to a clean, re-runnable state
--
-- Run after class (or after any practice run) to guarantee no orphaned demo
-- sessions or Day-5-only objects are left behind for the next run.
--
-- NOTE: no live Oracle instance was available while writing this script.
-- Verify against a real 19c instance before class.
-- =============================================================================

WHENEVER SQLERROR CONTINUE

-- -----------------------------------------------------------------------------
-- 1. Defensively kill any lingering sessions tagged for this day's demo/lab.
--    This is a safe, targeted kill — it only ever touches sessions carrying
--    this day's specific MODULE tags, never an untagged/real session.
-- -----------------------------------------------------------------------------
DECLARE
   CURSOR c_orphans IS
      SELECT sid, serial#
      FROM   v$session
      WHERE  module IN ('DAY05_DEMO_SESSION', 'DAY05_LAB_SESSION');
BEGIN
   FOR r IN c_orphans LOOP
      BEGIN
         EXECUTE IMMEDIATE
            'ALTER SYSTEM KILL SESSION ''' || r.sid || ',' || r.serial# || ''' IMMEDIATE';
         DBMS_OUTPUT.PUT_LINE('Killed orphaned demo session SID=' || r.sid ||
                               ' SERIAL#=' || r.serial#);
      EXCEPTION
         WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Could not kill SID=' || r.sid ||
                                  ' (' || SQLERRM || ') — check manually.');
      END;
   END LOOP;
END;
/

-- Confirm none remain:
SELECT sid, serial#, module
FROM   v$session
WHERE  module IN ('DAY05_DEMO_SESSION', 'DAY05_LAB_SESSION');
-- Expect: no rows.


-- -----------------------------------------------------------------------------
-- 2. Drop the disposable write-workload objects created in setup.sql.
--    Connect as PERF_LAB (or a DBA account with drop privileges on the
--    PERF_LAB schema) to run this section.
-- -----------------------------------------------------------------------------
BEGIN
   EXECUTE IMMEDIATE 'DROP PROCEDURE PERF_LAB.DAY05_GENERATE_WRITE_LOAD';
EXCEPTION
   WHEN OTHERS THEN
      IF SQLCODE != -4043 THEN -- ORA-04043: object does not exist
         RAISE;
      END IF;
END;
/

BEGIN
   EXECUTE IMMEDIATE 'DROP TABLE PERF_LAB.DAY05_WRITE_DEMO PURGE';
EXCEPTION
   WHEN OTHERS THEN
      IF SQLCODE != -942 THEN -- ORA-00942: table or view does not exist
         RAISE;
      END IF;
END;
/


-- -----------------------------------------------------------------------------
-- 3. Confirm the schema is clean.
-- -----------------------------------------------------------------------------
SELECT object_name, object_type
FROM   dba_objects
WHERE  owner = 'PERF_LAB'
AND    object_name IN ('DAY05_WRITE_DEMO', 'DAY05_GENERATE_WRITE_LOAD');
-- Expect: no rows.

PROMPT Day 5 cleanup complete: no orphaned demo sessions, no Day-5-only objects remain.
