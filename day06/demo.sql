-- =============================================================================
-- Day 06 -- Architecture Bootcamp IV: How Oracle Executes a Statement
-- demo.sql -- the live-demo command sequence
--
-- Format: 8 numbered steps, matching day06-content.md's Practical Demo section.
-- Run setup.sql immediately before this script, in the same session.
--
-- Narration goal for every step: name the exact Day 3 / Day 4 / Day 5
-- architecture piece being touched, not just "run this and look at the
-- output."
--
-- ENVIRONMENT DEPENDENT: exact byte counts, timings, and physical-read
-- counts below depend on hardware, what is already cached from prior runs,
-- and instance configuration. The STRUCTURE of the evidence (LOADS staying
-- at 1, EXECUTIONS incrementing, logical reads happening, a work area being
-- allocated) is what is guaranteed, not the specific numbers.
-- =============================================================================

SET ECHO ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 100

-- -----------------------------------------------------------------------------
-- STEP 1 -- ORIENT
-- Before running anything, confirm where each piece of today's story lives:
--   - Library cache / shared pool   -> part of the SGA (Day 3)
--   - Data dictionary / object stats -> Day 4's segments/extents metadata
--   - Buffer cache                  -> part of the SGA (Day 3)
--   - PGA work areas                -> private per-process memory (Day 3)
--   - The process doing all of it   -> this session's server process (Day 5)
-- -----------------------------------------------------------------------------
PROMPT ------------------------------------------------------------------------
PROMPT STEP 1 -- ORIENT: confirm the architecture pieces we are about to use
PROMPT ------------------------------------------------------------------------

-- Instance-level memory shape (Day 3 callback).
SELECT name, ROUND(bytes / 1024 / 1024) AS mb
FROM   v$sgainfo
WHERE  name IN ('Shared Pool Size', 'Buffer Cache Size', 'Redo Buffers',
                'Maximum SGA Size');

-- This session, and the server process behind it (Day 5 callback).
SELECT s.sid, s.serial#, s.server AS server_process, p.spid AS os_pid
FROM   v$session s
JOIN   v$process p ON p.addr = s.paddr
WHERE  s.sid = SYS_CONTEXT('USERENV', 'SID');

-- Confirm our demo statement is NOT already in the library cache -- this
-- makes the "cold run" in Step 2 a guaranteed hard parse. We tag the SQL
-- text with a fresh, unique marker so it has never been seen before.
COLUMN demo_tag NEW_VALUE demo_tag NOPRINT
SELECT TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISSFF3') AS demo_tag FROM dual;

SELECT COUNT(*) AS should_be_zero
FROM   v$sqlarea
WHERE  sql_text LIKE '%DAY06_' || '&demo_tag' || '%';


