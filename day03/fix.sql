-- =============================================================================
-- Day 3 — Architecture Bootcamp I: Instance vs. Database, Memory at a Glance
-- fix.sql
--
-- Purpose : This is a conceptual day with no live incident to fix, so — per
--           the course template — this script instead CORRECTS A MISCONCEPTION
--           with real numbers instead of a broken system with a real repair.
--
--           Misconception #1 (the big one): "The SGA holds the database" /
--           "SGA size roughly equals database size." It doesn't — the SGA is
--           a bounded CACHE for a working set of blocks and parsed SQL, sized
--           independently of how much data actually exists on disk. This
--           script proves it by putting the two numbers side by side.
--
--           Misconception #2: "SGA and PGA are the same memory pool, just
--           with different names." They are tracked completely separately by
--           Oracle; this script proves that too.
--
-- Connect as : DBA-privileged account (e.g. SYSTEM) at the CDB root.
--
-- ENVIRONMENT DEPENDENT: the exact SGA_MB, DATABASE_GB, and ratio values below
-- depend entirely on this lab's SGA_TARGET/SGA_MAX_SIZE configuration and how
-- much of the PERF_LAB Standard-tier data set has been loaded. The numbers
-- will differ from run to run and from lab to lab — the ARCHITECTURAL POINT
-- (that SGA size and database-on-disk size are two independent numbers, not
-- the same number by a different name) holds regardless of the exact values.
-- =============================================================================

SET LINESIZE 150
SET PAGESIZE 100
SET NUMFORMAT 999,999,999.99

PROMPT ================================================================
PROMPT MISCONCEPTION #1: "SGA size = database size"
PROMPT ================================================================
PROMPT
PROMPT We'll compute two numbers independently and compare them:
PROMPT   (a) total SGA size, from V$SGA — what's cached in shared memory
PROMPT   (b) total database size on disk, from CDB_DATA_FILES/CDB_TEMP_FILES/
PROMPT       V$LOG — every byte the database actually occupies on storage,
PROMPT       across every container in this CDB
PROMPT

-- (a) Total SGA size, in MB
COLUMN metric FORMAT A34
COLUMN value_mb FORMAT 999,999,999.99

PROMPT --- (a) Total SGA size ---
SELECT 'Total SGA (V$SGA)' AS metric,
       ROUND(SUM(value) / 1024 / 1024, 2) AS value_mb
FROM   v$sga;

-- (b) Total database size on disk, in MB — CDB_DATA_FILES/CDB_TEMP_FILES span
-- every container in the CDB (root + every PDB), which is the fair comparison
-- since V$SGA above is also instance-wide, not per-container.
PROMPT --- (b) Total database size on disk (all containers, datafiles+tempfiles+redo) ---
WITH sizes AS (
    SELECT bytes FROM cdb_data_files
    UNION ALL
    SELECT bytes FROM cdb_temp_files
    UNION ALL
    SELECT bytes FROM v$log
)
SELECT 'Total database on disk (all files)' AS metric,
       ROUND(SUM(bytes) / 1024 / 1024, 2) AS value_mb
FROM   sizes;

-- Put both numbers on screen together with the ratio, so the gap is
-- impossible to miss
PROMPT --- Side-by-side comparison ---
WITH sga AS (
    SELECT SUM(value) AS bytes FROM v$sga
),
db AS (
    SELECT SUM(bytes) AS bytes FROM (
        SELECT bytes FROM cdb_data_files
        UNION ALL
        SELECT bytes FROM cdb_temp_files
        UNION ALL
        SELECT bytes FROM v$log
    )
)
SELECT ROUND(sga.bytes / 1024 / 1024, 2)         AS sga_mb,
       ROUND(db.bytes  / 1024 / 1024, 2)         AS database_mb,
       ROUND(db.bytes / NULLIF(sga.bytes, 0), 1) AS database_is_n_times_sga
FROM   sga, db;

PROMPT
PROMPT CONCLUSION: the database on disk is very likely many times larger than
PROMPT the SGA (often 5x-50x or more, ENVIRONMENT DEPENDENT on this lab's
PROMPT sizing and how much PERF_LAB data has been loaded) — and that is
PROMPT EXPECTED, CORRECT behavior, not a problem to fix. The SGA is a bounded
PROMPT cache for a working set of frequently-touched blocks and parsed SQL; it
PROMPT was never meant to hold the whole database at once. "Increase the SGA
PROMPT so the database has more room" is backwards — the database's size on
PROMPT disk is governed by its data, not by how much RAM the instance was
PROMPT given. (How to size the SGA well, and what happens when the working set
PROMPT doesn't fit, is Stage 10 — Days 28-29 — not today.)
PROMPT

PROMPT ================================================================
PROMPT MISCONCEPTION #2: "SGA and PGA are the same memory pool"
PROMPT ================================================================
PROMPT
PROMPT Oracle tracks these as two entirely separate totals. Query both and
PROMPT put them side by side:
PROMPT

WITH sga AS (
    SELECT SUM(value) AS bytes FROM v$sga
),
pga AS (
    SELECT value AS bytes FROM v$pgastat WHERE name = 'total PGA allocated'
)
SELECT ROUND(sga.bytes / 1024 / 1024, 2) AS total_sga_mb,
       ROUND(pga.bytes / 1024 / 1024, 2) AS total_pga_allocated_mb
FROM   sga, pga;

-- Prove PGA is per-process and private by showing several different
-- processes each with their own distinct PGA figure
PROMPT --- Per-process PGA usage (proof it's private, not shared) ---
SELECT p.pid,
       p.spid AS os_pid,
       p.program,
       ROUND(p.pga_used_mem / 1024, 1)  AS pga_used_kb,
       ROUND(p.pga_alloc_mem / 1024, 1) AS pga_alloc_kb
FROM   v$process p
WHERE  p.background IS NULL
ORDER  BY p.pid;

PROMPT
PROMPT CONCLUSION: total PGA allocated is tracked in V$PGASTAT, a completely
PROMPT different view from V$SGA, and V$PROCESS shows each foreground process
PROMPT with its OWN distinct PGA_USED_MEM/PGA_ALLOC_MEM value — proof this is
PROMPT private, per-process memory, not a shared pool with another name.
PROMPT
