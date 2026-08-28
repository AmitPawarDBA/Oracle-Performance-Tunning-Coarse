-- =====================================================================
-- Day 4 — Architecture Bootcamp II — Storage
-- demo.sql  — the live in-class query sequence
--
-- Run as PERF_LAB unless a step says otherwise. Run after setup.sql.
--
-- PART A: trace one row from SELECT down to its physical block, file
--         and extent.
-- PART B: watch a single transaction generate redo and undo, live.
-- PART C: read consistency — prove a long-running query sees a
--         stable snapshot even while another session commits changes.
--         (PART C needs a SECOND session/window — marked clearly.)
--
-- ENVIRONMENT DEPENDENT: every byte count, block count and timing
-- number this script prints depends on block size, storage layout,
-- and instance load. Run it live and read YOUR numbers — do not
-- assume they will match any number written here.
-- =====================================================================


-- #######################################################################
-- PART A — Row -> ROWID -> Block -> File -> Extent
-- #######################################################################

PROMPT ===================================================================
PROMPT STEP A1 - Pick one row and look at its ROWID
PROMPT ===================================================================

SET LINESIZE 160
SET PAGESIZE 50
COLUMN customer_name FORMAT A20
COLUMN row_id FORMAT A20

SELECT order_id,
       customer_name,
       order_total,
       ROWID AS row_id
FROM   perf_lab.d4_demo_orders
WHERE  order_id = 42;

-- A ROWID is not a random string. Oracle's "extended ROWID" format
-- encodes, in order: the data object number, the relative file number
-- (relative to the tablespace), the block number within that file,
-- and the row number within that block: OOOOOOFFFBBBBBBRRR (base64
-- encoded). DBMS_ROWID decodes each piece below.


PROMPT ===================================================================
PROMPT STEP A2 - Decode the ROWID with DBMS_ROWID
PROMPT ===================================================================

SELECT
  ROWID                                                        AS row_id,
  DBMS_ROWID.ROWID_OBJECT(ROWID)                                AS data_object_id,
  DBMS_ROWID.ROWID_RELATIVE_FNO(ROWID)                          AS relative_file_no,
  DBMS_ROWID.ROWID_TO_ABSOLUTE_FNO(ROWID, 'PERF_LAB',
                                    'D4_DEMO_ORDERS')            AS absolute_file_no,
  DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID)                          AS block_no,
  DBMS_ROWID.ROWID_ROW_NUMBER(ROWID)                            AS row_no_in_block
FROM perf_lab.d4_demo_orders
WHERE order_id = 42;

-- Talking point: relative_file_no is relative to the TABLESPACE, not
-- the whole database -- that is exactly why the ROWID format needs
-- ROWID_TO_ABSOLUTE_FNO to get a file number you can join straight
-- against DBA_DATA_FILES.FILE_ID.


PROMPT ===================================================================
PROMPT STEP A3 - Confirm the data object id belongs to our table
PROMPT ===================================================================

SELECT owner, object_name, object_id, data_object_id, object_type
FROM   dba_objects
WHERE  owner = 'PERF_LAB'
AND    object_name = 'D4_DEMO_ORDERS';

-- object_id and data_object_id are usually equal for a simple heap
-- table that has never been TRUNCATEd/rebuilt -- point this out, and
-- mention that a TRUNCATE assigns a NEW data_object_id, which is
-- exactly why old ROWIDs become meaningless after a truncate.


PROMPT ===================================================================
PROMPT STEP A4 - Find the extent that owns that block (DBA_EXTENTS)
PROMPT ===================================================================

-- We plug in the absolute file number and block number decoded above.
-- (In a live class, have a student read the numbers off Step A2's
-- output and type them into this WHERE clause by hand -- that hands-on
-- substitution is the moment the architecture "clicks.")

SELECT owner,
       segment_name,
       segment_type,
       tablespace_name,
       extent_id,
       file_id,
       block_id          AS extent_start_block,
       blocks            AS blocks_in_extent,
       bytes             AS extent_bytes
FROM   dba_extents
WHERE  owner       = 'PERF_LAB'
AND    segment_name = 'D4_DEMO_ORDERS'
AND    file_id      = DBMS_ROWID.ROWID_TO_ABSOLUTE_FNO(
                         (SELECT ROWID FROM perf_lab.d4_demo_orders WHERE order_id = 42),
                         'PERF_LAB', 'D4_DEMO_ORDERS')
AND    DBMS_ROWID.ROWID_BLOCK_NUMBER(
         (SELECT ROWID FROM perf_lab.d4_demo_orders WHERE order_id = 42)
       ) BETWEEN block_id AND block_id + blocks - 1;

