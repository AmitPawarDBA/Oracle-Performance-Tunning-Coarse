-- =====================================================================
-- Day 4 — Architecture Bootcamp II — Storage
-- cleanup.sql — remove Day 4's dedicated objects, return PERF_LAB to
-- its baseline state. Run at the END of the day (or before moving on
-- to Day 5) once no further re-runs of demo.sql/validate.sql are
-- needed this session.
--
-- PART 1 runs as PERF_LAB. PART 2 runs as SYSTEM (or another
-- DBA-privileged account) and physically removes the datafiles.
-- =====================================================================

PROMPT ===========================================================
PROMPT PART 1 - drop Day 4 tables (run as PERF_LAB)
PROMPT ===========================================================

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE perf_lab.d4_demo_orders PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE perf_lab.d4_redo_demo PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

PROMPT ===========================================================
PROMPT PART 2 - drop Day 4 tablespaces and datafiles (run as SYSTEM)
PROMPT ===========================================================
-- CONNECT system/<password>@//localhost:1521/PERFPDB

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLESPACE perf_d4_ts INCLUDING CONTENTS AND DATAFILES';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -959 THEN RAISE; END IF; -- ORA-00959 tablespace does not exist
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLESPACE perf_d4_redo_ts INCLUDING CONTENTS AND DATAFILES';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -959 THEN RAISE; END IF;
END;
/

PROMPT ===========================================================
PROMPT Day 4 cleanup complete. PERF_LAB core schema (ORDERS,
PROMPT ORDER_ITEMS, CUSTOMERS, TRANSACTIONS, ...) is untouched --
PROMPT only this day's dedicated demo objects were removed.
PROMPT ===========================================================
