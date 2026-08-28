-- =============================================================================
-- PERF_LAB Setup — Script 00 of 7
-- 00_environment_check.sql
--
-- Purpose: verify the target environment meets the prerequisites for the
-- Oracle Database Performance Tuning & Troubleshooting course (PERF_LAB lab)
-- BEFORE running any of the scripts that follow (01-06). This script is
-- READ-ONLY — it creates, drops, and grants nothing.
--
-- Run this connected as the account that will perform setup — i.e. the
-- account that will run 01_create_user.sql (typically SYSTEM, or another
-- DBA-privileged account). Do NOT run this as PERF_LAB itself; PERF_LAB
-- does not exist yet at this point in the setup sequence.
--
-- Usage (adjust host/port/service to your environment):
--   sqlplus system/<password>@//localhost:1521/PERFPDB @00_environment_check.sql
--
-- If your target is a multitenant (CDB) 19c instance, connect directly to
-- the target PDB (PERFPDB by convention in this course) as shown above —
-- do not connect to CDB$ROOT and expect PERF_LAB objects to land in the
-- right place. If your target is a non-CDB instance, the connect string
-- simply omits the /PERFPDB service and everything below still works;
-- the CDB-specific checks report themselves as not applicable.
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF
SET VERIFY OFF
SET ECHO OFF
SET LINESIZE 200
SET PAGESIZE 100
SET TRIMSPOOL ON

PROMPT
PROMPT ================================================================================
PROMPT  PERF_LAB Environment Check  (run BEFORE 01_create_user.sql)
PROMPT ================================================================================
PROMPT

-- ---------------------------------------------------------------------------
-- Raw reference output first. These plain SELECTs are useful on their own
-- even if the connecting account lacks enough privilege to run the full
-- PASS/WARN/FAIL block below (in which case that block will simply report
-- more WARN/FAIL lines — which is itself diagnostic information).
-- ---------------------------------------------------------------------------
PROMPT ---- Raw reference: v$version ----
COLUMN banner FORMAT A80
SELECT banner FROM v$version ORDER BY banner;

PROMPT
PROMPT ---- Raw reference: v$database ----
COLUMN name FORMAT A12
COLUMN cdb FORMAT A5
COLUMN log_mode FORMAT A15
COLUMN open_mode FORMAT A20
COLUMN platform_name FORMAT A30
SELECT name, cdb, log_mode, open_mode, platform_name FROM v$database;

PROMPT
PROMPT ---- Raw reference: v$instance ----
COLUMN instance_name FORMAT A16
COLUMN host_name FORMAT A40
COLUMN version FORMAT A17
COLUMN status FORMAT A10
SELECT instance_name, host_name, version, status, database_status, instance_role
FROM   v$instance;

PROMPT
PROMPT ---- Raw reference: current container (multitenant only; blank/CDB$ROOT if non-CDB or in root) ----
COLUMN con_name FORMAT A20
SELECT SYS_CONTEXT('USERENV','CON_NAME') AS con_name,
       SYS_CONTEXT('USERENV','CON_ID')   AS con_id
FROM   dual;

PROMPT
PROMPT ---- Raw reference: connected as ----
SELECT USER AS connected_as FROM dual;

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  Detailed PASS / WARN / FAIL checks
PROMPT --------------------------------------------------------------------------------
PROMPT