-- Talking point: because setup.sql used UNIFORM SIZE 64K extents on
-- an 8K block size, blocks_in_extent should read 8 and extent_bytes
-- should read 65536 -- tie the number on screen directly back to the
-- tablespace DDL the students just ran.


PROMPT ===================================================================
PROMPT STEP A5 - Find the physical datafile behind that extent
PROMPT ===================================================================

SELECT file_id,
       file_name,
       tablespace_name,
       ROUND(bytes/1024/1024)   AS size_mb,
       autoextensible,
       status
FROM   dba_data_files
WHERE  tablespace_name = 'PERF_D4_TS';

-- This is the bottom of the hierarchy: an actual OS file on disk.
-- Everything above this (block, extent, segment, tablespace) is
-- Oracle's own bookkeeping ON TOP OF this one physical file.


PROMPT ===================================================================
PROMPT STEP A6 - Same story, top-down: tablespace -> segment -> extents
PROMPT ===================================================================

SELECT tablespace_name, status, contents, extent_management, allocation_type
FROM   dba_tablespaces
WHERE  tablespace_name = 'PERF_D4_TS';

SELECT owner, segment_name, segment_type, tablespace_name,
       bytes/1024 AS size_kb, extents, blocks
FROM   dba_segments
WHERE  owner = 'PERF_LAB'
AND    segment_name = 'D4_DEMO_ORDERS';

SELECT extent_id, file_id, block_id, blocks, bytes
FROM   dba_extents
WHERE  owner = 'PERF_LAB'
AND    segment_name = 'D4_DEMO_ORDERS'
ORDER BY extent_id;

-- Talking point: DBA_SEGMENTS.EXTENTS should match the row count of
-- the DBA_EXTENTS query directly above it -- one number, verified two
-- ways. This is the "top-down" half: tablespace -> segment -> extents
-- -> (implicitly) blocks, meeting the "bottom-up" ROWID trace from
-- Steps A1-A5 in the middle.


-- #######################################################################
-- PART B — Watch one transaction generate redo and undo, live
-- #######################################################################

PROMPT ===================================================================
PROMPT STEP B1 - Baseline: this session's redo/undo-related stats, before
PROMPT ===================================================================

COLUMN name FORMAT A32
COLUMN value FORMAT 999,999,999,999

SELECT sn.name, ms.value
FROM   v$mystat ms
JOIN   v$statname sn ON sn.statistic# = ms.statistic#
WHERE  sn.name IN ('redo size', 'redo entries', 'user commits',
                    'undo change vector size', 'db block changes')
ORDER  BY sn.name;

-- Keep this output visible (screenshot or write the numbers down) --
-- we diff against it in Step B4.


PROMPT ===================================================================
PROMPT STEP B2 - Start a transaction, do NOT commit yet
PROMPT ===================================================================

INSERT INTO perf_lab.d4_redo_demo (id, payload)
SELECT LEVEL, RPAD('redo-undo-demo-row-', 400, 'x') || LEVEL
FROM   DUAL
CONNECT BY LEVEL <= 5000;

-- Do NOT commit yet. The transaction is still open.


PROMPT ===================================================================
PROMPT STEP B3 - While uncommitted: inspect V$TRANSACTION for this session
PROMPT ===================================================================

SELECT s.sid, s.serial#,
       t.xidusn, t.xidslot, t.xidsqn,
       t.status, t.used_ublk, t.used_urec,
       t.start_time
FROM   v$transaction t
JOIN   v$session s ON s.taddr = t.addr
WHERE  s.sid = SYS_CONTEXT('USERENV', 'SID');

-- Talking point: USED_UBLK/USED_UREC prove undo is being generated
-- RIGHT NOW, for an INSERT, before any error and before any ROLLBACK
-- is even a possibility yet. Undo exists from the moment the
-- transaction starts making changes -- it is not something that only
-- appears "in case you roll back."

-- Which undo segment is backing this transaction:
SELECT r.segment_name, r.status, r.tablespace_name
FROM   v$rollstat rs
JOIN   dba_rollback_segs r ON r.segment_id = rs.usn
WHERE  rs.usn = (SELECT xidusn FROM v$transaction t
                 JOIN v$session s ON s.taddr = t.addr
                 WHERE s.sid = SYS_CONTEXT('USERENV', 'SID'));


PROMPT ===================================================================
PROMPT STEP B4 - Commit, then diff the redo/undo stats against Step B1
PROMPT ===================================================================

COMMIT;

SELECT sn.name, ms.value
FROM   v$mystat ms
JOIN   v$statname sn ON sn.statistic# = ms.statistic#
WHERE  sn.name IN ('redo size', 'redo entries', 'user commits',
                    'undo change vector size', 'db block changes')
ORDER  BY sn.name;