-- -----------------------------------------------------------------------------
-- STEP 2 -- COLD RUN (forces a HARD PARSE)
-- The comment /* DAY06_&demo_tag */ makes this exact SQL text unique, so the
-- library cache lookup (Day 3's shared pool) is guaranteed to miss. The
-- server process (Day 5) must therefore: syntax-check, semantic-check
-- (resolve every object/column name against the data dictionary -- Day 4's
-- segment/object metadata), and hand the statement to the optimizer for a
-- full cost-based plan.
-- -----------------------------------------------------------------------------
PROMPT ------------------------------------------------------------------------
PROMPT STEP 2 -- COLD RUN: first-ever execution of this exact SQL text
PROMPT (this must be a HARD PARSE -- the library cache cannot already hold it)
PROMPT ------------------------------------------------------------------------

SELECT /*+ GATHER_PLAN_STATISTICS */ /* DAY06_&demo_tag */
       c.customer_id, c.customer_name, o.order_id, o.order_date,
       SUM(oi.quantity * oi.unit_price) AS order_total
FROM   perf_lab.customers   c
JOIN   perf_lab.orders      o  ON o.customer_id = c.customer_id
JOIN   perf_lab.order_items oi ON oi.order_id   = o.order_id
WHERE  o.order_date BETWEEN DATE '2026-01-01' AND DATE '2026-01-31'
AND    c.region = 'WEST'
GROUP BY c.customer_id, c.customer_name, o.order_id, o.order_date
ORDER BY order_total DESC;


-- -----------------------------------------------------------------------------
-- STEP 3 -- OBSERVE the hard-parse evidence
-- LOADS = 1 is the tell: exactly one hard parse has ever happened for this
-- SQL_ID. PARSE_CALLS = EXECUTIONS = 1 at this point too.
-- -----------------------------------------------------------------------------
PROMPT ------------------------------------------------------------------------
PROMPT STEP 3 -- OBSERVE: V$SQLAREA evidence of the hard parse
PROMPT ------------------------------------------------------------------------

COLUMN sql_id       FORMAT A15
COLUMN sql_text      FORMAT A40 WORD_WRAPPED

SELECT sql_id, loads, parse_calls, executions, first_load_time,
       parsing_schema_name
FROM   v$sqlarea
WHERE  sql_text LIKE '%DAY06_' || '&demo_tag' || '%';

-- Captured via a distinct alias (grab_sql_id), never the plain "sql_id"
-- alias used for display elsewhere in this script and in diagnose.sql --
-- SQL*Plus COLUMN attributes are sticky per column name for the rest of the
-- session, so marking "sql_id" itself NOPRINT here would silently suppress
-- it from every later query (including in scripts run afterward in the same
-- session) that also selects a column called sql_id.
COLUMN grab_sql_id NEW_VALUE demo_sql_id NOPRINT
SELECT sql_id AS grab_sql_id
FROM   v$sqlarea
WHERE  sql_text LIKE '%DAY06_' || '&demo_tag' || '%'
AND    ROWNUM = 1;

PROMPT This SQL_ID for the rest of the demo: &demo_sql_id


-- -----------------------------------------------------------------------------
-- STEP 4 -- WARM RUN (expects a SOFT PARSE)
-- Identical SQL text, same session, run immediately after. The library
-- cache lookup now finds a shareable cursor for this exact SQL_ID, so
-- Oracle SOFT PARSES: it reuses the existing parsed representation and the
-- already-computed plan. The optimizer is not invoked again.
-- -----------------------------------------------------------------------------
PROMPT ------------------------------------------------------------------------
PROMPT STEP 4 -- WARM RUN: identical SQL text, run again
PROMPT (this should be a SOFT PARSE -- library cache lookup hits)
PROMPT ------------------------------------------------------------------------

SELECT /*+ GATHER_PLAN_STATISTICS */ /* DAY06_&demo_tag */
       c.customer_id, c.customer_name, o.order_id, o.order_date,
       SUM(oi.quantity * oi.unit_price) AS order_total
FROM   perf_lab.customers   c
JOIN   perf_lab.orders      o  ON o.customer_id = c.customer_id
JOIN   perf_lab.order_items oi ON oi.order_id   = o.order_id
WHERE  o.order_date BETWEEN DATE '2026-01-01' AND DATE '2026-01-31'
AND    c.region = 'WEST'
GROUP BY c.customer_id, c.customer_name, o.order_id, o.order_date
ORDER BY order_total DESC;


-- -----------------------------------------------------------------------------
-- STEP 5 -- OBSERVE the soft-parse evidence
-- LOADS is still 1 (no new hard parse happened). PARSE_CALLS and EXECUTIONS
-- have both incremented to 2. This is the proof: same plan, reused, cheaper.
-- -----------------------------------------------------------------------------
PROMPT ------------------------------------------------------------------------
PROMPT STEP 5 -- OBSERVE: V$SQLAREA evidence of the soft parse
PROMPT (compare LOADS to Step 3 -- it must be unchanged)
PROMPT ------------------------------------------------------------------------

SELECT sql_id, loads, parse_calls, executions, first_load_time
FROM   v$sqlarea
WHERE  sql_id = '&demo_sql_id';


-- -----------------------------------------------------------------------------
-- STEP 6 -- TRACE BLOCK ACCESS via buffer cache statistics
-- Even on a soft parse, Oracle still has to DO the work: every block the
-- plan needs is requested from the buffer cache (Day 3's SGA) by this
-- session's server process (Day 5). A block already resident is a logical
-- read (cache hit); a block not resident triggers a physical read from the
-- datafiles (Day 4's physical storage) into a free buffer.
-- -----------------------------------------------------------------------------
PROMPT ------------------------------------------------------------------------
PROMPT STEP 6 -- TRACE BLOCK ACCESS: buffer cache logical/physical read deltas
PROMPT ------------------------------------------------------------------------

DECLARE
  l_lreads_before  NUMBER;
  l_preads_before  NUMBER;
  l_lreads_after   NUMBER;
  l_preads_after   NUMBER;
  l_dummy          NUMBER;
BEGIN
  SELECT s.value INTO l_lreads_before
  FROM   v$mystat s JOIN v$statname n ON n.statistic# = s.statistic#
  WHERE  n.name = 'session logical reads';

  SELECT s.value INTO l_preads_before
  FROM   v$mystat s JOIN v$statname n ON n.statistic# = s.statistic#
  WHERE  n.name = 'physical reads';

  -- Run the same statement a third time. Plan is cached (soft parse), but
  -- data must still be fetched block by block through the buffer cache.
  FOR rec IN (
    SELECT /*+ GATHER_PLAN_STATISTICS */ /* DAY06_&demo_tag */
           c.customer_id, c.customer_name, o.order_id, o.order_date,
           SUM(oi.quantity * oi.unit_price) AS order_total
    FROM   perf_lab.customers   c
    JOIN   perf_lab.orders      o  ON o.customer_id = c.customer_id
    JOIN   perf_lab.order_items oi ON oi.order_id   = o.order_id
    WHERE  o.order_date BETWEEN DATE '2026-01-01' AND DATE '2026-01-31'
    AND    c.region = 'WEST'
    GROUP BY c.customer_id, c.customer_name, o.order_id, o.order_date
    ORDER BY order_total DESC
  ) LOOP
    l_dummy := rec.order_id;  -- fetch and discard; only the stats matter here
  END LOOP;

  SELECT s.value INTO l_lreads_after
  FROM   v$mystat s JOIN v$statname n ON n.statistic# = s.statistic#
  WHERE  n.name = 'session logical reads';

  SELECT s.value INTO l_preads_after
  FROM   v$mystat s JOIN v$statname n ON n.statistic# = s.statistic#
  WHERE  n.name = 'physical reads';

  DBMS_OUTPUT.PUT_LINE('Logical reads this execution (buffer cache gets) : '
                        || (l_lreads_after - l_lreads_before));
  DBMS_OUTPUT.PUT_LINE('Physical reads this execution (disk into cache)  : '
                        || (l_preads_after - l_preads_before));
  DBMS_OUTPUT.PUT_LINE('-- ENVIRONMENT DEPENDENT: exact counts depend on what');
  DBMS_OUTPUT.PUT_LINE('-- is already cached from prior runs, and on hardware.');
  DBMS_OUTPUT.PUT_LINE('-- The concept, not the number, is the point: every');
  DBMS_OUTPUT.PUT_LINE('-- row returned required a buffer cache request first.');
END;
/


-- -----------------------------------------------------------------------------
-- STEP 7 -- OBSERVE PGA / work area usage for the sort
-- This query's GROUP BY and ORDER BY need sort work areas, and the hash
-- joins need hash work areas. All of this memory comes out of the server
-- process's own PGA (Day 3: private per-process memory, unlike the shared
-- SGA), sized automatically under PGA_AGGREGATE_TARGET.
-- -----------------------------------------------------------------------------
PROMPT ------------------------------------------------------------------------
PROMPT STEP 7 -- OBSERVE: PGA work areas for this statement's sort/hash steps
PROMPT ------------------------------------------------------------------------

COLUMN operation_type FORMAT A18
SELECT wa.operation_type, wa.policy, wa.last_memory_used,
       wa.estimated_optimal_size, wa.optimal_executions,
       wa.onepass_executions, wa.multipasses_executions
FROM   v$sql_workarea wa
WHERE  wa.sql_id = '&demo_sql_id';

-- Instance-level PGA shape, for context (Day 3 callback: PGA_AGGREGATE_TARGET
-- governs automatic sizing of exactly the work areas listed above).
SELECT name, ROUND(value / 1024 / 1024) AS mb
FROM   v$pgastat
WHERE  name IN ('aggregate PGA target parameter', 'total PGA allocated',
                'total PGA used for auto workareas');


-- -----------------------------------------------------------------------------
-- STEP 8 -- TIE IT ALL BACK to Days 3-5, then RESET this session
-- -----------------------------------------------------------------------------
PROMPT ------------------------------------------------------------------------
PROMPT STEP 8 -- TIE BACK to the Architecture Bootcamp, then reset
PROMPT ------------------------------------------------------------------------

BEGIN
  DBMS_OUTPUT.PUT_LINE('PARSE               -> library cache / shared pool (Day 3 SGA)');
  DBMS_OUTPUT.PUT_LINE('  hard parse only   -> data dictionary semantic check (Day 4 segments/objects)');
  DBMS_OUTPUT.PUT_LINE('OPTIMIZE            -> CBO reads object/column stats from the data dictionary (Day 4)');
  DBMS_OUTPUT.PUT_LINE('ROW SOURCE GEN      -> still inside the library cache (Day 3)');
  DBMS_OUTPUT.PUT_LINE('EXECUTE             -> the server process (Day 5) does the work:');
  DBMS_OUTPUT.PUT_LINE('                       - reads blocks via the buffer cache (Day 3 SGA)');
  DBMS_OUTPUT.PUT_LINE('                       - sorts/hashes using its own PGA (Day 3)');
  DBMS_OUTPUT.PUT_LINE('                       - (DML would also touch redo/undo + LGWR/DBWn -- Day 4/5)');
  DBMS_OUTPUT.PUT_LINE('FETCH               -> server process (Day 5) returns rows over the session');
  DBMS_OUTPUT.PUT_LINE('                       connection first traced from listener to server on Day 5');
END;
/

-- Session-level reset: clear the module/action tag and switch statistics
-- level back to default so this session does not carry demo-only overhead
-- into whatever runs next. This does NOT touch the shared pool or any other
-- session -- see reset.sql for the full, instructor-run, cross-cohort reset.
ALTER SESSION SET STATISTICS_LEVEL = TYPICAL;

BEGIN
  DBMS_APPLICATION_INFO.SET_MODULE(module_name => NULL, action_name => NULL);
END;
/

PROMPT ================================================================
PROMPT Demo complete. SQL_ID used throughout: &demo_sql_id
PROMPT This session has been reset to defaults.
PROMPT For a full shared-pool-level reset before the next cohort run,
PROMPT see reset.sql (instructor-run, requires SYSTEM/DBA privileges).
PROMPT ================================================================
