-- =====================================================================
-- Day 4 — Architecture Bootcamp II — Storage
-- diagnose.sql — supporting investigative queries
--
-- These are the "look before/after" queries used around the demo and
-- lab: tablespace and segment state, free space, and the
-- Troubleshooting Challenge ("a tablespace is unexpectedly low on
-- free space"). Run as PERF_LAB (DBA_* views were granted in
-- setup.sql) unless noted.
-- =====================================================================

PROMPT ===================================================================
PROMPT D1 - Tablespace inventory: what exists, how big, what type
PROMPT ===================================================================

COLUMN tablespace_name FORMAT A20

SELECT tablespace_name, status, contents, extent_management,
       allocation_type, segment_space_management
FROM   dba_tablespaces
ORDER  BY tablespace_name;


PROMPT ===================================================================
PROMPT D2 - Datafiles: size, autoextend, current status
PROMPT ===================================================================

SELECT file_id, tablespace_name, file_name,
       ROUND(bytes/1024/1024)      AS size_mb,
       ROUND(maxbytes/1024/1024)   AS max_mb,
       autoextensible, status
FROM   dba_data_files
ORDER  BY tablespace_name, file_id;


PROMPT ===================================================================
PROMPT D3 - Free space per tablespace (the "how full is it" view)
PROMPT ===================================================================

SELECT tablespace_name,
       COUNT(*)                         AS free_chunks,
       ROUND(SUM(bytes)/1024/1024, 2)   AS total_free_mb,
       ROUND(MAX(bytes)/1024/1024, 2)   AS largest_free_chunk_mb
FROM   dba_free_space
GROUP  BY tablespace_name
ORDER  BY tablespace_name;


PROMPT ===================================================================
PROMPT D4 - Used space per tablespace (allocated to segments, not free)
PROMPT ===================================================================

SELECT tablespace_name,
       ROUND(SUM(bytes)/1024/1024, 2)  AS used_mb,
       COUNT(*)                        AS segment_count
FROM   dba_segments
GROUP  BY tablespace_name
ORDER  BY tablespace_name;


PROMPT ===================================================================
PROMPT D5 - Used + free side by side, with a percent-full column
PROMPT     (this is the query the Troubleshooting Challenge starts from)
PROMPT ===================================================================

WITH used AS (
  SELECT tablespace_name, SUM(bytes) AS used_bytes
  FROM   dba_segments
  GROUP  BY tablespace_name
),
free AS (
  SELECT tablespace_name, SUM(bytes) AS free_bytes
  FROM   dba_free_space
  GROUP  BY tablespace_name
),
allocated AS (
  SELECT tablespace_name, SUM(bytes) AS allocated_bytes
  FROM   dba_data_files
  GROUP  BY tablespace_name
)
SELECT a.tablespace_name,
       ROUND(a.allocated_bytes/1024/1024, 1)              AS datafile_mb,
       ROUND(NVL(u.used_bytes, 0)/1024/1024, 1)            AS used_mb,
       ROUND(NVL(f.free_bytes, 0)/1024/1024, 1)            AS free_mb,
       ROUND(NVL(u.used_bytes, 0) / a.allocated_bytes * 100, 1) AS pct_used
FROM   allocated a
LEFT JOIN used u ON u.tablespace_name = a.tablespace_name
LEFT JOIN free f ON f.tablespace_name = a.tablespace_name
ORDER  BY pct_used DESC;


PROMPT ===================================================================
PROMPT D6 - Largest segments in a specific tablespace (find the "hog")
PROMPT     Edit the tablespace name below to whichever one is low on
PROMPT     space in the Troubleshooting Challenge.
PROMPT ===================================================================

SELECT owner, segment_name, segment_type,
       ROUND(bytes/1024/1024, 2) AS size_mb, extents
FROM   dba_segments
WHERE  tablespace_name = 'PERF_D4_REDO_TS'   -- <-- edit as needed
ORDER  BY bytes DESC
FETCH FIRST 10 ROWS ONLY;


PROMPT ===================================================================
PROMPT D7 - Extent map for one segment (fragmentation / growth pattern)
PROMPT ===================================================================

SELECT extent_id, file_id, block_id, blocks, bytes
FROM   dba_extents
WHERE  owner        = 'PERF_LAB'
AND    segment_name = 'D4_REDO_DEMO'
ORDER  BY extent_id;


PROMPT ===================================================================
PROMPT D8 - Segment growth check: rows vs. allocated extents
PROMPT     (a segment can hold far more allocated space than live
PROMPT     rows need, e.g. after heavy deletes -- a classic false lead
PROMPT     in the Troubleshooting Challenge)
PROMPT ===================================================================

SELECT s.segment_name,
       s.extents,
       ROUND(s.bytes/1024/1024, 2)                     AS allocated_mb,
       t.num_rows,
       t.blocks                                        AS blocks_at_last_analyze,
       t.last_analyzed
FROM   dba_segments s
JOIN   dba_tables t ON t.owner = s.owner AND t.table_name = s.segment_name
WHERE  s.owner = 'PERF_LAB'
AND    s.segment_name IN ('D4_DEMO_ORDERS', 'D4_REDO_DEMO');


PROMPT ===================================================================
PROMPT D9 - Redo log and thread inventory (context for Part B of demo.sql)
PROMPT     LOG-related views are instance-wide; no WHERE needed for a
PROMPT     single-instance lab.
PROMPT ===================================================================

COLUMN member FORMAT A55

SELECT l.thread#, l.group#, l.sequence#, l.status,
       ROUND(l.bytes/1024/1024) AS size_mb, l.members, l.archived
FROM   v$log l
ORDER  BY l.thread#, l.group#;

SELECT lf.group#, lf.member, lf.type, lf.status
FROM   v$logfile lf
ORDER  BY lf.group#;

SELECT thread#, status, instance, enabled
FROM   v$thread;

-- Talking point: STATUS = CURRENT is the group LGWR is writing into
-- right now; ACTIVE means it is still needed for instance recovery
-- (not yet fully checkpointed/archived); INACTIVE means it is free
-- to be reused. If every group is ACTIVE and none is INACTIVE, that
-- is a classic sign the redo logs are too small or too few for the
-- write rate -- filed away for a later tuning day, not solved today.