-- Talking point: 'redo size' should have grown by roughly the volume
-- of change vectors generated by 5,000 row inserts (ENVIRONMENT
-- DEPENDENT — exact bytes vary by block size, row length, and
-- whether this is the only activity in the instance right now).
-- 'user commits' should have grown by exactly 1. Note that 'redo
-- entries' and 'undo change vector size' both grew from the SAME
-- statement -- the INSERT wrote BOTH a redo change vector (to make
-- the change durable) AND an undo change vector (to make the change
-- reversible/read-consistent), and the undo change vector's own
-- creation was ITSELF protected by redo. This is the single most
-- important physical fact to land today: undo blocks are redo-
-- protected too.


PROMPT ===================================================================
PROMPT STEP B5 - After commit: V$TRANSACTION no longer shows this txn
PROMPT ===================================================================

SELECT COUNT(*) AS active_txn_rows_for_my_session
FROM   v$transaction t
JOIN   v$session s ON s.taddr = t.addr
WHERE  s.sid = SYS_CONTEXT('USERENV', 'SID');

-- Expect 0. Once committed, the transaction slot is freed for reuse.
-- The undo DATA that transaction wrote, however, is NOT thrown away
-- immediately -- it stays in the undo tablespace, subject to
-- UNDO_RETENTION, precisely so that OTHER sessions' still-running
-- queries can keep reading a consistent "before" image if they need
-- to. That is Part C.


PROMPT ===================================================================
PROMPT STEP B6 - Zoom out: recent system-wide undo activity
PROMPT ===================================================================

COLUMN begin_time FORMAT A20
COLUMN end_time   FORMAT A20

SELECT TO_CHAR(begin_time, 'HH24:MI:SS') AS begin_time,
       TO_CHAR(end_time,   'HH24:MI:SS') AS end_time,
       undoblks,
       txncount,
       maxquerylen,
       ssolderrcnt AS snapshot_too_old_errors
FROM   v$undostat
ORDER  BY begin_time DESC
FETCH FIRST 5 ROWS ONLY;

-- V$UNDOSTAT is a 10-minute-bucketed instance-wide history (not
-- per-session). At this early stage, just orient students to what
-- each column MEANS: UNDOBLKS = undo blocks consumed in that
-- 10-minute window, TXNCOUNT = transactions in that window,
-- MAXQUERYLEN = the longest-running query (seconds) that needed undo
-- for consistency during that window, SSOLDERRCNT = how many times a
-- query in that window failed with ORA-01555 "snapshot too old"
-- because the undo it needed had already been overwritten. This view
-- comes back properly on Day 30 (I/O) and later tuning days -- today
-- it is architecture only.


-- #######################################################################
-- PART C — Read consistency: a query sees a stable snapshot
-- (needs a SECOND session — open a second SQL*Plus/SQLcl window)
-- #######################################################################

PROMPT ===================================================================
PROMPT STEP C - SESSION A: start a query that reads the table slowly
PROMPT ===================================================================
-- In SESSION A, run this first so it is mid-flight when Session B commits:
--
--   SELECT order_id, customer_name, order_total,
--          DBMS_LOCK.SLEEP(1) AS pause   -- artificial delay, illustration only
--   FROM   perf_lab.d4_demo_orders
--   ORDER  BY order_id;
--
-- (DBMS_LOCK.SLEEP requires EXECUTE on DBMS_LOCK; if not granted,
-- simply narrate this step instead of running it live -- the SQL
-- below in SESSION B is the part that matters.)

PROMPT ===================================================================
PROMPT STEP C - SESSION B: while A is still running, update and COMMIT
PROMPT ===================================================================
-- In a SECOND window, connected as PERF_LAB, run:
--
--   UPDATE perf_lab.d4_demo_orders
--   SET    order_total = order_total + 100000
--   WHERE  order_id = 42;
--   COMMIT;
--
-- Session A's query, if it has not yet reached order_id = 42's block,
-- will STILL return the ORIGINAL order_total for order_id 42 when it
-- gets there -- not the +100000 value Session B just committed.
-- Oracle reconstructs the block as it looked at the moment Session
-- A's query STARTED, using undo, even though the data BLOCK on disk
-- has already been changed by Session B. This is read consistency,
-- and it is why "undo is just for rollback" is a myth: this entire
-- demonstration involves ZERO rollbacks. Undo is being read to serve
-- a query, not to reverse a transaction.

PROMPT ===================================================================
PROMPT STEP C - Confirm the final committed value once A finishes
PROMPT ===================================================================

SELECT order_id, customer_name, order_total
FROM   perf_lab.d4_demo_orders
WHERE  order_id = 42;

-- Expect the +100000 value now — Session A's snapshot only applied
-- WHILE that query was running; a brand-new query sees current data.
