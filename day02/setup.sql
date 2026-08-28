-- =============================================================================
-- Day 2 — Systematic Investigation: From Symptom to SQL
-- setup.sql
--
-- Assumes the PERF_LAB schema already exists (CUSTOMERS, PRODUCTS, ORDERS,
-- ORDER_ITEMS, PAYMENTS, TRANSACTIONS, EMPLOYEES, DEPARTMENTS, SALES,
-- LOG_EVENTS) at Standard tier, built by setup/01-06 at the repo root.
-- This script adds ONLY what Day 2 needs on top of that schema:
--
--   1. Guarantees ORDER_ITEMS.PRODUCT_ID has NO supporting index (the
--      demo's injected root cause) — indexing itself is Day 23 content,
--      so at this point in the course no non-PK/FK index is assumed.
--   2. Two "screen" procedures that stand in for real application code:
--        SP_CSR_ORDER_LOOKUP_BY_PRODUCT   — the Day 2 demo incident
--        SP_CSR_PAYMENT_LOOKUP_BY_METHOD  — the Day 2 independent lab incident
--   3. Two load-generator procedures that simulate a spike of concurrent
--      CSR (Customer Service Rep) sessions hammering each screen, using
--      DBMS_SCHEDULER one-off jobs. This is lab MECHANICS to reproduce a
--      concurrency spike on demand — it is not itself course content.
--
-- Run connected as PERF_LAB (or a DBA account with ALTER SESSION SET
-- CURRENT_SCHEMA = PERF_LAB already issued).
--
-- Requires: CREATE JOB (DBMS_SCHEDULER) privilege on the PERF_LAB account.
-- If PERF_LAB does not already have it:
--   GRANT CREATE JOB TO perf_lab;   -- run once, as a DBA, before this script
--
-- COLUMN-NAME ASSUMPTION: the master PERF_LAB DDL (setup/02_create_tables.sql
-- at the repo root) is being built in parallel and its exact column list
-- wasn't available when this script was written. This script assumes the
-- obvious, conventional column names for a schema of this shape:
--   ORDER_ITEMS(ORDER_ID, PRODUCT_ID, QUANTITY, UNIT_PRICE)
--   ORDERS(ORDER_ID, CUSTOMER_ID, ORDER_DATE, ORDER_STATUS)
--   PAYMENTS(PAYMENT_ID, ORDER_ID, AMOUNT, PAYMENT_DATE)
-- Verify these against the actual DDL before running this in a real class;
-- adjust the procedure bodies below if any name differs.
-- =============================================================================

SET SERVEROUTPUT ON
WHENEVER SQLERROR CONTINUE

-- -----------------------------------------------------------------------------
-- 1. Ensure ORDER_ITEMS.PRODUCT_ID has no supporting index
-- -----------------------------------------------------------------------------
-- Defensive: if a prior run of this script (or an earlier day) left an index
-- on PRODUCT_ID behind, drop it so the demo reliably reproduces a full scan.
-- This does NOT touch the primary key or FK-enforcing indexes.
DECLARE
    v_count NUMBER;
BEGIN
    FOR idx_rec IN (
        SELECT ic.index_name
        FROM   user_ind_columns ic
        JOIN   user_indexes ui ON ui.index_name = ic.index_name
        WHERE  ic.table_name  = 'ORDER_ITEMS'
        AND    ic.column_name = 'PRODUCT_ID'
        AND    ic.column_position = 1
        AND    ui.index_type NOT IN ('LOB')
        AND    ui.uniqueness = 'NONUNIQUE'          -- never touch the PK
    )
    LOOP
        EXECUTE IMMEDIATE 'DROP INDEX ' || idx_rec.index_name;
        DBMS_OUTPUT.PUT_LINE('Dropped pre-existing index: ' || idx_rec.index_name);
    END LOOP;
END;
/

-- -----------------------------------------------------------------------------
-- 2a. The demo "screen": Order Lookup by Product
-- -----------------------------------------------------------------------------
-- Represents the customer-service "which orders contain this product?" screen.
-- This is the query that used to be run rarely and cheaply; it has ALWAYS done
-- a full scan of ORDER_ITEMS (no index was ever built for it), but that only
-- became a business-visible problem once call volume made it concurrent.
CREATE OR REPLACE PROCEDURE sp_csr_order_lookup_by_product (
    p_product_id IN order_items.product_id%TYPE
) AUTHID DEFINER
IS
    CURSOR c_lookup IS
        SELECT oi.order_id,
               oi.product_id,
               oi.quantity,
               oi.unit_price,
               o.customer_id,
               o.order_date,
               o.order_status
        FROM   order_items oi
        JOIN   orders      o ON o.order_id = oi.order_id
        WHERE  oi.product_id = p_product_id;

    v_row  c_lookup%ROWTYPE;
    v_cnt  PLS_INTEGER := 0;
BEGIN
    DBMS_APPLICATION_INFO.SET_MODULE(
        module_name => 'ORDER_LOOKUP_SCREEN',
        action_name => 'BY_PRODUCT');

    OPEN c_lookup;
    LOOP
        FETCH c_lookup INTO v_row;
        EXIT WHEN c_lookup%NOTFOUND;
        v_cnt := v_cnt + 1;                -- simulate the screen rendering each row
    END LOOP;
    CLOSE c_lookup;

    DBMS_APPLICATION_INFO.SET_MODULE(NULL, NULL);
END sp_csr_order_lookup_by_product;
/
SHOW ERRORS PROCEDURE sp_csr_order_lookup_by_product

-- -----------------------------------------------------------------------------
-- 2b. Load generator for the demo: simulate a spike of concurrent CSR sessions
-- -----------------------------------------------------------------------------
-- Spawns p_sessions one-off DBMS_SCHEDULER jobs, each repeatedly calling
-- sp_csr_order_lookup_by_product for roughly p_duration_seconds, to reproduce
-- the "everyone is on the phone about the same product today" spike.
-- ENVIRONMENT DEPENDENT: how many concurrent sessions are needed to make the
-- contention visible depends on CPU core count / storage throughput of the
-- lab host. Start with the defaults used in demo.sql and scale up if the
-- symptom is not obvious.
CREATE OR REPLACE PROCEDURE sp_generate_csr_load_product (
    p_sessions         IN PLS_INTEGER DEFAULT 25,
    p_duration_seconds IN PLS_INTEGER DEFAULT 90,
    p_product_id       IN order_items.product_id%TYPE DEFAULT NULL
) AUTHID DEFINER
IS
    v_product_id order_items.product_id%TYPE := p_product_id;
    v_job_name   VARCHAR2(128);
BEGIN
    -- Default to a product that genuinely appears across many orders, so the
    -- full scan has real work to do and the query result set is non-trivial.
    IF v_product_id IS NULL THEN
        SELECT product_id INTO v_product_id
        FROM  (SELECT product_id, COUNT(*) cnt
               FROM   order_items
               GROUP BY product_id
               ORDER BY cnt DESC)
        WHERE  ROWNUM = 1;
    END IF;

    FOR i IN 1 .. p_sessions LOOP
        v_job_name := 'CSR_LOAD_PROD_' || TO_CHAR(i) || '_' ||
                      TO_CHAR(SYSTIMESTAMP, 'HH24MISSFF3');

        DBMS_SCHEDULER.CREATE_JOB(
            job_name        => v_job_name,
            job_type        => 'PLSQL_BLOCK',
            job_action       => q'[
                DECLARE
                  v_end_time DATE := SYSDATE + (]' || p_duration_seconds || q'[/86400);
                BEGIN
                  WHILE SYSDATE < v_end_time LOOP
                    perf_lab.sp_csr_order_lookup_by_product(]' || v_product_id || q'[);
                  END LOOP;
                END;]',
            enabled         => TRUE,
            auto_drop       => TRUE);
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Launched ' || p_sessions ||
        ' concurrent CSR sessions against PRODUCT_ID = ' || v_product_id ||
        ' for ~' || p_duration_seconds || ' seconds.');
