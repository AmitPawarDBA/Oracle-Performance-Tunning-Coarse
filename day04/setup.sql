-- =====================================================================
-- Day 4 — Architecture Bootcamp II — Storage
-- setup.sql
--
-- Purpose: create a small, DEDICATED tablespace and demo table so the
-- row -> block -> file -> extent trace in demo.sql is clean and
-- reproducible. PERF_LAB's real tables (ORDERS 5M, ORDER_ITEMS 20M,
-- TRANSACTIONS 10M ...) are deliberately NOT used for the first trace
-- because they are partitioned and/or span many extents across
-- multiple datafiles -- great for later days, bad for a first-time
-- "one row, one block, one extent, one file" demonstration.
--
-- This script has two parts:
--   PART 1 — run as a DBA-privileged account (e.g. SYSTEM), connected
--            to the PERFPDB pluggable database (or the target
--            non-CDB instance).
--   PART 2 — run as PERF_LAB.
--
-- ENVIRONMENT DEPENDENT: datafile path in PART 1 must be adjusted to
-- a valid directory on the instructor's/student's lab server before
-- running. Sizes below are intentionally small and fixed (no
-- autoextend on the tablespace itself) so the extent trace stays
-- simple; the DEMO_REDO table's tablespace does autoextend because
-- Part 2 of the demo intentionally generates enough redo to be
-- visible in V$MYSTAT.
-- =====================================================================

-- =====================================================================
-- PART 1 — run as SYSTEM (or another DBA-privileged account)
-- =====================================================================

