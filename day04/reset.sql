-- =====================================================================
-- Day 4 — Architecture Bootcamp II — Storage
-- reset.sql — return Day 4's demo objects to a pristine, just-set-up
-- state WITHOUT a full cleanup+re-setup round trip. Use this between
-- class sections (e.g. before re-running demo.sql for a second
-- group) when you want fresh data but do not want to drop and
-- recreate the tablespaces/datafiles themselves.
--
-- For a full teardown instead, use cleanup.sql. For first-time
-- creation, use setup.sql. This script assumes setup.sql has already
-- run at least once in this environment.
--
-- Run as PERF_LAB.
-- =====================================================================

PROMPT ===========================================================
PROMPT Resetting D4_DEMO_ORDERS to its original 200-row baseline
PROMPT ===========================================================

TRUNCATE TABLE perf_lab.d4_demo_orders;

-- Note: TRUNCATE assigns a NEW data_object_id to the table. If you
-- ran demo.sql Step A3 before this reset and wrote the old
-- data_object_id on a whiteboard, point out that after this TRUNCATE
-- it will be a DIFFERENT number -- a good, concrete illustration of
-- what TRUNCATE actually does at the segment level (versus DELETE,
-- which does not reallocate the segment or change the object id).

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

PROMPT ===========================================================
PROMPT Resetting D4_REDO_DEMO to empty
PROMPT ===========================================================

TRUNCATE TABLE perf_lab.d4_redo_demo;

PROMPT ===========================================================
PROMPT Day 4 reset complete. demo.sql / fix.sql / validate.sql can
PROMPT be re-run from the top.
PROMPT ===========================================================