END sp_generate_csr_load_product;
/
SHOW ERRORS PROCEDURE sp_generate_csr_load_product

-- -----------------------------------------------------------------------------
-- 3a. Hands-on Lab "screen": Payment Lookup by Method
-- -----------------------------------------------------------------------------
-- PAYMENT_METHOD is a Day-2-specific addition to PAYMENTS: a new filter the
-- reconciliation team asked for ("show me every payment made by X method on
-- a given day") that was shipped without an index, on the assumption "it's
-- just an internal report, nobody will run it much." This is the second,
-- structurally similar but distinct problem students investigate on their
-- own in the Hands-on Lab.
DECLARE
    v_exists PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_exists
    FROM   user_tab_columns
    WHERE  table_name  = 'PAYMENTS'
    AND    column_name = 'PAYMENT_METHOD';

    IF v_exists = 0 THEN
        EXECUTE IMMEDIATE
            'ALTER TABLE payments ADD payment_method VARCHAR2(20)';

        -- Populate with a realistic method distribution. Adjust the batch
        -- size / COMMIT frequency to taste for your lab hardware.
        EXECUTE IMMEDIATE q'[
            UPDATE payments
            SET    payment_method =
                     CASE MOD(payment_id, 5)
                       WHEN 0 THEN 'CREDIT_CARD'
                       WHEN 1 THEN 'DEBIT_CARD'
                       WHEN 2 THEN 'PAYPAL'
                       WHEN 3 THEN 'BANK_TRANSFER'
                       ELSE        'GIFT_CARD'
                     END
        ]';
        COMMIT;

        DBMS_OUTPUT.PUT_LINE('Added and populated PAYMENTS.PAYMENT_METHOD.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('PAYMENTS.PAYMENT_METHOD already present — skipped.');
    END IF;
END;
/

-- Defensive: drop any index on PAYMENT_METHOD so the lab problem is guaranteed
-- to reproduce (this column should never have been indexed for this exercise).
DECLARE
    v_count NUMBER;
BEGIN
    FOR idx_rec IN (
        SELECT ic.index_name
        FROM   user_ind_columns ic
        JOIN   user_indexes ui ON ui.index_name = ic.index_name
        WHERE  ic.table_name   = 'PAYMENTS'
        AND    ic.column_name  = 'PAYMENT_METHOD'
        AND    ic.column_position = 1
    )
    LOOP
        EXECUTE IMMEDIATE 'DROP INDEX ' || idx_rec.index_name;
        DBMS_OUTPUT.PUT_LINE('Dropped pre-existing index: ' || idx_rec.index_name);
    END LOOP;
END;
/

CREATE OR REPLACE PROCEDURE sp_csr_payment_lookup_by_method (
    p_payment_method IN payments.payment_method%TYPE
) AUTHID DEFINER
IS
    CURSOR c_lookup IS
        SELECT payment_id, order_id, payment_method, amount, payment_date
        FROM   payments
        WHERE  payment_method = p_payment_method;

    v_row c_lookup%ROWTYPE;
    v_cnt PLS_INTEGER := 0;
BEGIN
    DBMS_APPLICATION_INFO.SET_MODULE(
        module_name => 'PAYMENT_RECON_SCREEN',
        action_name => 'BY_METHOD');

    OPEN c_lookup;
    LOOP
        FETCH c_lookup INTO v_row;
        EXIT WHEN c_lookup%NOTFOUND;
        v_cnt := v_cnt + 1;
    END LOOP;
    CLOSE c_lookup;

    DBMS_APPLICATION_INFO.SET_MODULE(NULL, NULL);
END sp_csr_payment_lookup_by_method;
/
SHOW ERRORS PROCEDURE sp_csr_payment_lookup_by_method

-- -----------------------------------------------------------------------------
-- 3b. Load generator for the Hands-on Lab problem
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_generate_csr_load_payment (
    p_sessions         IN PLS_INTEGER DEFAULT 20,
    p_duration_seconds IN PLS_INTEGER DEFAULT 90,
    p_payment_method   IN payments.payment_method%TYPE DEFAULT 'CREDIT_CARD'
) AUTHID DEFINER
IS
    v_job_name VARCHAR2(128);
BEGIN
    FOR i IN 1 .. p_sessions LOOP
        v_job_name := 'CSR_LOAD_PAY_' || TO_CHAR(i) || '_' ||
                      TO_CHAR(SYSTIMESTAMP, 'HH24MISSFF3');

        DBMS_SCHEDULER.CREATE_JOB(
            job_name        => v_job_name,
            job_type        => 'PLSQL_BLOCK',
            job_action       => q'[
                DECLARE
                  v_end_time DATE := SYSDATE + (]' || p_duration_seconds || q'[/86400);
                BEGIN
                  WHILE SYSDATE < v_end_time LOOP
                    perf_lab.sp_csr_payment_lookup_by_method(']' || p_payment_method || q'[');
                  END LOOP;
                END;]',
            enabled         => TRUE,
            auto_drop       => TRUE);
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Launched ' || p_sessions ||
        ' concurrent CSR sessions against PAYMENT_METHOD = ''' || p_payment_method ||
        ''' for ~' || p_duration_seconds || ' seconds.');
END sp_generate_csr_load_payment;
/
SHOW ERRORS PROCEDURE sp_generate_csr_load_payment

-- -----------------------------------------------------------------------------
-- 4. Verification
-- -----------------------------------------------------------------------------
SELECT object_name, object_type, status
FROM   user_objects
WHERE  object_name IN (
         'SP_CSR_ORDER_LOOKUP_BY_PRODUCT', 'SP_GENERATE_CSR_LOAD_PRODUCT',
         'SP_CSR_PAYMENT_LOOKUP_BY_METHOD', 'SP_GENERATE_CSR_LOAD_PAYMENT')
ORDER BY object_name;

SELECT 'ORDER_ITEMS.PRODUCT_ID indexed?' AS check_name,
       CASE WHEN COUNT(*) = 0 THEN 'NO (expected)' ELSE 'YES — investigate!' END AS result
FROM   user_ind_columns
WHERE  table_name = 'ORDER_ITEMS' AND column_name = 'PRODUCT_ID' AND column_position = 1
UNION ALL
SELECT 'PAYMENTS.PAYMENT_METHOD indexed?',
       CASE WHEN COUNT(*) = 0 THEN 'NO (expected)' ELSE 'YES — investigate!' END
FROM   user_ind_columns
WHERE  table_name = 'PAYMENTS' AND column_name = 'PAYMENT_METHOD' AND column_position = 1;

PROMPT Day 2 setup complete.
