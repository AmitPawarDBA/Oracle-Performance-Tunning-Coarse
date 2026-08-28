-- =====================================================================
-- Day 4 — Architecture Bootcamp II — Storage
-- validate.sql — confirms the concepts landed correctly
--
-- Self-contained: does not depend on demo.sql/fix.sql having been run
-- first (it generates its own small transaction), so it can be run
-- standalone as a comprehension check. Run as PERF_LAB.
-- Every check prints PASS/FAIL via DBMS_OUTPUT so it can be read at a
-- glance during class.
-- =====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED

PROMPT ===================================================================
PROMPT CHECK 1 - ROWID decode is internally consistent with DBA_OBJECTS
PROMPT ===================================================================

DECLARE
  v_rowid     ROWID;
  v_obj_id    NUMBER;
  v_dict_obj  NUMBER;
BEGIN
  SELECT ROWID INTO v_rowid FROM perf_lab.d4_demo_orders WHERE order_id = 1;
  v_obj_id := DBMS_ROWID.ROWID_OBJECT(v_rowid);

  SELECT data_object_id INTO v_dict_obj
  FROM   dba_objects
  WHERE  owner = 'PERF_LAB' AND object_name = 'D4_DEMO_ORDERS';

  IF v_obj_id = v_dict_obj THEN
    DBMS_OUTPUT.PUT_LINE('PASS - DBMS_ROWID.ROWID_OBJECT (' || v_obj_id ||
      ') matches DBA_OBJECTS.DATA_OBJECT_ID (' || v_dict_obj || ')');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FAIL - object id mismatch: rowid says ' || v_obj_id ||
      ', dictionary says ' || v_dict_obj);
  END IF;
END;
/


PROMPT ===================================================================
PROMPT CHECK 2 - the decoded block actually falls inside a DBA_EXTENTS row
PROMPT     for this segment (i.e. the row-to-block trace is provably
PROMPT     correct, not just plausible-looking)
PROMPT ===================================================================

DECLARE
  v_rowid    ROWID;
  v_fno      NUMBER;
  v_block    NUMBER;
  v_matches  NUMBER;
BEGIN
  SELECT ROWID INTO v_rowid FROM perf_lab.d4_demo_orders WHERE order_id = 1;
  v_fno   := DBMS_ROWID.ROWID_TO_ABSOLUTE_FNO(v_rowid, 'PERF_LAB', 'D4_DEMO_ORDERS');
  v_block := DBMS_ROWID.ROWID_BLOCK_NUMBER(v_rowid);

  SELECT COUNT(*) INTO v_matches
  FROM   dba_extents
  WHERE  owner        = 'PERF_LAB'
  AND    segment_name = 'D4_DEMO_ORDERS'
  AND    file_id       = v_fno
  AND    v_block BETWEEN block_id AND block_id + blocks - 1;

  IF v_matches = 1 THEN
    DBMS_OUTPUT.PUT_LINE('PASS - block ' || v_block || ' in file ' || v_fno ||
      ' is covered by exactly one extent of D4_DEMO_ORDERS, as expected');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FAIL - expected exactly 1 matching extent, found ' || v_matches);
  END IF;
END;
/


PROMPT ===================================================================
PROMPT CHECK 3 - DBA_SEGMENTS.EXTENTS agrees with a COUNT(*) of DBA_EXTENTS
PROMPT ===================================================================

DECLARE
  v_seg_extents   NUMBER;
  v_extent_rows   NUMBER;
BEGIN
  SELECT extents INTO v_seg_extents
  FROM   dba_segments
  WHERE  owner = 'PERF_LAB' AND segment_name = 'D4_DEMO_ORDERS';

  SELECT COUNT(*) INTO v_extent_rows
  FROM   dba_extents
  WHERE  owner = 'PERF_LAB' AND segment_name = 'D4_DEMO_ORDERS';

  IF v_seg_extents = v_extent_rows THEN
    DBMS_OUTPUT.PUT_LINE('PASS - DBA_SEGMENTS reports ' || v_seg_extents ||
      ' extents, DBA_EXTENTS lists ' || v_extent_rows || ' rows - consistent');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FAIL - DBA_SEGMENTS says ' || v_seg_extents ||
      ' but DBA_EXTENTS lists ' || v_extent_rows);
  END IF;
END;
/


