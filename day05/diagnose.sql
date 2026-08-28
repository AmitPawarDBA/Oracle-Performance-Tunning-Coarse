-- =============================================================================
-- Day 5 — Architecture Bootcamp III: Process Architecture & Connections
-- diagnose.sql — supporting investigative queries
--
-- Two purposes:
--   (A) General-purpose session-to-OS-process and background-process queries
--       used throughout the demo and hands-on lab.
--   (B) The server-side evidence-gathering used in the Real-World Scenario
--       ("the connection just hangs") to confirm the database side is
--       healthy and rule out the false lead (unregistered service) before
--       concluding the problem is upstream (client-side TNS/network).
--
-- NOTE: no live Oracle instance was available while writing this script.
-- Verify against a real 19c instance before class.
-- =============================================================================


-- =============================================================================
-- (A1) Map every currently connected user session to its OS process.
-- =============================================================================
SELECT s.sid, s.serial#, s.username, s.server, s.status,
       s.program, s.machine, s.module,
       p.spid AS os_pid
FROM   v$session s
JOIN   v$process p ON p.addr = s.paddr
WHERE  s.type = 'USER'
ORDER BY s.logon_time DESC;


-- =============================================================================
-- (A2) Which connection type is each session using? Quick distribution.
-- =============================================================================
SELECT server, COUNT(*) AS session_count
FROM   v$session
WHERE  type = 'USER'
GROUP BY server
ORDER BY server;


-- =============================================================================
-- (A3) Every background process currently started, with its OS PID.
--      PADDR = '00' means that background process slot is defined but not
--      currently running (e.g., an ARCn slot that hasn't been needed yet).
-- =============================================================================
SELECT b.pname, b.description, p.spid AS os_pid
FROM   v$bgprocess b
LEFT JOIN v$process p ON p.addr = b.paddr
WHERE  b.paddr != '00'
ORDER BY b.pname;


-- =============================================================================
-- (A4) Is this instance configured for shared server at all?
--      An empty result set is completely normal — most instances never
--      configure shared server.
-- =============================================================================
SELECT name, value
FROM   v$parameter
WHERE  name IN ('dispatchers', 'shared_servers', 'max_shared_servers');

SELECT network, dispatchers AS configured, DECODE(status,'WAIT','idle','busy') AS current_status
FROM   v$dispatcher;

SELECT name, status, requests, messages
FROM   v$shared_server;


-- =============================================================================
-- (A5) Redo/write activity snapshot (point-in-time; run twice around a
--      workload and diff manually, or use the delta pattern in demo.sql).
-- =============================================================================
SELECT name, value
FROM   v$sysstat
WHERE  name IN ('redo size', 'redo entries', 'redo writes',
                'physical writes', 'user commits', 'db block changes')
ORDER BY name;


-- =============================================================================
-- (B1) Real-World Scenario evidence gathering — "the connection just hangs"
-- Confirm the instance itself is healthy and reachable internally.
-- =============================================================================
SELECT instance_name, host_name, status, database_status
FROM   v$instance;


-- =============================================================================
-- (B2) Confirm the service the app expects is actually configured to be
-- offered by this instance (server-side name, independent of the listener).
-- =============================================================================
SELECT name, value
FROM   v$parameter
WHERE  name = 'service_names';

SELECT name, network_name, creation_date
FROM   dba_services
ORDER BY name;


-- =============================================================================
-- (B3) False lead check: is the service actually registered with the
-- listener the app is (or should be) pointing at? In this scenario this
-- comes back healthy, which is what rules OUT "unregistered service" as
-- the cause and points the investigation toward the client-side network
-- path instead.
--
-- This step is run at the OS shell on the database host, not in SQL*Plus:
--
--     lsnrctl status
--     lsnrctl services
--
-- Expected (healthy) LSNRCTL STATUS output includes a block like:
--   Service "perfpdb" has 1 instance(s).
--     Instance "ORCLCDB", status READY, has 2 handler(s) for this service...
--
-- If that block is present and the handler count is > 0, the database side
-- of service registration is confirmed healthy — the investigation must
-- move to the client's network path (host/port reachability), which is
-- outside what any V$ view on the database server can show you directly.
-- =============================================================================


-- =============================================================================
-- (B4) Resource-exhaustion check (rules IN or OUT the Troubleshooting
-- Challenge's cause: ORA-00020 maximum processes exceeded).
-- =============================================================================
SELECT resource_name, current_utilization, max_utilization, limit_value
FROM   v$resource_limit
WHERE  resource_name IN ('processes', 'sessions');


-- =============================================================================
-- (B5) Troubleshooting Challenge support — find which program/host is
-- holding an unusually large number of dedicated server connections open.
-- =============================================================================
SELECT machine, program, server, COUNT(*) AS session_count,
       MIN(logon_time) AS oldest_logon,
       MAX(logon_time) AS newest_logon
FROM   v$session
WHERE  type = 'USER'
GROUP BY machine, program, server
ORDER BY session_count DESC;

-- Sessions idle for an unusually long time from the same program are the
-- classic signature of a connection-pool leak (opens new connections,
-- never closes old ones):
SELECT s.sid, s.serial#, s.machine, s.program, s.status,
       s.last_call_et AS seconds_since_last_call,
       p.spid AS os_pid
FROM   v$session s
JOIN   v$process p ON p.addr = s.paddr
WHERE  s.type = 'USER'
AND    s.status = 'INACTIVE'
ORDER BY s.last_call_et DESC;