DECLARE
    -- -------------------------------------------------------------------
    -- Counters, tallied by the pr() helper below, used for the summary.
    -- -------------------------------------------------------------------
    v_pass_count  PLS_INTEGER := 0;
    v_warn_count  PLS_INTEGER := 0;
    v_fail_count  PLS_INTEGER := 0;

    v_version_full   v$instance.version%TYPE;
    v_version_major  VARCHAR2(10);
    v_cdb            v$database.cdb%TYPE;
    v_open_mode      v$database.open_mode%TYPE;
    v_inst_status    v$instance.status%TYPE;
    v_con_name       VARCHAR2(64);
    v_con_id         NUMBER;
    v_dummy          PLS_INTEGER;
    v_priv_count     PLS_INTEGER;

    -- -------------------------------------------------------------------
    -- pr(): prints one PASS/WARN/FAIL line in a fixed-width format and
    -- tallies the running totals. Declared here (nested inside the
    -- anonymous block) so it can update the counters declared above —
    -- standard PL/SQL nested-subprogram scoping, not a special trick.
    -- -------------------------------------------------------------------
    PROCEDURE pr(p_check IN VARCHAR2, p_status IN VARCHAR2, p_detail IN VARCHAR2 DEFAULT NULL) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(
            RPAD(p_check, 58, ' ') || ' [' || RPAD(p_status, 4, ' ') || ']' ||
            CASE WHEN p_detail IS NOT NULL THEN '  ' || p_detail ELSE NULL END
        );
        IF p_status = 'PASS' THEN v_pass_count := v_pass_count + 1;
        ELSIF p_status = 'WARN' THEN v_warn_count := v_warn_count + 1;
        ELSIF p_status = 'FAIL' THEN v_fail_count := v_fail_count + 1;
        END IF;
    END pr;

