-- =============================================================================
-- Day 2 — Systematic Investigation: From Symptom to SQL
-- diagnose.sql — the reusable investigation chain
--
--   active sessions -> rule out false leads -> expensive SQL -> wait event
--   -> execution plan -> hypothesis
--
-- Every query here uses ONLY views available at this point in the course:
-- V$SESSION, V$SQL, V$SQLAREA, V$SESSION_WAIT, V$ACTIVE_SESSION_HISTORY,
-- V$LOCK, plus a basic DBMS_XPLAN.DISPLAY_CURSOR call. No AWR/ASH HISTORY,
-- no deep join-method plan reading — that comes in later stages.
-- =============================================================================


-- =============================================================================
-- CHAIN STEP A — Who, exactly, is active right now, and what are they doing?
-- =============================================================================
-- This is the query every investigation starts with. SID, username, status,
-- wait class/event, and the SQL_ID currently executing (or last executed).
SELECT s.sid, s.serial#, s.username, s.status,
       s.module, s.action,
       NVL(s.wait_class, 'ON CPU') AS wait_class,
       s.event,
       s.blocking_session,
       s.sql_id
FROM   v$session s
WHERE  s.username = 'PERF_LAB'
AND    s.type     = 'USER'
AND    s.status   = 'ACTIVE'
ORDER  BY s.wait_class NULLS FIRST, s.sid;

-- First read of the room: dozens of PERF_LAB sessions, module
-- ORDER_LOOKUP_SCREEN, most sitting in the same wait_class, and — importantly
-- — BLOCKING_SESSION is empty for all of them. Keep that observation; it
-- matters in Step B.


-- =============================================================================
-- CHAIN STEP B — FALSE LEAD #1: "sessions are stuck, must be locking"
-- =============================================================================
-- A very natural first guess when you see 25 sessions all "stuck" on the same
-- table: someone must be blocking everyone else. Check it properly instead of
-- assuming it.
SELECT s.sid, s.serial#, s.blocking_session, s.event
FROM   v$session s
WHERE  s.username = 'PERF_LAB'
AND    s.type     = 'USER'
AND    s.blocking_session IS NOT NULL;

-- Also check the lock table directly for TX (row lock) enqueues, the
-- classic signature of real blocking.
SELECT l.sid, l.type, l.lmode, l.request, l.block
FROM   v$lock l
JOIN   v$session s ON s.sid = l.sid
WHERE  s.username = 'PERF_LAB'
AND    l.type IN ('TX', 'TM')
AND    (l.block > 0 OR l.request > 0);

-- RESULT: zero rows both times. No session is blocked waiting on another
-- session's lock. FALSE LEAD #1 RULED OUT — this is not a locking problem.
-- (If this HAD returned rows, the investigation would branch toward Day 18's
-- concurrency/locking material instead of continuing below.)


-- =============================================================================
-- CHAIN STEP C — FALSE LEAD #2: "maybe it's the network / app tier"
-- =============================================================================
-- Second natural guess when a screen is "slow": blame the network or the
-- app server before the database. Check what wait class actually dominates.
SELECT NVL(wait_class, 'ON CPU') AS wait_class, COUNT(*) AS session_count
FROM   v$session
WHERE  username = 'PERF_LAB'
AND    type     = 'USER'
AND    status   = 'ACTIVE'
GROUP  BY wait_class
ORDER  BY session_count DESC;

-- RESULT: the dominant wait_class is 'User I/O' (events like
-- 'db file scattered read' / 'direct path read'), not 'Network' and not idle
-- 'SQL*Net message from client'. If the sessions were network-bound we would
-- see them mostly idle on SQL*Net waits instead. FALSE LEAD #2 RULED OUT —
-- this is real database work, not a network symptom being misread as a DB
-- problem.


-- =============================================================================
-- CHAIN STEP D — Which SQL is actually responsible?
-- =============================================================================
-- Join the active sessions back to V$SQL on SQL_ID to find out what
-- statement is behind all that User I/O wait time.
SELECT s.sql_id, COUNT(*) AS active_session_count,
       SUBSTR(q.sql_text, 1, 60) AS sql_text_snippet
