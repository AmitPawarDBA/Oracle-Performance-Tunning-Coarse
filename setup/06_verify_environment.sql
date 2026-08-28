-- =============================================================================
-- PERF_LAB Setup — Script 06 of 7 (final step)
-- 06_verify_environment.sql
--
-- Purpose: confirm setup completed correctly — actual row counts per table
-- against the expected counts for the tier/scale used, plus a basic sanity
-- check that the expected objects (tables, constraints, indexes,
-- partitions, statistics) are all present. READ-ONLY — creates, drops, and
-- modifies nothing.
--
-- Run connected AS perf_lab, after 05_create_statistics.sql:
--   sqlplus perf_lab/<password>@//localhost:1521/PERFPDB @06_verify_environment.sql
--
-- You will be asked to re-enter the SAME scale factor (&c_scale) you used
-- in 04_generate_data.sql — this script has no way to recover that value on
-- its own (it isn't persisted anywhere in the schema), so entering the
-- wrong one here will produce misleading FAILs/PASSes against the wrong
-- expected counts, not an error. If you're unsure what you used, the row
-- counts printed below will tell you: divide any table's actual count by
-- its Standard-tier base count (documented in 04_generate_data.sql's
-- header) to recover it.
-- =============================================================================

SET DEFINE ON
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF
SET TIMING ON
SET LINESIZE 200
SET ECHO OFF

PROMPT
PROMPT ================================================================================
PROMPT  PERF_LAB Setup — Step 6: verify environment (final step)
PROMPT ================================================================================
PROMPT

ACCEPT c_scale NUMBER DEFAULT 1 PROMPT 'Scale factor used in 04_generate_data.sql (Small ~0.05-0.10, Standard 1, Large 3-5) [1]: '

DECLARE
    v_scale        NUMBER := &c_scale;

    v_pass_count   PLS_INTEGER := 0;
    v_warn_count   PLS_INTEGER := 0;
    v_fail_count   PLS_INTEGER := 0;

    v_actual       NUMBER;
    v_expected     NUMBER;
    v_who          VARCHAR2(30);

    -- -------------------------------------------------------------------
    -- pr(): one PASS/WARN/FAIL line, tallied — same pattern as
    -- 00_environment_check.sql.
    -- -------------------------------------------------------------------
    PROCEDURE pr(p_check IN VARCHAR2, p_status IN VARCHAR2, p_detail IN VARCHAR2 DEFAULT NULL) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(
            RPAD(p_check, 46, ' ') || ' [' || RPAD(p_status, 4, ' ') || ']' ||
            CASE WHEN p_detail IS NOT NULL THEN '  ' || p_detail ELSE NULL END
        );
        IF    p_status = 'PASS' THEN v_pass_count := v_pass_count + 1;
        ELSIF p_status = 'WARN' THEN v_warn_count := v_warn_count + 1;
        ELSIF p_status = 'FAIL' THEN v_fail_count := v_fail_count + 1;
        END IF;
    END pr;

    -- -------------------------------------------------------------------
    -- check_table(): compares an actual row count to an expected count
    -- (Standard-tier base * v_scale) with tolerance bands. Generation in
    -- 04_generate_data.sql is deterministic, so an exact or near-exact
    -- match is normal — this is not a sampled estimate.
    --   0% off            -> PASS
    --   up to 1% off      -> PASS  (rounding at the scale-factor boundary)
    --   up to 10% off     -> WARN  (load likely incomplete or re-run partially)
    --   actual = 0, or
    --   more than 10% off -> FAIL
    -- -------------------------------------------------------------------
    PROCEDURE check_table(p_table IN VARCHAR2, p_actual IN NUMBER, p_expected IN NUMBER) IS
        v_diff_pct NUMBER;
    BEGIN
        IF p_actual = 0 AND p_expected > 0 THEN
            pr(p_table, 'FAIL',
               'actual=0, expected~' || p_expected ||
               ' — table appears empty; 04_generate_data.sql did not load this table.');
            RETURN;
        END IF;

        v_diff_pct := ABS(p_actual - p_expected) / GREATEST(p_expected,1) * 100;

        IF v_diff_pct <= 1 THEN
            pr(p_table, 'PASS', 'actual=' || TO_CHAR(p_actual,'FM999,999,999,999') ||
                                  '  expected~' || TO_CHAR(p_expected,'FM999,999,999,999'));
        ELSIF v_diff_pct <= 10 THEN
            pr(p_table, 'WARN', 'actual=' || TO_CHAR(p_actual,'FM999,999,999,999') ||
                                  '  expected~' || TO_CHAR(p_expected,'FM999,999,999,999') ||
                                  '  (' || ROUND(v_diff_pct,1) || '% off — check for a partial/interrupted load)');
        ELSE
            pr(p_table, 'FAIL', 'actual=' || TO_CHAR(p_actual,'FM999,999,999,999') ||
                                  '  expected~' || TO_CHAR(p_expected,'FM999,999,999,999') ||
                                  '  (' || ROUND(v_diff_pct,1) || '% off — did you enter the same' ||
                                  ' scale factor used in 04_generate_data.sql?)');
        END IF;
    END check_table;

BEGIN
    DBMS_OUTPUT.PUT_LINE('Using scale factor v_scale = ' || v_scale);
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 80, '-'));

    -- =====================================================================
    -- Connected-as sanity check
    -- =====================================================================
    SELECT USER INTO v_who FROM dual;
    IF v_who = 'PERF_LAB' THEN
        pr('Connected as PERF_LAB', 'PASS');
    ELSE
        pr('Connected as PERF_LAB', 'WARN', 'Connected as ' || v_who ||
           ' — table counts below are read from THIS schema''s objects, so' ||
           ' if you did not run 01-05 as PERF_LAB, these checks are meaningless.');
    END IF;

    -- =====================================================================
    -- Row counts — the 10 PERF_LAB tables against Standard-tier * v_scale
    -- =====================================================================
    DBMS_OUTPUT.PUT_LINE(' ');
    DBMS_OUTPUT.PUT_LINE('-- Row counts --');

    SELECT COUNT(*) INTO v_actual FROM departments;
    check_table('DEPARTMENTS',  v_actual, ROUND(200*v_scale));

    SELECT COUNT(*) INTO v_actual FROM employees;
    check_table('EMPLOYEES',    v_actual, ROUND(10000*v_scale));

    SELECT COUNT(*) INTO v_actual FROM customers;
    check_table('CUSTOMERS',    v_actual, ROUND(500000*v_scale));

    SELECT COUNT(*) INTO v_actual FROM products;
    check_table('PRODUCTS',     v_actual, ROUND(50000*v_scale));

    SELECT COUNT(*) INTO v_actual FROM orders;
    check_table('ORDERS',       v_actual, ROUND(5000000*v_scale));

    SELECT COUNT(*) INTO v_actual FROM order_items;
    check_table('ORDER_ITEMS',  v_actual, ROUND(5000000*v_scale) * 4);   -- see 04's step 6

    SELECT COUNT(*) INTO v_actual FROM payments;
    check_table('PAYMENTS',     v_actual, ROUND(5000000*v_scale));       -- 1:1 with ORDERS, see 04's step 7

    SELECT COUNT(*) INTO v_actual FROM transactions;
    check_table('TRANSACTIONS', v_actual, ROUND(10000000*v_scale));

    SELECT COUNT(*) INTO v_actual FROM sales;
    check_table('SALES',        v_actual, ROUND(10000000*v_scale));

    SELECT COUNT(*) INTO v_actual FROM log_events;
    check_table('LOG_EVENTS',   v_actual, ROUND(20000000*v_scale));

    -- =====================================================================
    -- Object sanity checks
    -- =====================================================================
    DBMS_OUTPUT.PUT_LINE(' ');
    DBMS_OUTPUT.PUT_LINE('-- Object counts --');

    SELECT COUNT(*) INTO v_actual FROM user_tables;
    IF v_actual = 10 THEN
        pr('Table count = 10', 'PASS');
    ELSE
        pr('Table count = 10', 'FAIL', 'Found ' || v_actual || ' tables — expected exactly the 10 built by 02_create_tables.sql.');
    END IF;

    SELECT COUNT(*) INTO v_actual FROM user_constraints WHERE constraint_type = 'P';
    IF v_actual = 10 THEN
        pr('Primary key constraints = 10', 'PASS');
    ELSE
        pr('Primary key constraints = 10', 'FAIL', 'Found ' || v_actual || '.');
    END IF;

    SELECT COUNT(*) INTO v_actual FROM user_constraints WHERE constraint_type = 'R';
    IF v_actual = 10 THEN
        pr('Foreign key constraints = 10', 'PASS');
    ELSE
        pr('Foreign key constraints = 10', 'WARN', 'Found ' || v_actual ||
           ' — expected 10 (see 02_create_tables.sql for the full list); a mismatch' ||
           ' here usually means 02 was edited or only partially ran.');
    END IF;

    SELECT COUNT(*) INTO v_actual FROM user_constraints WHERE constraint_type = 'U';
    IF v_actual = 4 THEN
        pr('Unique constraints = 4', 'PASS');
    ELSE
        pr('Unique constraints = 4', 'WARN', 'Found ' || v_actual || ' — expected 4' ||
           ' (uq_departments_code, uq_employees_number, uq_customers_number, uq_products_sku).');
    END IF;

    -- Named CHECK constraints only — Oracle auto-generates one unnamed
    -- (SYS_C%) 'C'-type constraint per NOT NULL column, so counting ALL
    -- type='C' rows would not match the 10 explicitly named CHECKs in
    -- 02_create_tables.sql.
    SELECT COUNT(*) INTO v_actual
    FROM   user_constraints
    WHERE  constraint_type = 'C'
    AND    constraint_name NOT LIKE 'SYS\_%' ESCAPE '\';
    IF v_actual = 10 THEN
        pr('Named CHECK constraints = 10', 'PASS');
    ELSE
        pr('Named CHECK constraints = 10', 'WARN', 'Found ' || v_actual || ' — expected 10 named CHECKs' ||
           ' (this ignores the system-generated NOT NULL checks, which are additional and expected).');
    END IF;

    -- Index baseline: 03_create_indexes.sql leaves ONLY the automatic
    -- PK/UNIQUE-supporting indexes in place (10 PK + 4 UNIQUE = 14) unless
    -- the instructor deliberately uncommented its optional FK-index block.
    SELECT COUNT(*) INTO v_actual FROM user_indexes;
    IF v_actual = 14 THEN
        pr('Index count = 14 (PK/UNIQUE baseline)', 'PASS');
    ELSIF v_actual > 14 THEN
        pr('Index count = 14 (PK/UNIQUE baseline)', 'WARN', 'Found ' || v_actual ||
           ' — more than the intentionally-minimal baseline. This is fine if you' ||
           ' deliberately ran the optional FK-index block at the bottom of' ||
           ' 03_create_indexes.sql; otherwise review what added the extra index(es),' ||
           ' since several days'' demos depend on specific FK columns starting unindexed.');
    ELSE
        pr('Index count = 14 (PK/UNIQUE baseline)', 'FAIL', 'Found only ' || v_actual ||
           ' — fewer than the 14 automatic PK/UNIQUE indexes 02_create_tables.sql should' ||
           ' have created. Review 02_create_tables.sql and 03_create_indexes.sql for errors.');
    END IF;

    -- Partitioned tables actually have partitions materialized.
    SELECT COUNT(*) INTO v_actual FROM user_tab_partitions WHERE table_name = 'ORDERS';
    IF v_actual >= 1 THEN
        pr('ORDERS has partitions', 'PASS', v_actual || ' partition(s) present');
    ELSE
        pr('ORDERS has partitions', 'FAIL', 'No partitions found — ORDERS should be interval-partitioned with data in it.');
    END IF;

    SELECT COUNT(*) INTO v_actual FROM user_tab_partitions WHERE table_name = 'SALES';
    IF v_actual >= 1 THEN
        pr('SALES has partitions', 'PASS', v_actual || ' partition(s) present');
    ELSE
        pr('SALES has partitions', 'FAIL', 'No partitions found — SALES should be interval-partitioned with data in it.');
    END IF;

    -- =====================================================================
    -- Statistics sanity check
    -- =====================================================================
    DBMS_OUTPUT.PUT_LINE(' ');
    DBMS_OUTPUT.PUT_LINE('-- Statistics --');

    SELECT COUNT(*) INTO v_actual FROM user_tables WHERE num_rows IS NULL;
    IF v_actual = 0 THEN
        pr('All tables have stats gathered', 'PASS');
    ELSE
        pr('All tables have stats gathered', 'FAIL', v_actual ||
           ' table(s) have NULL num_rows — 05_create_statistics.sql did not complete for them.');
    END IF;

    SELECT COUNT(*) INTO v_actual
    FROM   user_tab_col_statistics
    WHERE  table_name = 'CUSTOMERS'
    AND    column_name IN ('REGION','CUSTOMER_STATUS')
    AND    histogram != 'NONE';
    IF v_actual = 2 THEN
        pr('Histograms present on skewed columns', 'PASS', 'CUSTOMERS.REGION and CUSTOMERS.CUSTOMER_STATUS');
    ELSE
        pr('Histograms present on skewed columns', 'FAIL', 'Found ' || v_actual || ' of 2 expected —' ||
           ' re-run 05_create_statistics.sql. Day 24''s cardinality-misestimation lab needs these.');
    END IF;

    -- =====================================================================
    -- Summary
    -- =====================================================================
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 80, '-'));
    DBMS_OUTPUT.PUT_LINE('SUMMARY: ' || v_pass_count || ' PASS, ' || v_warn_count || ' WARN, ' || v_fail_count || ' FAIL');
    IF v_fail_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('RESULT: FAIL — PERF_LAB setup is NOT complete/correct. Resolve the FAIL item(s) above.');
        DBMS_OUTPUT.PUT_LINE('        Most FAILs mean re-running the relevant earlier script (00-05) is the fix —');
        DBMS_OUTPUT.PUT_LINE('        see the detail text on each FAIL line above for which one.');
    ELSIF v_warn_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('RESULT: PASS WITH WARNINGS — review the WARN item(s) above; the lab is usable but not exactly nominal.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('RESULT: PASS — PERF_LAB is fully set up and ready for Day 1.');
    END IF;
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 80, '-'));
END;
/

PROMPT
PROMPT ================================================================================
PROMPT  Verification complete. If the summary above says PASS (with or without
PROMPT  warnings), PERF_LAB setup (scripts 00-06) is done — proceed to dayNN
PROMPT  material. If it says FAIL, resolve the flagged item(s) and re-run this
PROMPT  script before starting Day 1.
PROMPT ================================================================================
PROMPT
