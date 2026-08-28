-- =============================================================================
-- Day 5 — Architecture Bootcamp III: Process Architecture & Connections
-- setup.sql
--
-- Purpose: create the small, disposable Day-5-only objects used for the
-- write-heavy workload demo (LGWR/DBWn observation). This does NOT touch the
-- large PERF_LAB tables (ORDERS, ORDER_ITEMS, TRANSACTIONS, etc.) — Day 5 is
-- about connections and background processes, not data volume.
--
-- Run connected as: PERF_LAB (the lab application schema is assumed to
-- already exist, per the course lab environment design).
--
-- NOTE FOR INSTRUCTOR: no live Oracle instance was available while writing
-- this script. The SQL below is syntactically correct, standard 19c PL/SQL
-- and DDL/DML — verify against a real 19c instance before class, and adjust
-- the workload sizing (p_batches / p_rows_per_batch) if it runs too fast or
-- too slow for your lab hardware (ENVIRONMENT DEPENDENT).
-- =============================================================================

WHENEVER SQLERROR CONTINUE

-- -----------------------------------------------------------------------------
-- 1. Disposable table for the write-heavy workload.
--    Small, narrow, no indexes beyond the PK — this is deliberately a simple
--    redo/dirty-buffer generator, not a realistic application table.
-- -----------------------------------------------------------------------------
BEGIN
   EXECUTE IMMEDIATE 'DROP TABLE PERF_LAB.DAY05_WRITE_DEMO PURGE';
EXCEPTION
   WHEN OTHERS THEN
      IF SQLCODE != -942 THEN -- ORA-00942: table or view does not exist
         RAISE;
      END IF;
END;
/

CREATE TABLE PERF_LAB.DAY05_WRITE_DEMO (
   ID          NUMBER          GENERATED ALWAYS AS IDENTITY,
   BATCH_NO    NUMBER          NOT NULL,
   PAYLOAD     VARCHAR2(200)   NOT NULL,
   CREATED_AT  TIMESTAMP       DEFAULT SYSTIMESTAMP NOT NULL,
   UPDATED_AT  TIMESTAMP,
   CONSTRAINT day05_write_demo_pk PRIMARY KEY (ID)
);

COMMENT ON TABLE PERF_LAB.DAY05_WRITE_DEMO IS
   'Day 5 disposable table: exists only to generate a controlled, observable
    write workload (redo + dirty buffers) for the LGWR/DBWn demo. Safe to
    truncate/drop at will — never used by any other day.';

-- -----------------------------------------------------------------------------
-- 2. Controlled write-load generator.
--    Inserts p_rows_per_batch rows per batch, commits after each batch
--    (so LGWR has real commit-driven work to do), then does a small UPDATE
--    pass to dirty buffers again without generating new rows. A short
--    DBMS_LOCK.SLEEP-free pause is intentionally NOT included by default so
--    the demo produces a fast, visible V$SYSSTAT delta; p_delay_seconds is
--    provided for instructors who want to slow it down to talk over it.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE PERF_LAB.DAY05_GENERATE_WRITE_LOAD (
   p_batches        IN NUMBER DEFAULT 10,
   p_rows_per_batch IN NUMBER DEFAULT 500,
   p_delay_seconds  IN NUMBER DEFAULT 0
) AUTHID DEFINER
IS
   v_payload VARCHAR2(200);
BEGIN
   FOR b IN 1 .. p_batches LOOP
      FOR r IN 1 .. p_rows_per_batch LOOP
         v_payload := 'day05-demo-batch-' || b || '-row-' || r || '-' ||
                      DBMS_RANDOM.STRING('X', 40);
         INSERT INTO PERF_LAB.DAY05_WRITE_DEMO (BATCH_NO, PAYLOAD)
         VALUES (b, v_payload);
      END LOOP;

      -- Commit each batch: this is what gives LGWR a concrete, repeated
      -- reason to flush the redo buffer to disk (write-ahead / commit rule).
      COMMIT;

      -- A follow-up UPDATE pass dirties buffers again without adding new
      -- rows, giving DBWn additional write-back work independent of LGWR's
      -- commit-driven flushes.
      UPDATE PERF_LAB.DAY05_WRITE_DEMO
      SET    UPDATED_AT = SYSTIMESTAMP
      WHERE  BATCH_NO = b;
      COMMIT;

      IF p_delay_seconds > 0 THEN
         DBMS_LOCK.SLEEP(p_delay_seconds); -- optional, instructor pacing only
      END IF;
   END LOOP;
END DAY05_GENERATE_WRITE_LOAD;
/

SHOW ERRORS PROCEDURE PERF_LAB.DAY05_GENERATE_WRITE_LOAD

-- -----------------------------------------------------------------------------
-- 3. Sanity check: confirm the objects exist and the procedure compiles.
-- -----------------------------------------------------------------------------
SELECT object_name, object_type, status
FROM   dba_objects
WHERE  owner = 'PERF_LAB'
AND    object_name IN ('DAY05_WRITE_DEMO', 'DAY05_GENERATE_WRITE_LOAD')
ORDER BY object_type;

PROMPT Day 5 setup complete: PERF_LAB.DAY05_WRITE_DEMO table and
PROMPT PERF_LAB.DAY05_GENERATE_WRITE_LOAD procedure are ready.
