-- =============================================================================
-- PERF_LAB Setup — rebuild_from_scratch.sql
--
-- Purpose: completely tear down the PERF_LAB schema, its tablespace, and its
-- user account, so 01_create_user.sql through 06_verify_environment.sql can
-- be re-run from a genuinely empty starting point. This is the environment-
-- level equivalent of each day's cleanup.sql — use it when you want to test
-- the FULL lab build (not just one day's demo) more than once: after
-- changing 04_generate_data.sql's scale factor, after editing table DDL,
-- or simply to rehearse the whole build end to end before a cohort starts.
--
-- 01_create_user.sql and 02_create_tables.sql are deliberately NOT
-- idempotent on their own (rebuilding a 20M+ row schema is expensive, so
-- they assume a clean slate rather than silently dropping-and-recreating
-- on every run) — this script IS that "drop everything" step, run once,
-- explicitly, before you re-run 01 through 06.
--
-- Run connected as a DBA-privileged account (e.g. SYSTEM), against the
-- same PDB (PERFPDB by convention) the rest of setup/ uses.
--
-- WARNING: this is destructive. It drops the PERF_LAB user (CASCADE — every
-- table, index, procedure, and row it owns) and the PERF_LAB_DATA
-- tablespace (INCLUDING CONTENTS AND DATAFILES — the actual datafile on
-- disk is deleted). There is no confirmation prompt by design, so it can be
-- scripted/automated — do not run this against an environment you did not
-- mean to wipe. Never run this against anything but a disposable training
-- lab instance.
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK ON

PROMPT ================================================================================
PROMPT  PERF_LAB rebuild: dropping PERF_LAB user and PERF_LAB_DATA tablespace
PROMPT ================================================================================

-- 1. Drop the user (and everything it owns) if it exists.
DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM dba_users WHERE username = 'PERF_LAB';
    IF v_count > 0 THEN
        EXECUTE IMMEDIATE 'DROP USER perf_lab CASCADE';
        DBMS_OUTPUT.PUT_LINE('Dropped user PERF_LAB (CASCADE).');
    ELSE
        DBMS_OUTPUT.PUT_LINE('User PERF_LAB does not exist — nothing to drop.');
    END IF;
END;
/

-- 2. Drop the tablespace (and its datafiles on disk) if it exists.
--    A DROP USER CASCADE above does NOT drop the tablespace itself — only
--    the objects inside it — so this is a separate, necessary step.
DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM dba_tablespaces WHERE tablespace_name = 'PERF_LAB_DATA';
    IF v_count > 0 THEN
        EXECUTE IMMEDIATE 'DROP TABLESPACE perf_lab_data INCLUDING CONTENTS AND DATAFILES';
        DBMS_OUTPUT.PUT_LINE('Dropped tablespace PERF_LAB_DATA (including contents and datafiles).');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Tablespace PERF_LAB_DATA does not exist — nothing to drop.');
    END IF;
END;
/

-- 3. Confirm clean slate.
SELECT COUNT(*) AS perf_lab_user_remaining FROM dba_users WHERE username = 'PERF_LAB';
SELECT COUNT(*) AS perf_lab_data_ts_remaining FROM dba_tablespaces WHERE tablespace_name = 'PERF_LAB_DATA';
-- Expected: both queries return 0.

PROMPT
PROMPT ================================================================================
PROMPT  Rebuild teardown complete. To rebuild the environment, run in order:
PROMPT    @01_create_user.sql
PROMPT    @02_create_tables.sql   (connect as PERF_LAB)
PROMPT    @03_create_indexes.sql  (connect as PERF_LAB)
PROMPT    @04_generate_data.sql   (connect as PERF_LAB)
PROMPT    @05_create_statistics.sql (connect as PERF_LAB)
PROMPT    @06_verify_environment.sql (connect as PERF_LAB)
PROMPT ================================================================================
