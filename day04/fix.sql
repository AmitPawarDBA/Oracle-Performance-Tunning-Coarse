-- =====================================================================
-- Day 4 — Architecture Bootcamp II — Storage
-- fix.sql — correcting two common misconceptions with live proof
--
-- This is a conceptual/architecture day, not an incident day, so
-- "fix" here means: run a concrete counter-example that corrects a
-- misconception cleanly, with evidence, rather than patch a broken
-- system. Run as PERF_LAB, after demo.sql.
-- =====================================================================


-- #######################################################################
-- MISCONCEPTION 1: "If I made a mistake, I can just ROLLBACK to fix it"
--                    -- even after it was already committed.
--
-- Reality: ROLLBACK only reverses the CURRENT, still-open transaction.
-- Once COMMIT has run, that transaction is over -- there is nothing
-- left for ROLLBACK to undo. A committed change can only be reversed
-- by a NEW transaction that writes the data back (or by DBA-level
-- recovery methods such as Flashback Table/Database/point-in-time
-- recovery, which are entirely different mechanisms from ROLLBACK).
-- #######################################################################

PROMPT ===================================================================
PROMPT MISCONCEPTION 1 - "ROLLBACK undoes committed work" -- FALSE
PROMPT ===================================================================

PROMPT --- Baseline value ---
SELECT order_id, order_total FROM perf_lab.d4_demo_orders WHERE order_id = 1;

PROMPT --- Change it and COMMIT (transaction now CLOSED) ---
UPDATE perf_lab.d4_demo_orders SET order_total = 999.99 WHERE order_id = 1;
COMMIT;

SELECT order_id, order_total FROM perf_lab.d4_demo_orders WHERE order_id = 1;
-- order_total is now 999.99, and it is committed -- durable.

PROMPT --- Now try to "undo the mistake" with ROLLBACK ---
ROLLBACK;

SELECT order_id, order_total FROM perf_lab.d4_demo_orders WHERE order_id = 1;
-- Still 999.99. ROLLBACK had ABSOLUTELY NOTHING to roll back -- the
-- transaction that changed this row ended the instant COMMIT ran.
-- This ROLLBACK, if it affected anything at all, could only have
-- reversed a DIFFERENT, still-open transaction in this same session
-- -- there was none here.

-- Note for the instructor: the ORIGINAL value of order_total for
-- order_id 1 was randomly generated in setup.sql, so this script
-- cannot "know" the original number to restore it programmatically.
-- Restoring it now would require a brand-new UPDATE ... COMMIT with
-- the original value -- which IS the point: committed data can only
-- be fixed by writing new data, never by ROLLBACK. In class, either
-- narrate that and move on, or re-run setup.sql for a fully pristine
-- demo table (see reset.sql).


-- #######################################################################
-- MISCONCEPTION 2: "Undo only exists so you can ROLLBACK."
--
-- Reality: undo has a SECOND, arguably more important, everyday job:
-- serving read-consistent snapshots to queries, including queries
-- that never touch ROLLBACK at all. The block below reads a PAST
-- version of a row using nothing but a flashback query -- zero
-- ROLLBACK statements anywhere in this section.
-- #######################################################################

PROMPT ===================================================================
PROMPT MISCONCEPTION 2 - "Undo is just for ROLLBACK" -- FALSE
PROMPT ===================================================================

PROMPT --- Capture the current value and a timestamp ---
COLUMN order_total FORMAT 999999.99
SELECT SYSTIMESTAMP FROM DUAL;
SELECT order_id, order_total FROM perf_lab.d4_demo_orders WHERE order_id = 2;

PROMPT --- Change it and COMMIT ---
UPDATE perf_lab.d4_demo_orders SET order_total = 111.11 WHERE order_id = 2;
COMMIT;

SELECT order_id, order_total FROM perf_lab.d4_demo_orders WHERE order_id = 2;
-- Now 111.11, committed.

PROMPT --- Read the PRE-CHANGE value with a flashback query (no ROLLBACK) ---
-- Adjust the INTERVAL below to comfortably cover the time between the
-- SYSTIMESTAMP captured above and now (a few minutes is safe for a
-- live class; UNDO_RETENTION defaults to well over that).
SELECT order_id, order_total
FROM   perf_lab.d4_demo_orders AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '2' MINUTE)
WHERE  order_id = 2;

-- This query just reconstructed a row exactly as it looked BEFORE the
-- UPDATE/COMMIT above -- using undo -- with no ROLLBACK statement
-- anywhere in this script. Oracle located the undo records still
-- retained for this block (bounded by UNDO_RETENTION and available
-- undo space) and applied them, in reverse, to the CURRENT block
-- image to reconstruct the OLDER one. This is the exact same
-- mechanism (undo-based block reconstruction) that powers ordinary
-- read consistency for every SELECT running concurrently with
-- writers, all day, every day -- ROLLBACK is only one of undo's
-- consumers, not its purpose.

-- Note: order_id 2 is now permanently 111.11 in this demo table --
-- that is fine for teaching purposes (the row's original random
-- value was never the point). Run setup.sql again for a fully
-- pristine reset (see reset.sql).
