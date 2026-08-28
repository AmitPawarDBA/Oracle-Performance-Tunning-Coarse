-- =============================================================================
-- Day 3 — Architecture Bootcamp I: Instance vs. Database, Memory at a Glance
-- validate.sql
--
-- Purpose : A short self-check query set confirming today's concepts landed
--           correctly. Each check states what a correct understanding SHOULD
--           produce, so a student can run this independently and grade
--           themselves without an instructor present.
--
-- Connect as : DBA-privileged account (e.g. SYSTEM) at the CDB root.
-- =============================================================================

SET LINESIZE 150
SET PAGESIZE 100

PROMPT ================================================================
PROMPT CHECK 1: Instance identity and database identity are independent
PROMPT   PASS if: instance_name and db_name are shown as two separate,
PROMPT   independently-set values (they are allowed to look similar in a
PROMPT   single-instance lab, but they are not the same parameter).
PROMPT ================================================================

SELECT i.instance_name, d.name AS db_name, d.cdb
FROM   v$instance i, v$database d;


PROMPT ================================================================
PROMPT CHECK 2: This session's own server process is a FOREGROUND process,
PROMPT   not a background one.
PROMPT   PASS if: BACKGROUND is NULL for this row, and the SPID does not
PROMPT   appear anywhere in the V$BGPROCESS list below.
PROMPT ================================================================

SELECT p.pid, p.spid AS os_pid, p.background, p.program
FROM   v$session s
JOIN   v$process p ON p.addr = s.paddr
WHERE  s.sid = SYS_CONTEXT('USERENV','SID');

PROMPT --- Full background process SPID list, for comparison ---
SELECT TRIM(bg.name) AS process_name, p.spid AS os_pid
FROM   v$bgprocess bg
JOIN   v$process p ON p.addr = bg.paddr
ORDER  BY process_name;


PROMPT ================================================================
PROMPT CHECK 3: At least the mandatory background processes are present
PROMPT   PASS if: PMON, SMON, DBW0 (or DBWn), LGWR, and CKPT all appear in
PROMPT   this list (ARCn will only appear if the database runs in
PROMPT   ARCHIVELOG mode — check V$DATABASE.LOG_MODE if it's missing).
PROMPT ================================================================

SELECT TRIM(name) AS process_name, description
FROM   v$bgprocess
WHERE  paddr != '00'
  AND  TRIM(name) IN ('PMON','SMON','DBW0','DBWN','LGWR','CKPT','ARC0','ARCN','MMON','MMNL','RECO')
ORDER  BY process_name;


PROMPT ================================================================
PROMPT CHECK 4: V$PDBS returns at least two rows for a single-app-PDB CDB
PROMPT   PASS if: you see PDB$SEED (READ ONLY) AND the application PDB
PROMPT   (READ WRITE) as two distinct rows — this is the "mystery" from
PROMPT   today's Real-World Scenario, self-verified.
PROMPT   FAIL condition to recognize: if a student concludes "two rows means
PROMPT   two application databases," that's the misconception to correct —
PROMPT   re-read the OPEN_MODE and PDB_NAME columns carefully.
PROMPT ================================================================

SELECT con_id, pdb_name, open_mode, restricted
FROM   v$pdbs
ORDER  BY con_id;


PROMPT ================================================================
PROMPT CHECK 5: SGA and PGA are reported by two different views with two
PROMPT   different totals (not the same pool under two names)
PROMPT   PASS if: TOTAL_SGA_MB and TOTAL_PGA_MB are both non-null, both
PROMPT   plausible values, and NOT required to be equal to each other.
PROMPT ================================================================

SELECT
    (SELECT ROUND(SUM(value)/1024/1024,2) FROM v$sga) AS total_sga_mb,
    (SELECT ROUND(value/1024/1024,2) FROM v$pgastat
      WHERE name = 'total PGA allocated')             AS total_pga_mb
FROM dual;


PROMPT ================================================================
PROMPT CHECK 6: The database's on-disk footprint is independent of, and in
PROMPT   this lab almost certainly larger than, the SGA (Misconception #1
PROMPT   from fix.sql, self-verified)
PROMPT   PASS if: DATABASE_MB is a meaningfully different number from
PROMPT   SGA_MB — they should NOT be roughly equal by coincidence.
PROMPT ================================================================

WITH sga AS (SELECT SUM(value) AS bytes FROM v$sga),
     db  AS (SELECT SUM(bytes) AS bytes FROM (
                 SELECT bytes FROM cdb_data_files
                 UNION ALL SELECT bytes FROM cdb_temp_files
                 UNION ALL SELECT bytes FROM v$log))
SELECT ROUND(sga.bytes/1024/1024,2) AS sga_mb,
       ROUND(db.bytes/1024/1024,2)  AS database_mb
FROM   sga, db;

PROMPT
PROMPT ================================================================
PROMPT Self-check complete. If every PASS condition above held, today's
PROMPT architecture concepts have landed. If CHECK 3 is missing an expected
PROMPT process, or CHECK 4's row count/OPEN_MODE surprised you, revisit the
PROMPT Theory and Real-World Scenario sections of day03-content.md before
PROMPT moving on to Day 4.
PROMPT ================================================================
