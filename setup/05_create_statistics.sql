-- =============================================================================
-- PERF_LAB Setup — Script 05 of 7
-- 05_create_statistics.sql
--
-- Purpose: gather a complete, correct set of optimizer statistics for the
-- freshly-loaded PERF_LAB schema — table stats, column stats (including
-- histograms on the deliberately skewed columns), and index stats.
--
-- Run connected AS perf_lab, after 04_generate_data.sql:
--   sqlplus perf_lab/<password>@//localhost:1521/PERFPDB @05_create_statistics.sql
--
-- ENVIRONMENT DEPENDENT: DBMS_STATS.GATHER_SCHEMA_STATS on a Standard-tier
-- PERF_LAB (the ~85 million rows across all 10 tables) will typically run
-- from several minutes to well over an hour depending on CPU core count
-- (DEGREE below lets Oracle auto-parallelize this) and storage throughput —
-- the two 20-million-row tables (ORDER_ITEMS, LOG_EVENTS) and the two
-- 10-million-row tables (TRANSACTIONS, SALES) dominate elapsed time, same
-- as they did during 04_generate_data.sql.
--
-- WHY THIS MATTERS FOR THE COURSE, NOT JUST FOR CORRECTNESS: a schema with
-- no stats (or stale/default stats) makes the optimizer's decisions
-- effectively undiagnosable — you cannot teach cardinality estimation,
-- histogram behavior, or plan stability starting from a schema the
-- optimizer has never actually looked at. This script establishes the
-- known-good stats baseline every later day's demo assumes at its start
-- (whatever it does to that baseline afterward, deliberately, is that day's
-- own concern — see the note at the bottom of this script).
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK ON
SET TIMING ON
SET ECHO OFF

PROMPT
PROMPT ================================================================================
PROMPT  PERF_LAB Setup — Step 5: gather optimizer statistics
PROMPT ================================================================================
PROMPT

-- -----------------------------------------------------------------------------
-- METHOD_OPT explained:
--   'FOR ALL COLUMNS SIZE AUTO'
--     — the standard, sensible default: let Oracle decide, per column,
--       whether a histogram is warranted (based on the column's data
--       distribution and, once dayNN demos start running real workloads,
--       its recorded usage in DBA_TAB_COL_STATISTICS / SQL Plan Directives).
--   'FOR COLUMNS SIZE 254 region customer_status'
--     — explicitly FORCES a full (254-bucket) histogram on REGION and
--       CUSTOMER_STATUS regardless of what AUTO would decide on its own.
--       These are the two columns 04_generate_data.sql deliberately skewed
--       (CUSTOMERS: ~80% of rows in 3 of 6 REGION values; an uneven
--       CUSTOMER_STATUS split) specifically so Day 24 (Optimizer &
--       Statistics: cardinality misestimation and histograms) has a real,
--       reproducible skew to diagnose. Forcing the histogram here — rather
--       than trusting AUTO to notice the skew on a first gather — makes
--       Day 24's starting state deterministic across every environment
--       this script is run against.
--   Note: method_opt column names are NOT table-qualified for
--   GATHER_SCHEMA_STATS — 'region' matches CUSTOMERS.REGION and also
--   SALES.REGION (both benefit from a histogram; SALES.REGION is generated
--   as a flat, unskewed distribution in 04_generate_data.sql, so its
--   histogram will simply come back closer to uniform — that's expected
--   and harmless, not a mistake).
-- -----------------------------------------------------------------------------

PROMPT Gathering schema statistics for PERF_LAB (AUTO_SAMPLE_SIZE, forced
PROMPT histograms on REGION / CUSTOMER_STATUS, cascading to indexes) ...

BEGIN
  DBMS_STATS.GATHER_SCHEMA_STATS(
    ownname          => 'PERF_LAB',
    estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
    method_opt       => 'FOR ALL COLUMNS SIZE AUTO FOR COLUMNS SIZE 254 region customer_status',
    degree           => DBMS_STATS.AUTO_DEGREE,
    cascade          => TRUE,           -- also gather index statistics
    granularity      => 'AUTO',         -- global + partition-level stats on ORDERS/SALES
    options          => 'GATHER',       -- gather everything, don't try to skip "unchanged" objects
    no_invalidate    => FALSE           -- invalidate dependent cursors immediately, don't defer
  );
END;
/

PROMPT
PROMPT ---- Verifying: table-level stats landed on every table ----
COLUMN table_name    FORMAT A16
COLUMN num_rows      FORMAT 999,999,999,999
COLUMN last_analyzed FORMAT A20
SELECT table_name, num_rows, blocks, last_analyzed
FROM   user_tables
ORDER  BY table_name;

PROMPT
PROMPT ---- Verifying: histograms landed on the deliberately skewed columns ----
COLUMN column_name FORMAT A18
COLUMN histogram   FORMAT A16
SELECT table_name, column_name, num_distinct, histogram, num_buckets
FROM   user_tab_col_statistics
WHERE  (table_name = 'CUSTOMERS' AND column_name IN ('REGION','CUSTOMER_STATUS'))
   OR  (table_name = 'SALES'     AND column_name = 'REGION')
ORDER  BY table_name, column_name;

PROMPT
PROMPT ---- Verifying: partition-level stats exist on the two partitioned tables ----
COLUMN partition_name FORMAT A20
SELECT table_name, COUNT(*) AS partitions_with_stats
FROM   user_tab_partitions
WHERE  table_name IN ('ORDERS','SALES')
AND    num_rows IS NOT NULL
GROUP  BY table_name
ORDER  BY table_name;

PROMPT
PROMPT ---- Verifying: index stats landed (cascade => TRUE) ----
SELECT COUNT(*) AS indexes_with_stats
FROM   user_indexes
WHERE  num_rows IS NOT NULL;

-- =============================================================================
-- NOTE FOR EVERY LATER dayNN SCRIPT (not something this script needs to
-- guard against): several later days deliberately invalidate, stale-out,
-- lock, or otherwise deliberately corrupt these statistics as PART OF their
-- own demo — that is expected, intentional, and specific to that day's
-- lesson, not a defect in this baseline. Known examples already planned in
-- the course design:
--   - Day 24 (Optimizer & Statistics) explicitly manipulates histograms and
--     stale/locked stats on CUSTOMERS to demonstrate cardinality
--     misestimation and its fix.
--   - Any day using DBMS_STATS.LOCK_TABLE_STATS, SET_TABLE_PREFS, or a
--     manual DELETE/GATHER cycle on a subset of PERF_LAB tables does so in
--     its own setup.sql/demo.sql and is expected to leave those tables'
--     stats different from what this script establishes — and to restore
--     them (or explain why not) in that day's reset.sql.
-- If you need to return the whole schema to this script's known-good
-- baseline after a class has run several such demos, simply re-run this
-- script — GATHER_SCHEMA_STATS with options => 'GATHER' recomputes
-- everything from scratch rather than skipping objects it thinks are
-- already up to date.
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT  Statistics gathered.
PROMPT  Next step: 06_verify_environment.sql
PROMPT ================================================================================
PROMPT
