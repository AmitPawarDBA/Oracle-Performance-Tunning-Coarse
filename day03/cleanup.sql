-- =============================================================================
-- Day 3 — Architecture Bootcamp I: Instance vs. Database, Memory at a Glance
-- cleanup.sql
--
-- Purpose : Day 3 is entirely read-only against dictionary/V$ views — no
--           tables, no rows, no PDBs, no parameters were created or changed
--           by setup.sql, demo.sql, diagnose.sql, fix.sql, or validate.sql.
--           So there is genuinely nothing to DROP or DELETE. What this script
--           DOES do is confirm that's actually true — i.e. it verifies no
--           session-level state leaked out of today's demo before the next
--           class/day uses this same lab instance — and returns the session
--           to the CDB root container.
--
-- Connect as : the same DBA-privileged account used throughout Day 3.
-- =============================================================================

PROMPT ================================================================
PROMPT Day 3 cleanup: confirming no session-level state was left behind
PROMPT ================================================================

-- 1. Confirm we're not still sitting inside PERFPDB from diagnose.sql's
--    Question 1/2 container switches (that script already switches back, but
--    verify independently here in case steps were run out of order).
SELECT SYS_CONTEXT('USERENV','CON_NAME') AS current_container FROM dual;

-- If the above does not read CDB$ROOT, switch back explicitly:
ALTER SESSION SET CONTAINER = CDB$ROOT;

-- 2. Confirm the always-a-two-row PERFPDB/PDB$SEED nature of V$PDBS is
--    unchanged (i.e. nobody accidentally created or dropped a PDB while
--    exploring — Day 3 never issues CREATE/DROP PLUGGABLE DATABASE, but this
--    is a cheap, worthwhile sanity check given how easy it is to fat-finger a
--    DDL statement while live-demoing).
SELECT COUNT(*) AS pdb_row_count FROM v$pdbs;

-- 3. Confirm no PERF_LAB objects were touched — Day 3 never queries or
--    modifies PERF_LAB application tables at all, only dictionary/V$ views,
--    so object counts should read whatever the base lab setup produced,
--    untouched by anything in this day's folder.
SELECT COUNT(*) AS perf_lab_object_count
FROM   cdb_objects
WHERE  owner = 'PERF_LAB';

PROMPT
PROMPT Nothing to drop, nothing to delete — Day 3 leaves the lab environment
PROMPT exactly as setup.sql found it. Proceed to reset.sql to clear
PROMPT SQL*Plus session formatting before the next block.
PROMPT