FROM   v$session s
JOIN   v$sql     q ON q.sql_id = s.sql_id
WHERE  s.username = 'PERF_LAB'
AND    s.type     = 'USER'
AND    s.status   = 'ACTIVE'
GROUP  BY s.sql_id, SUBSTR(q.sql_text, 1, 60)
ORDER  BY active_session_count DESC;

-- RESULT: one SQL_ID accounts for nearly all active sessions — the
-- ORDER_ITEMS/ORDERS join behind sp_csr_order_lookup_by_product. That's our
-- suspect. Note the SQL_ID from this output; it's used in every step below.


-- =============================================================================
-- CHAIN STEP E — How expensive is that SQL_ID, in Oracle's own numbers?
-- =============================================================================
-- Replace '&sql_id' with the SQL_ID found in Step D (SQL*Plus will prompt
-- for it if run interactively).
SELECT sql_id, executions, buffer_gets, disk_reads, rows_processed,
       ROUND(buffer_gets / GREATEST(executions,1))  AS gets_per_exec,
       ROUND(elapsed_time / GREATEST(executions,1) / 1e3, 1) AS ms_per_exec,
       ROUND(elapsed_time / 1e6, 2)                  AS total_elapsed_sec
FROM   v$sqlarea
WHERE  sql_id = '&sql_id';

-- RESULT: buffer_gets per execution roughly matches ORDER_ITEMS' total block
-- count (tens of thousands of gets for a single lookup) — a strong signal of
-- a full scan, not a selective indexed lookup, which would show gets in the
-- tens or low hundreds. This is the "expensive SQL" evidence.


-- =============================================================================
-- CHAIN STEP F — What is the wait EVENT, specifically (not just the class)?
-- =============================================================================
-- V$SESSION_WAIT (legacy but still valid, and explicitly part of this
-- course's basic toolkit) or the equivalent columns on V$SESSION itself.
SELECT sw.sid, sw.event, sw.wait_time, sw.seconds_in_wait, sw.state
FROM   v$session_wait sw
JOIN   v$session s ON s.sid = sw.sid
WHERE  s.username = 'PERF_LAB'
AND    s.sql_id   = '&sql_id'
ORDER  BY sw.seconds_in_wait DESC;

-- RESULT: 'db file scattered read' (multiblock read into the buffer cache)
-- or 'direct path read' (read straight into PGA, common for large full
-- scans) dominates — both are the textbook signature of a full table scan
-- competing with other sessions for the same I/O path. This confirms Step E.


-- =============================================================================
-- CHAIN STEP G — Confirm the story with V$ACTIVE_SESSION_HISTORY
-- =============================================================================
-- ASH (in-memory, last hour) gives us a sample-based cross-check that isn't
-- dependent on catching sessions at one exact instant.
SELECT sql_id, event, COUNT(*) AS sample_count
FROM   v$active_session_history
WHERE  sample_time > SYSTIMESTAMP - INTERVAL '10' MINUTE
AND    session_type = 'FOREGROUND'
GROUP  BY sql_id, event
ORDER  BY sample_count DESC
FETCH FIRST 10 ROWS ONLY;

-- RESULT: the same SQL_ID and the same wait event dominate the ASH sample
-- history for the last several minutes — three independent views
-- (V$SESSION snapshot, V$SQLAREA statistics, ASH samples) now agree.


-- =============================================================================
-- CHAIN STEP H — Look at the plan: WHY is it a full scan?
-- =============================================================================
-- Basic plan reading only — we are answering one question: "full scan or
-- indexed access?" Deep join-method / cost analysis is Days 21-22.
SELECT * FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(sql_id => '&sql_id', format => 'BASIC')
);

-- RESULT: the plan shows TABLE ACCESS FULL on ORDER_ITEMS. Combined with
-- Steps E-G, the picture is complete:
--
--   HYPOTHESIS: ORDER_ITEMS.PRODUCT_ID has no supporting index, so every
--   execution of the product-lookup screen full-scans a 20-million-row
--   table. At one concurrent user this was slow-but-tolerable; at 25+
--   concurrent users (the recall-notice call spike) it saturates I/O and
--   buffer cache access, and response time collapses for everyone running
--   the screen — not because anything is "broken," but because an
--   inherently expensive access path was never a problem until concurrency
--   made it one.
--
-- This hypothesis is tested in demo.sql Step 4 (PROVE) before any DDL is
-- touched, and the fix is applied deliberately and separately in fix.sql.