BEGIN
    -- =====================================================================
    -- CHECK 1: Oracle version — course baseline is 19c
    -- =====================================================================
    BEGIN
        SELECT version, SUBSTR(version, 1, INSTR(version, '.') - 1)
        INTO   v_version_full, v_version_major
        FROM   v$instance;

        IF v_version_major = '19' THEN
            pr('Oracle version is 19c', 'PASS', 'version=' || v_version_full);
        ELSE
            pr('Oracle version is 19c', 'WARN',
               'version=' || v_version_full ||
               ' — course baseline is 19c; where a demo needs a 21c/23ai-only' ||
               ' feature it is marked explicitly, but unmarked demos assume 19c behavior.');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            pr('Oracle version is 19c', 'FAIL', 'Could not query v$instance: ' || SQLERRM);
    END;

    -- =====================================================================
    -- CHECK 2: CDB / PDB architecture and current container
    -- =====================================================================
    BEGIN
        SELECT cdb INTO v_cdb FROM v$database;
        v_con_name := SYS_CONTEXT('USERENV', 'CON_NAME');
        v_con_id   := TO_NUMBER(SYS_CONTEXT('USERENV', 'CON_ID'));

        IF v_cdb = 'YES' THEN
            IF v_con_name = 'CDB$ROOT' THEN
                pr('CDB/PDB mode', 'WARN',
                   'Multitenant instance, but this session is connected to CDB$ROOT' ||
                   ' (CON_ID=' || v_con_id || '). PERF_LAB must be created inside a' ||
                   ' PDB (this course''s convention: PERFPDB), not in the root.' ||
                   ' Reconnect with a PDB-qualified connect string before continuing.');
            ELSE
                pr('CDB/PDB mode', 'PASS',
                   'Multitenant instance, connected to PDB ' || v_con_name ||
                   ' (CON_ID=' || v_con_id || ')');
            END IF;
        ELSE
            pr('CDB/PDB mode', 'PASS', 'Non-CDB instance — no container distinction needed');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            pr('CDB/PDB mode', 'FAIL', 'Could not query v$database: ' || SQLERRM);
    END;

    -- =====================================================================
    -- CHECK 3: Database open_mode — must be READ WRITE for setup to proceed
    -- =====================================================================
    BEGIN
        SELECT open_mode INTO v_open_mode FROM v$database;
        IF v_open_mode = 'READ WRITE' THEN
            pr('Database open_mode is READ WRITE', 'PASS', v_open_mode);
        ELSE
            pr('Database open_mode is READ WRITE', 'FAIL',
               'open_mode=' || v_open_mode || ' — setup requires a writable database/PDB.');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            pr('Database open_mode is READ WRITE', 'FAIL', 'Could not query v$database: ' || SQLERRM);
    END;

    -- =====================================================================
    -- CHECK 4: Instance status — must be OPEN
    -- =====================================================================
    BEGIN
        SELECT status INTO v_inst_status FROM v$instance;
        IF v_inst_status = 'OPEN' THEN
            pr('Instance status is OPEN', 'PASS', v_inst_status);
        ELSE
            pr('Instance status is OPEN', 'FAIL', 'status=' || v_inst_status);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            pr('Instance status is OPEN', 'FAIL', 'Could not query v$instance: ' || SQLERRM);
    END;

    -- =====================================================================
    -- CHECK 5: Privileges needed to RUN 01_create_user.sql
    --   (CREATE USER, CREATE TABLESPACE, and the ability to grant
    --    UNLIMITED TABLESPACE / role grants onward to the new user)
    -- =====================================================================
    BEGIN
        SELECT COUNT(*) INTO v_priv_count
        FROM   session_privs
        WHERE  privilege = 'CREATE USER';
        IF v_priv_count > 0 THEN
            pr('Privilege: CREATE USER', 'PASS');
        ELSE
            pr('Privilege: CREATE USER', 'FAIL',
               'Connected account cannot create the PERF_LAB user. Connect as SYSTEM' ||
               ' or another account with the DBA role (or an equivalent direct grant).');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            pr('Privilege: CREATE USER', 'FAIL', 'Could not query session_privs: ' || SQLERRM);
    END;

    BEGIN
        SELECT COUNT(*) INTO v_priv_count
        FROM   session_privs
        WHERE  privilege = 'CREATE TABLESPACE';
        IF v_priv_count > 0 THEN
            pr('Privilege: CREATE TABLESPACE', 'PASS');
        ELSE
            pr('Privilege: CREATE TABLESPACE', 'FAIL',
               'Connected account cannot create PERF_LAB_DATA. Connect as SYSTEM or' ||
               ' another DBA-privileged account, or ask a DBA to pre-create the' ||
               ' tablespace and adjust 01_create_user.sql accordingly.');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            pr('Privilege: CREATE TABLESPACE', 'FAIL', 'Could not query session_privs: ' || SQLERRM);
    END;

    BEGIN
        SELECT COUNT(*) INTO v_priv_count
        FROM   session_roles
        WHERE  role = 'DBA';
        IF v_priv_count > 0 THEN
            pr('DBA role enabled in this session', 'PASS',
               'Sufficient for all grants 01_create_user.sql needs to issue.');
        ELSE
            -- Not fatal by itself — the two granular checks below cover the
            -- specific case that matters most (granting onward SELECT on
            -- V$/DBA_HIST views), but flag this so the instructor knows
            -- 01_create_user.sql may fail partway through on a narrower account.
            pr('DBA role enabled in this session', 'WARN',
               'DBA role not enabled. 01_create_user.sql may still work if the' ||
               ' connected account holds the individual privileges it needs' ||
               ' directly, but a narrowly-privileged account is the most common' ||
               ' cause of a setup script failing partway through. See the two' ||
               ' checks below for the specific privilege that matters most.');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            pr('DBA role enabled in this session', 'WARN', 'Could not query session_roles: ' || SQLERRM);
    END;

    -- =====================================================================
    -- CHECK 6: Ability to grant SELECT on V$/DBA_HIST views onward to
    --          PERF_LAB (needed for the SELECT_CATALOG_ROLE grant in
    --          01_create_user.sql). SELECT_CATALOG_ROLE itself, or
    --          GRANT ANY ROLE / the DBA role, all satisfy this.
    -- =====================================================================
    BEGIN
        SELECT COUNT(*) INTO v_priv_count
        FROM   session_roles
        WHERE  role IN ('DBA', 'SELECT_CATALOG_ROLE');
        IF v_priv_count > 0 THEN
            pr('Can grant SELECT_CATALOG_ROLE onward', 'PASS');
        ELSE
            SELECT COUNT(*) INTO v_priv_count
            FROM   session_privs
            WHERE  privilege = 'GRANT ANY ROLE';
            IF v_priv_count > 0 THEN
                pr('Can grant SELECT_CATALOG_ROLE onward', 'PASS', 'via GRANT ANY ROLE');
            ELSE
                pr('Can grant SELECT_CATALOG_ROLE onward', 'FAIL',
                   'Connected account cannot grant SELECT_CATALOG_ROLE to PERF_LAB.' ||
                   ' This role is how the lab account reads V$/DBA_* views, including' ||
                   ' DBA_HIST_* (see LICENSE DEPENDENCY note in 01_create_user.sql).' ||
                   ' Connect as SYSTEM or a DBA-role account instead.');
            END IF;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            pr('Can grant SELECT_CATALOG_ROLE onward', 'FAIL', 'Could not check: ' || SQLERRM);
    END;

    -- =====================================================================
    -- CHECK 7: DBA_HIST_* accessibility from THIS account (informational —
    --          confirms the dictionary views exist and are queryable here;
    --          it does NOT confirm license entitlement, which is a
    --          contractual matter this script cannot determine).
    -- =====================================================================
    BEGIN
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM dba_hist_snapshot WHERE ROWNUM <= 1' INTO v_dummy;
        pr('DBA_HIST_SNAPSHOT is queryable from this account', 'PASS',
           'LICENSE DEPENDENCY: querying DBA_HIST_* requires the Diagnostics Pack' ||
           ' license on Enterprise Edition — see 01_create_user.sql and the' ||
           ' course design doc before relying on this in a licensed environment.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -942 THEN
                pr('DBA_HIST_SNAPSHOT is queryable from this account', 'WARN',
                   'ORA-00942 — no SELECT privilege on DBA_HIST_SNAPSHOT from this' ||
                   ' account (expected if not connected as a DBA-privileged user;' ||
                   ' 01_create_user.sql will grant this to PERF_LAB separately).');
            ELSE
                pr('DBA_HIST_SNAPSHOT is queryable from this account', 'WARN', SQLERRM);
            END IF;
    END;

    -- =====================================================================
    -- CHECK 8: whether PERF_LAB already exists (informational — 01 handles
    --          re-runs, but flag it here so nobody is surprised).
    -- =====================================================================
    BEGIN
        SELECT COUNT(*) INTO v_dummy FROM dba_users WHERE username = 'PERF_LAB';
        IF v_dummy > 0 THEN
            pr('PERF_LAB user already exists', 'WARN',
               'A PERF_LAB account is already present. 01_create_user.sql does not' ||
               ' drop it automatically — review before re-running setup.');
        ELSE
            pr('PERF_LAB user already exists', 'PASS', 'Not present — clean to create.');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            pr('PERF_LAB user already exists', 'WARN', 'Could not query dba_users: ' || SQLERRM);
    END;

    -- =====================================================================
    -- Summary
    -- =====================================================================
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 80, '-'));
    DBMS_OUTPUT.PUT_LINE('SUMMARY: ' || v_pass_count || ' PASS, ' ||
                          v_warn_count || ' WARN, ' || v_fail_count || ' FAIL');
    IF v_fail_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('RESULT: FAIL — resolve the FAIL item(s) above before running 01_create_user.sql.');
    ELSIF v_warn_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('RESULT: PASS WITH WARNINGS — review the WARN item(s) above; setup can likely proceed.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('RESULT: PASS — environment looks ready for 01_create_user.sql.');
    END IF;
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 80, '-'));
END;
/

PROMPT
PROMPT Environment check complete. Review any WARN/FAIL lines above before proceeding.
PROMPT Next step: 01_create_user.sql (run as the same DBA-privileged account).
PROMPT
