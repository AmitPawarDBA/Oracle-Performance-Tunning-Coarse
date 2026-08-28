-- =============================================================================
-- Day 5 — Architecture Bootcamp III: Process Architecture & Connections
-- fix.sql — resolves the Real-World Scenario ("the connection just hangs")
--
-- Root cause recap: the database instance, listener, and service
-- registration are all healthy. The app server's tnsnames.ora still points
-- at PORT=1522, the listener's old port before last night's maintenance
-- window moved it to the standard PORT=1521. Nothing is listening on 1522
-- any more, and the firewall between the app tier and the DB host silently
-- drops the connection attempt instead of returning a fast refusal — so the
-- client's TCP handshake sits until the OS/SQL*Net connect timeout expires,
-- which is what the app team experiences as "it just hangs."
--
-- The actual fix is a CLIENT-SIDE configuration change (tnsnames.ora on the
-- app server), not a database change — this script documents that fix
-- precisely, plus the DB-side confirmation that nothing on the database
-- itself needed to change (formally closing out the false lead from
-- diagnose.sql section B3).
--
-- NOTE: no live Oracle instance was available while writing this script.
-- Verify the exact host/port/service values against your real 19c instance
-- and lab network topology before class.
-- =============================================================================


-- =============================================================================
-- STEP 1 — Confirm, one more time, exactly what the listener's current
-- endpoint and registered service actually are (run at the OS shell on the
-- database host):
--
--     lsnrctl status
--
-- Expect output containing a block similar to:
--
--   Listening Endpoints Summary...
--     (DESCRIPTION=(ADDRESS=(PROTOCOL=tcp)(HOST=dbhost01.lab.local)(PORT=1521)))
--   Service "perfpdb" has 1 instance(s).
--     Instance "ORCLCDB", status READY, has 2 handler(s) for this service...
--
-- Record the exact HOST and PORT shown here — this is the ground truth the
-- client-side file must match. In this scenario: HOST=dbhost01.lab.local,
-- PORT=1521, SERVICE_NAME=perfpdb.
-- =============================================================================


-- =============================================================================
-- STEP 2 — Correct the client-side tnsnames.ora on the app server.
-- This is a text-file edit, run on the APP SERVER, not in SQL*Plus.
--
-- BEFORE (stale entry, still pointing at the pre-maintenance port):
--
--   PERFPDB =
--     (DESCRIPTION =
--       (ADDRESS = (PROTOCOL = TCP)(HOST = dbhost01.lab.local)(PORT = 1522))
--       (CONNECT_DATA =
--         (SERVER = DEDICATED)
--         (SERVICE_NAME = perfpdb)
--       )
--     )
--
-- AFTER (corrected to match the listener's actual current endpoint from
-- Step 1):
--
--   PERFPDB =
--     (DESCRIPTION =
--       (ADDRESS = (PROTOCOL = TCP)(HOST = dbhost01.lab.local)(PORT = 1521))
--       (CONNECT_DATA =
--         (SERVER = DEDICATED)
--         (SERVICE_NAME = perfpdb)
--       )
--     )
--
-- Only the PORT value changes. Save the file. No listener or database
-- restart is required — this was never a server-side problem.
-- =============================================================================


-- =============================================================================
-- STEP 3 — Formally close out the false lead: confirm the service-
-- registration side (the thing that was suspected first) was, in fact,
-- never broken. This documents why "unregistered service" was ruled out.
-- =============================================================================
SELECT name, value
FROM   v$parameter
WHERE  name = 'service_names';
-- Expect: 'perfpdb' is present. If it had been missing, that WOULD have been
-- the root cause instead, and it would have produced an immediate
-- ORA-12514, not a hang — the symptom itself already argued against this
-- being the cause.

SELECT name, network_name
FROM   dba_services
WHERE  name = 'perfpdb';
-- Expect: one row, confirming the service is defined and known to the
-- instance server-side, independent of any listener.


-- =============================================================================
-- STEP 4 — Optional server-side reinforcement (not required for this fix,
-- but good practice after any listener endpoint change): force an immediate
-- re-registration of every service with every listener the instance knows
-- about, rather than waiting for the next automatic registration interval.
-- Since Oracle 12c this dynamic registration work is performed by the LREG
-- background process, not PMON.
-- =============================================================================
ALTER SYSTEM REGISTER;

-- Confirm registration succeeded by re-running, at the OS shell:
--     lsnrctl services
-- and checking the handler count for "perfpdb" is > 0.
