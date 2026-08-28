-- =============================================================================
-- Day 2 — Systematic Investigation: From Symptom to SQL
-- reset.sql — full rewind to a clean, re-runnable "problem still exists" state
--
-- Run cleanup.sql FIRST if any load-generator jobs might still be running.
-- This script:
--   1. Drops the fix (the index) so the root cause reproduces again.
--   2. Drops all Day 2 helper objects (procedures, any leftover jobs).
--   3. Leaves PAYMENTS.PAYMENT_METHOD and its data in place (regenerating
--      20M+ rows of PAYMENTS data is expensive and the column itself is
--      inert without the lab procedures — only the injected condition,
--      "no index," needs to be guaranteed, which is re-asserted below).
--
-- After running this, re-running setup.sql brings Day 2 back to exactly the
-- state it was in before the demo ever started.
-- =============================================================================

SET SERVEROUTPUT ON

-- -----------------------------------------------------------------------------
-- 1. Drop the fix
-- -----------------------------------------------------------------------------
DECLARE
    v_exists PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_exists
    FROM   user_indexes
    WHERE  index_name = 'IX_ORDER_ITEMS_PRODUCT_ID';

    IF v_exists > 0 THEN
        EXECUTE IMMEDIATE 'DROP INDEX ix_order_items_product_id';
        DBMS_OUTPUT.PUT_LINE('Dropped ix_order_items_product_id.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('ix_order_items_product_id not present — nothing to drop.');
    END IF;
END;
/

-- -----------------------------------------------------------------------------
-- 2. Re-assert the injected condition on PAYMENTS.PAYMENT_METHOD (lab problem)
-- -----------------------------------------------------------------------------
DECLARE
    v_count NUMBER;
BEGIN
    FOR idx_rec IN (
        SELECT ic.index_name
        FROM   user_ind_columns ic
        WHERE  ic.table_name  = 'PAYMENTS'
        AND    ic.column_name = 'PAYMENT_METHOD'
        AND    ic.column_position = 1
    )
    LOOP
        EXECUTE IMMEDIATE 'DROP INDEX ' || idx_rec.index_name;
        DBMS_OUTPUT.PUT_LINE('Dropped ' || idx_rec.index_name || ' (lab problem re-asserted).');
    END LOOP;
END;
/

-- -----------------------------------------------------------------------------
-- 3. Drop Day 2 helper procedures (setup.sql will recreate them)
-- -----------------------------------------------------------------------------
BEGIN
    FOR p IN (
        SELECT object_name
        FROM   user_objects
        WHERE  object_type = 'PROCEDURE'
        AND    object_name IN (
                 'SP_CSR_ORDER_LOOKUP_BY_PRODUCT', 'SP_GENERATE_CSR_LOAD_PRODUCT',
                 'SP_CSR_PAYMENT_LOOKUP_BY_METHOD', 'SP_GENERATE_CSR_LOAD_PAYMENT')
    )
    LOOP
        EXECUTE IMMEDIATE 'DROP PROCEDURE ' || p.object_name;
        DBMS_OUTPUT.PUT_LINE('Dropped procedure ' || p.object_name);
    END LOOP;
END;
/

-- -----------------------------------------------------------------------------
-- 4. Clear any leftover scheduler jobs
-- -----------------------------------------------------------------------------
BEGIN
    FOR j IN (SELECT job_name FROM user_scheduler_jobs WHERE job_name LIKE 'CSR_LOAD_%')
    LOOP
        BEGIN
            DBMS_SCHEDULER.DROP_JOB(job_name => j.job_name, force => TRUE);
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END LOOP;
END;
/

-- -----------------------------------------------------------------------------
-- 5. Flush the shared pool so no stale cached plan for the old/new access
--    path lingers into the next run (optional but recommended between runs)
-- -----------------------------------------------------------------------------
-- Uncomment if re-running the full demo in the same instance shortly after:
-- ALTER SYSTEM FLUSH SHARED_POOL;

-- -----------------------------------------------------------------------------
-- 6. Verify
-- -----------------------------------------------------------------------------
SELECT object_name, object_type
FROM   user_objects
WHERE  object_name IN (
         'SP_CSR_ORDER_LOOKUP_BY_PRODUCT', 'SP_GENERATE_CSR_LOAD_PRODUCT',
         'SP_CSR_PAYMENT_LOOKUP_BY_METHOD', 'SP_GENERATE_CSR_LOAD_PAYMENT',
         'IX_ORDER_ITEMS_PRODUCT_ID');
-- Expected: zero rows — everything Day 2 added is gone except the base
-- PAYMENTS.PAYMENT_METHOD column/data, which is harmless to leave behind.

PROMPT Reset complete. Run setup.sql to rebuild Day 2 from scratch.
