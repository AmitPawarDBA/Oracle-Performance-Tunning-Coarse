-- =============================================================================
-- Day 06 -- Architecture Bootcamp IV: How Oracle Executes a Statement
-- diagnose.sql -- supporting investigative queries
--
-- Purpose: these are the queries used to BUILD the "which architecture piece
-- is this touching" narration during the demo and the Real-World Scenario --
-- run them any time after demo.sql Step 3 (once &demo_sql_id exists) to dig
-- one level deeper into each phase's evidence.
--
-- This is deliberately still introductory: V$SQL_PLAN is queried for its
-- raw plan-tree shape only (ID/OPERATION/OBJECT_NAME), not for cost-based
-- plan-reading technique -- that skill is built starting Day 21-22.
--
-- Run after demo.sql, in the same session (so &demo_sql_id is still defined),
-- or re-derive &demo_sql_id with the lookup query at the top.
-- =============================================================================

SET LINESIZE 200
SET PAGESIZE 100
COLUMN sql_id        FORMAT A15
COLUMN sql_text       FORMAT A50 WORD_WRAPPED

-- If &demo_sql_id is not already defined in this session (e.g. you are
-- running diagnose.sql on its own), recover it here first:
-- COLUMN sql_id NEW_VALUE demo_sql_id NOPRINT
-- SELECT sql_id FROM v$sqlarea WHERE sql_text LIKE '%DAY06_%' AND ROWNUM = 1;


-- -----------------------------------------------------------------------------
-- 1. PARSE PHASE EVIDENCE -- library cache / shared pool (Day 3)
-- -----------------------------------------------------------------------------
PROMPT ==== 1. PARSE evidence: library cache cursor state (Day 3 SGA) ====

SELECT sql_id, child_number, loads, parse_calls, executions,
       invalidations, is_shareable, is_obsolete, first_load_time
FROM   v$sql
WHERE  sql_id = '&demo_sql_id'
ORDER BY child_number;

-- Why a child cursor might NOT be shared with another, textually-identical
-- statement (bind mismatch, optimizer environment mismatch, etc.) -- a
-- preview of cursor-sharing depth that Day 19 covers properly.
SELECT sql_id, child_number, reason
FROM   v$sql_shared_cursor
WHERE  sql_id = '&demo_sql_id';


-- -----------------------------------------------------------------------------
-- 2. OPTIMIZE PHASE EVIDENCE -- data dictionary / object stats (Day 4)
-- -----------------------------------------------------------------------------
PROMPT ==== 2. OPTIMIZE evidence: the dictionary/segment metadata the CBO used (Day 4) ====

COLUMN segment_name  FORMAT A20
COLUMN segment_type  FORMAT A14
COLUMN partition_name FORMAT A20

SELECT segment_name, partition_name, segment_type, tablespace_name,
       bytes / 1024 / 1024 AS mb, blocks, extents
FROM   dba_segments
WHERE  owner = 'PERF_LAB'
AND    segment_name IN ('CUSTOMERS', 'ORDERS', 'ORDER_ITEMS')
ORDER BY segment_name, partition_name;

-- Object/column statistics the optimizer read to estimate cardinality --
-- same dictionary views Day 4 used to explain "where does my data live."
SELECT table_name, num_rows, blocks, last_analyzed
FROM   dba_tab_statistics
WHERE  owner = 'PERF_LAB'
AND    table_name IN ('CUSTOMERS', 'ORDERS', 'ORDER_ITEMS')
AND    partition_name IS NULL
ORDER BY table_name;


-- -----------------------------------------------------------------------------
-- 3. THE PLAN ITSELF -- introductory only (full plan-reading is Day 21-22)
-- -----------------------------------------------------------------------------
PROMPT ==== 3. The chosen plan shape -- evidence only, not analysis (Day 21-22 job) ====

COLUMN operation    FORMAT A18
COLUMN options       FORMAT A18
COLUMN object_name   FORMAT A18

SELECT id, parent_id, operation, options, object_name, cost, cardinality
FROM   v$sql_plan
WHERE  sql_id = '&demo_sql_id'
AND    child_number = 0
ORDER BY id;


-- -----------------------------------------------------------------------------
-- 4. EXECUTE PHASE EVIDENCE -- the server process (Day 5) and the buffer
--    cache / PGA it touches (Day 3)
-- -----------------------------------------------------------------------------
PROMPT ==== 4. EXECUTE evidence: this session's server process (Day 5) ====

SELECT s.sid, s.serial#, s.server AS server_process, s.status,
       p.spid AS os_pid, p.pga_used_mem / 1024 AS pga_used_kb,
       p.pga_alloc_mem / 1024 AS pga_alloc_kb
FROM   v$session s
JOIN   v$process p ON p.addr = s.paddr
WHERE  s.sid = SYS_CONTEXT('USERENV', 'SID');

PROMPT ==== 4b. Session-level buffer cache / sort statistics (Day 3 SGA + PGA) ====

COLUMN name FORMAT A34
SELECT n.name, s.value
FROM   v$mystat s JOIN v$statname n ON n.statistic# = s.statistic#
WHERE  n.name IN ('session logical reads', 'physical reads',
                   'physical reads cache', 'db block gets',
                   'consistent gets', 'sorts (memory)', 'sorts (disk)',
                   'workarea executions - optimal',
                   'workarea executions - onepass',
                   'workarea executions - multipass');


-- -----------------------------------------------------------------------------
-- 5. FETCH / WAIT EVIDENCE -- a first, light look at V$SESSION_EVENT
--    (the deep wait-event toolkit starts Day 10 -- this is only enough to
--    show that fetch time shows up as recorded wait/CPU history, not to
--    interpret it yet)
-- -----------------------------------------------------------------------------
PROMPT ==== 5. FETCH/WAIT evidence: this session's recorded events so far (light touch -- Day 10 goes deep) ====

COLUMN event FORMAT A32
SELECT event, total_waits, time_waited, average_wait
FROM   v$session_event
WHERE  sid = SYS_CONTEXT('USERENV', 'SID')
ORDER BY time_waited DESC
FETCH FIRST 10 ROWS ONLY;
