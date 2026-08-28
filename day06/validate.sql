-- =============================================================================
-- Day 06 -- Architecture Bootcamp IV: How Oracle Executes a Statement
-- validate.sql
--
-- Confirms, with an explicit PASS/FAIL check, that the hard-parse-then-
-- soft-parse pattern demonstrated in demo.sql (Steps 2-5) and proved in
-- fix.sql actually held for THIS run: exactly one hard parse (LOADS = 1)
-- and at least two parse calls (PARSE_CALLS >= 2) for the demo SQL_ID.
--
-- Run after demo.sql, in the same session, while &demo_sql_id is still
-- defined. If run separately, the lookup query below re-derives it from
-- the most recent DAY06_ tagged statement in V$SQLAREA.
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200

-- Re-derive &demo_sql_id defensively in case this script is run standalone.
-- NOTE: captured via a distinct alias (grab_sql_id), never the plain "sql_id"
-- alias -- SQL*Plus COLUMN attributes are sticky per column name for the rest
-- of the session, so marking "sql_id" itself NOPRINT here would silently
-- suppress it from every later query in this script (and any script run
-- afterward in the same session) that also selects a column called sql_id.
COLUMN grab_sql_id NEW_VALUE v_sql_id NOPRINT
SELECT sql_id AS grab_sql_id
FROM   v$sqlarea
WHERE  sql_text LIKE '%DAY06_%'
AND    sql_text NOT LIKE '%DAY06_FIX%'
AND    first_load_time = (
         SELECT MAX(first_load_time)
         FROM   v$sqlarea
         WHERE  sql_text LIKE '%DAY06_%'
         AND    sql_text NOT LIKE '%DAY06_FIX%'
       )
AND    ROWNUM = 1;

PROMPT ==== BEFORE/AFTER comparison: hard parse (first execution) vs soft parse (later executions) ====

COLUMN sql_id FORMAT A15
SELECT sql_id, loads AS hard_parses, parse_calls, executions,
       CASE
         WHEN parse_calls > 0 THEN
           ROUND(100 * (1 - (loads / parse_calls)), 1)
       END AS pct_parse_calls_soft
FROM   v$sqlarea
WHERE  sql_id = '&v_sql_id';

DECLARE
  l_loads       NUMBER;
  l_parse_calls NUMBER;
  l_executions  NUMBER;
BEGIN
  SELECT loads, parse_calls, executions
  INTO   l_loads, l_parse_calls, l_executions
  FROM   v$sqlarea
  WHERE  sql_id = '&v_sql_id';

  DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------');
  IF l_loads = 1 THEN
    DBMS_OUTPUT.PUT_LINE('PASS: exactly one hard parse occurred (LOADS = 1) for this SQL_ID.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FAIL: expected LOADS = 1, found LOADS = ' || l_loads
                          || '. Likely cause: the shared pool was flushed or this');
    DBMS_OUTPUT.PUT_LINE('  statement was invalidated (e.g. stats gathered on');
    DBMS_OUTPUT.PUT_LINE('  PERF_LAB objects) between demo.sql executions -- rerun');
    DBMS_OUTPUT.PUT_LINE('  demo.sql cleanly with a fresh &demo_tag to confirm.');
  END IF;

  IF l_parse_calls >= 2 AND l_executions >= 2 THEN
    DBMS_OUTPUT.PUT_LINE('PASS: at least two parse calls and two executions were recorded,');
    DBMS_OUTPUT.PUT_LINE('  confirming the statement was reused (soft-parsed), not reloaded.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FAIL: expected PARSE_CALLS >= 2 and EXECUTIONS >= 2, found '
                          || l_parse_calls || ' / ' || l_executions
                          || '. Confirm demo.sql Steps 2 and 4 both ran in this session.');
  END IF;
  DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------');
END;
/

PROMPT ==== Cross-check: fix.sql's isolated hard-vs-soft PARSE timing proof ====
PROMPT (see fix.sql output for the millisecond comparison -- soft parse should
PROMPT be substantially faster than hard parse for identical SQL text)

SELECT sql_id, loads, parse_calls, executions
FROM   v$sqlarea
WHERE  sql_text LIKE '%DAY06_FIX%'
ORDER BY first_load_time DESC
FETCH FIRST 1 ROWS ONLY;