-- If running against a multitenant 19c instance, connect to the PDB
-- first, e.g.:
--   CONNECT system/<password>@//localhost:1521/PERFPDB
-- (adjust host/port/service to your lab's actual connect string)

PROMPT ===========================================================
PROMPT PART 1 - creating Day 4 dedicated tablespace (run as SYSTEM)
PROMPT ===========================================================

-- Drop leftovers from a previous run of this day, if any (idempotent).
DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM dba_tablespaces WHERE tablespace_name = 'PERF_D4_TS';
  IF v_count > 0 THEN
    EXECUTE IMMEDIATE 'DROP TABLESPACE PERF_D4_TS INCLUDING CONTENTS AND DATAFILES';
  END IF;
END;
/

-- A small, fixed-size, LOCALLY MANAGED, UNIFORM-extent tablespace.
-- UNIFORM SIZE 64K keeps every extent the same size, which makes the
-- extent math in demo.sql easy to follow on a whiteboard: block size
-- (8K, the PERF_LAB default) x 8 blocks = 64K per extent.
--
-- ENVIRONMENT DEPENDENT: change the DATAFILE path below to a real,
-- writable directory in your lab (e.g. an ASM diskgroup '+DATA', or
-- a filesystem path under your instance's datafile destination).
CREATE TABLESPACE perf_d4_ts
  DATAFILE '/u01/app/oracle/oradata/PERFPDB/perf_d4_ts01.dbf'
  SIZE 20M
  AUTOEXTEND OFF
  LOGGING
  EXTENT MANAGEMENT LOCAL UNIFORM SIZE 64K
  SEGMENT SPACE MANAGEMENT AUTO;

-- A second, small tablespace purely for the redo/undo generation demo.
-- This one DOES autoextend a little, because Part 2 of the demo
-- inserts several thousand rows and we do not want the demo to fail
-- on "out of space" mid-lecture.
CREATE TABLESPACE perf_d4_redo_ts
  DATAFILE '/u01/app/oracle/oradata/PERFPDB/perf_d4_redo_ts01.dbf'
  SIZE 20M
  AUTOEXTEND ON NEXT 10M MAXSIZE 200M
  LOGGING
  EXTENT MANAGEMENT LOCAL UNIFORM SIZE 64K
  SEGMENT SPACE MANAGEMENT AUTO;

-- Give PERF_LAB a quota on both (unlimited is fine for a lab schema;
-- tighten in a shared/multi-student environment if needed).
ALTER USER perf_lab QUOTA UNLIMITED ON perf_d4_ts;
ALTER USER perf_lab QUOTA UNLIMITED ON perf_d4_redo_ts;

-- PERF_LAB needs to be able to query V$/GV$ and DBA_* views for this
-- day's dictionary work. If your lab already granted this broadly to
-- PERF_LAB on Day 3, this is a harmless re-grant.
GRANT SELECT_CATALOG_ROLE TO perf_lab;
GRANT SELECT ANY DICTIONARY TO perf_lab;

PROMPT Part 1 complete. Now connect as PERF_LAB and run Part 2 below
PROMPT (either in the same script if your client stays connected as a
PROMPT DBA-capable proxy user, or by reconnecting as PERF_LAB).

-- =====================================================================
-- PART 2 — run as PERF_LAB
-- =====================================================================
-- CONNECT perf_lab/<password>@//localhost:1521/PERFPDB

PROMPT ===========================================================
PROMPT PART 2 - creating Day 4 demo objects (run as PERF_LAB)
PROMPT ===========================================================

-- Clean up any leftovers from a previous run.
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE perf_lab.d4_demo_orders PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF; -- ignore ORA-00942 table not found
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE perf_lab.d4_redo_demo PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

-- ---------------------------------------------------------------------
-- D4_DEMO_ORDERS: the "one clean row" table used for the row -> block
-- trace. Deliberately tiny (200 rows) and given explicit small storage
-- so it lives entirely inside a single extent of the tablespace above
-- -- one extent, one segment, one file, easy to reason about.
-- ---------------------------------------------------------------------
CREATE TABLE perf_lab.d4_demo_orders (
  order_id      NUMBER          NOT NULL,
  customer_name VARCHAR2(50)    NOT NULL,
  order_total   NUMBER(10,2)    NOT NULL,
  order_date    DATE            DEFAULT SYSDATE NOT NULL,
  filler        VARCHAR2(200)   -- pads row size so the block/extent
                                 -- math in demo.sql is easy to see
)
TABLESPACE perf_d4_ts
STORAGE (INITIAL 64K NEXT 64K PCTINCREASE 0);

ALTER TABLE perf_lab.d4_demo_orders ADD CONSTRAINT d4_demo_orders_pk PRIMARY KEY (order_id) USING INDEX TABLESPACE perf_d4_ts;

-- Populate with 200 small, predictable rows.
INSERT INTO perf_lab.d4_demo_orders (order_id, customer_name, order_total, order_date, filler)
SELECT
  LEVEL,
  'Demo Customer ' || LEVEL,
  ROUND(DBMS_RANDOM.VALUE(10, 5000), 2),
  DATE '2026-08-01' + MOD(LEVEL, 20),
  RPAD('x', 100, 'x')
FROM DUAL
CONNECT BY LEVEL <= 200;

COMMIT;

EXEC DBMS_STATS.GATHER_TABLE_STATS('PERF_LAB', 'D4_DEMO_ORDERS');

-- ---------------------------------------------------------------------
-- D4_REDO_DEMO: an empty scratch table used purely to generate a
-- visible, attributable burst of redo and undo during the live demo.
-- Kept separate from D4_DEMO_ORDERS so the row-trace table's extent
-- map stays completely undisturbed by the redo/undo section.
-- ---------------------------------------------------------------------
CREATE TABLE perf_lab.d4_redo_demo (
  id      NUMBER        NOT NULL,
  payload VARCHAR2(500) NOT NULL
)
TABLESPACE perf_d4_redo_ts;

ALTER TABLE perf_lab.d4_redo_demo ADD CONSTRAINT d4_redo_demo_pk PRIMARY KEY (id);

COMMIT;

PROMPT ===========================================================
PROMPT Day 4 setup complete.
PROMPT   Tablespaces : PERF_D4_TS, PERF_D4_REDO_TS
PROMPT   Tables      : PERF_LAB.D4_DEMO_ORDERS (200 rows, 1 extent)
PROMPT                 PERF_LAB.D4_REDO_DEMO   (empty, ready for demo.sql)
PROMPT ===========================================================
