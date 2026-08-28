-- =============================================================================
-- Day 06 -- Architecture Bootcamp IV: How Oracle Executes a Statement
-- fix.sql
--
-- This is a SYNTHESIS day, not an incident day -- there is no bug to fix.
-- What this script does instead: PROVE, with real timing and real V$SQL
-- counters from this instance, that the second (soft-parse) execution of a
-- statement is genuinely cheaper than the first (hard-parse) execution of
-- the identical text, and that only ONE hard parse ever occurred no matter
-- how many times the statement is subsequently executed.
--
-- Technique: DBMS_SQL.PARSE is called twice, back to back, on the exact
-- same brand-new SQL text in the same session. The first PARSE call is
-- necessarily a hard parse (the text has never existed in the library
-- cache before this moment). The second PARSE call, on the identical text,
-- finds the now-cached cursor and soft-parses. Timing both calls directly
-- shows the cost difference driven purely by skipping semantic checking
-- and optimization on the second call.
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 100

COLUMN fix_tag NEW_VALUE fix_tag NOPRINT
SELECT TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISSFF3') AS fix_tag FROM dual;

DECLARE
  l_cur       INTEGER;
  l_sql       VARCHAR2(4000);
  l_start_ts  TIMESTAMP;
  l_hard_ms   NUMBER;
  l_soft_ms   NUMBER;
BEGIN
  l_sql := 'SELECT /* DAY06_FIX_&fix_tag */ COUNT(*) FROM perf_lab.orders o ' ||
           'JOIN perf_lab.order_items oi ON oi.order_id = o.order_id ' ||
           'WHERE o.order_date BETWEEN DATE ''2026-02-01'' AND DATE ''2026-02-28''';

  -- First PARSE of this brand-new SQL text: guaranteed HARD PARSE.
  -- The text has never been seen by this instance, so it cannot already be
  -- in the shared pool/library cache (Day 3). Oracle must run semantic
  -- checking against the data dictionary (Day 4) and full CBO optimization.
  l_start_ts := SYSTIMESTAMP;
  l_cur := DBMS_SQL.OPEN_CURSOR;
  DBMS_SQL.PARSE(l_cur, l_sql, DBMS_SQL.NATIVE);
  DBMS_SQL.CLOSE_CURSOR(l_cur);
  l_hard_ms := EXTRACT(SECOND FROM (SYSTIMESTAMP - l_start_ts)) * 1000;

  -- Second PARSE of the IDENTICAL SQL text, same session, immediately
  -- after: the library cache now holds a shareable cursor for this exact
  -- text, so this is a SOFT PARSE. Oracle matches the cursor and reuses the
  -- existing plan instead of re-optimizing.
  l_start_ts := SYSTIMESTAMP;
  l_cur := DBMS_SQL.OPEN_CURSOR;
  DBMS_SQL.PARSE(l_cur, l_sql, DBMS_SQL.NATIVE);
  DBMS_SQL.CLOSE_CURSOR(l_cur);
  l_soft_ms := EXTRACT(SECOND FROM (SYSTIMESTAMP - l_start_ts)) * 1000;

  DBMS_OUTPUT.PUT_LINE('Hard-parse elapsed (ms) : ' || TO_CHAR(l_hard_ms, '999990.000'));
  DBMS_OUTPUT.PUT_LINE('Soft-parse elapsed (ms) : ' || TO_CHAR(l_soft_ms, '999990.000'));
  DBMS_OUTPUT.PUT_LINE('-- ENVIRONMENT DEPENDENT: absolute milliseconds depend on');
  DBMS_OUTPUT.PUT_LINE('-- hardware and current shared pool load, but the soft parse');
  DBMS_OUTPUT.PUT_LINE('-- should consistently and substantially beat the hard parse');
  DBMS_OUTPUT.PUT_LINE('-- for identical SQL text.');
END;
/

-- Confirm from V$SQLAREA itself: LOADS must be 1 (only the first PARSE call
-- ever triggered a hard parse) while PARSE_CALLS is 2 (both PARSE calls
-- went through the parse path, but only one did the expensive work).
PROMPT ==== V$SQLAREA proof: one hard parse (LOADS), two parse calls ====

COLUMN sql_id FORMAT A15
SELECT sql_id, loads, parse_calls, executions
FROM   v$sqlarea
WHERE  sql_text LIKE '%DAY06_FIX_' || '&fix_tag' || '%';