PROMPT ===================================================================
PROMPT CHECK 4 - a committed INSERT measurably increases 'redo size'
PROMPT ===================================================================

DECLARE
  v_before  NUMBER;
  v_after   NUMBER;
BEGIN
  SELECT ms.value INTO v_before
  FROM   v$mystat ms JOIN v$statname sn ON sn.statistic# = ms.statistic#
  WHERE  sn.name = 'redo size';

  INSERT INTO perf_lab.d4_redo_demo (id, payload)
  SELECT id + 100000, payload FROM perf_lab.d4_redo_demo WHERE id <= 50;
  COMMIT;

  SELECT ms.value INTO v_after
  FROM   v$mystat ms JOIN v$statname sn ON sn.statistic# = ms.statistic#
  WHERE  sn.name = 'redo size';

  IF v_after > v_before THEN
    DBMS_OUTPUT.PUT_LINE('PASS - redo size grew from ' || v_before ||
      ' to ' || v_after || ' after a committed insert (delta: ' ||
      (v_after - v_before) || ' bytes, ENVIRONMENT DEPENDENT)');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FAIL - redo size did not increase (' ||
      v_before || ' -> ' || v_after || ') -- unexpected for any DML');
  END IF;
END;
/

-- Clean up the rows Check 4 just inserted so re-running validate.sql
-- stays repeatable.
DELETE FROM perf_lab.d4_redo_demo WHERE id > 100000;
COMMIT;


PROMPT ===================================================================
PROMPT CHECK 5 - V$TRANSACTION shows an active transaction mid-DML, and
PROMPT     none once committed (undo lifecycle sanity check)
PROMPT ===================================================================

DECLARE
  v_mid_dml_count  NUMBER;
  v_after_commit   NUMBER;
BEGIN
  INSERT INTO perf_lab.d4_redo_demo (id, payload) VALUES (999999, 'validate-check-5');

  SELECT COUNT(*) INTO v_mid_dml_count
  FROM   v$transaction t JOIN v$session s ON s.taddr = t.addr
  WHERE  s.sid = SYS_CONTEXT('USERENV', 'SID');

  COMMIT;

  SELECT COUNT(*) INTO v_after_commit
  FROM   v$transaction t JOIN v$session s ON s.taddr = t.addr
  WHERE  s.sid = SYS_CONTEXT('USERENV', 'SID');

  IF v_mid_dml_count = 1 AND v_after_commit = 0 THEN
    DBMS_OUTPUT.PUT_LINE('PASS - V$TRANSACTION showed 1 active row mid-DML, 0 after commit');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FAIL - expected (1, 0), got (' || v_mid_dml_count ||
      ', ' || v_after_commit || ')');
  END IF;
END;
/

DELETE FROM perf_lab.d4_redo_demo WHERE id = 999999;
COMMIT;


PROMPT ===================================================================
PROMPT CHECK 6 - flashback query reconstructs a past value via undo,
PROMPT     with no ROLLBACK involved (read-consistency misconception check)
PROMPT ===================================================================

DECLARE
  v_original   NUMBER;
  v_changed    NUMBER;
  v_flashback  NUMBER;
  v_ts         TIMESTAMP := SYSTIMESTAMP;
BEGIN
  SELECT order_total INTO v_original FROM perf_lab.d4_demo_orders WHERE order_id = 3;

  UPDATE perf_lab.d4_demo_orders SET order_total = order_total + 1 WHERE order_id = 3;
  COMMIT;

  SELECT order_total INTO v_changed FROM perf_lab.d4_demo_orders WHERE order_id = 3;

  EXECUTE IMMEDIATE
    'SELECT order_total FROM perf_lab.d4_demo_orders AS OF TIMESTAMP :1 WHERE order_id = 3'
    INTO v_flashback USING v_ts;

  IF v_flashback = v_original AND v_changed = v_original + 1 THEN
    DBMS_OUTPUT.PUT_LINE('PASS - flashback query returned the pre-update value (' ||
      v_flashback || ') using undo alone, no ROLLBACK executed');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FAIL - original=' || v_original || ' changed=' || v_changed ||
      ' flashback=' || v_flashback);
  END IF;
END;
/

PROMPT ===================================================================
PROMPT Validation complete. Review PASS/FAIL lines above.
PROMPT ===================================================================
