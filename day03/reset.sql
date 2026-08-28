-- =============================================================================
-- Day 3 — Architecture Bootcamp I: Instance vs. Database, Memory at a Glance
-- reset.sql
--
-- Purpose : Return the SQL*Plus/SQLcl session to a clean state for the next
--           block (Day 4, or a re-run of Day 3's own demo). "Reset" for this
--           conceptual, read-only day means clearing SESSION-LEVEL formatting
--           and confirming the session is back at the CDB root — there is no
--           data or object state to roll back, per cleanup.sql.
--
-- Connect as : the same DBA-privileged account used throughout Day 3. Safe to
--              run multiple times.
-- =============================================================================

-- Make sure we're back at the CDB root (some diagnose.sql steps switch into
-- PERFPDB; this is idempotent if already at the root).
ALTER SESSION SET CONTAINER = CDB$ROOT;

-- Clear every COLUMN format applied during demo.sql / diagnose.sql / fix.sql
-- / validate.sql so the next script starts from SQL*Plus defaults.
CLEAR COLUMNS;

COLUMN instance_name  CLEAR
COLUMN host_name      CLEAR
COLUMN db_name         CLEAR
COLUMN name             CLEAR
COLUMN pdb_name         CLEAR
COLUMN open_mode        CLEAR
COLUMN program           CLEAR
COLUMN spid               CLEAR
COLUMN description        CLEAR
COLUMN metric              CLEAR
COLUMN value_mb             CLEAR

-- Restore default display settings
SET LINESIZE 80
SET PAGESIZE 14
SET NUMFORMAT ''

PROMPT
PROMPT Session reset: CDB$ROOT, default SQL*Plus formatting restored.
PROMPT Day 3 is complete — no lingering objects, no lingering session state.
PROMPT Ready for Day 4 (Architecture Bootcamp II — Storage: Datafiles,
PROMPT Tablespaces, Segments, Redo & Undo).
PROMPT
