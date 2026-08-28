-- =============================================================================
-- Day 06 -- Architecture Bootcamp IV: How Oracle Executes a Statement
-- setup.sql
--
-- Purpose: put THIS session into a clean, known, reproducible state before
-- running demo.sql. This is deliberately minimal for Day 06 -- there is no
-- new schema object to build (PERF_LAB already exists, built in the parallel
-- lab-environment track). All this script does is:
--   1. Set a predictable SQL*Plus environment
--   2. Turn on row-source execution statistics for this session
--   3. Tag this session with a MODULE/ACTION so it is easy to find in
--      V$SESSION even if other students/cohorts are running the same lab
--      concurrently
--   4. Report this session's SID/SERIAL# and OS process linkage, so students
--      can see -- immediately, before a single demo query runs -- that they
--      already know how to find this (Day 5 callback: session -> server
--      process -> OS process)
--
-- Run connected as: PERF_LAB, or any account with SELECT on PERF_LAB objects
-- plus SELECT on V$SESSION / V$PROCESS / V$MYSTAT / V$STATNAME / V$SQLAREA /
-- V$SQL_PLAN / V$SQL_WORKAREA / V$SESSION_EVENT (granted via SELECT ANY
-- DICTIONARY or explicit V_$ grants in a locked-down environment).
--
-- NOTE ON PERF_LAB COLUMN NAMES: this script (and demo.sql/diagnose.sql/
-- fix.sql) assume CUSTOMERS(CUSTOMER_ID, CUSTOMER_NAME, REGION, STATUS, ...),
-- ORDERS(ORDER_ID, CUSTOMER_ID, ORDER_DATE, STATUS, ...) range-partitioned by
-- ORDER_DATE, and ORDER_ITEMS(ORDER_ITEM_ID, ORDER_ID, PRODUCT_ID, QUANTITY,
-- UNIT_PRICE, ...), consistent with the PERF_LAB design in
-- docs/phase1-course-foundation.md. If the final DDL from the lab-build track
-- names columns differently, adjust these scripts before class -- instructor
-- to verify against a real 19c instance before teaching this day.
-- =============================================================================

SET ECHO ON
SET TIMING ON
SET LINESIZE 200
SET PAGESIZE 100
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK ON

-- Row-source execution statistics ON for this session only. This is what lets
-- later DBMS_XPLAN.DISPLAY_CURSOR(...,'ALLSTATS LAST') style evidence work
-- (full plan-reading technique itself is Day 21-22 -- today we only need the
-- statistics captured, not a deep plan-reading skill).
ALTER SESSION SET STATISTICS_LEVEL = ALL;

-- Tag this session so it is unambiguous in V$SESSION during a shared lab.
BEGIN
  DBMS_APPLICATION_INFO.SET_MODULE(module_name => 'DAY06_BOOTCAMP_IV', action_name => 'SETUP');
END;
/

-- Confirm this session's identity -- SID/SERIAL# -- which demo.sql and
-- diagnose.sql will reuse. This is a direct callback to Day 5, where you
-- first learned to walk from V$SESSION to V$PROCESS to find the OS process
-- actually doing the work.
COLUMN sid_serial NEW_VALUE demo_sid_serial NOPRINT
SELECT sid || ',' || serial# AS sid_serial
FROM   v$session
WHERE  sid = SYS_CONTEXT('USERENV', 'SID');

COLUMN username        FORMAT A15
COLUMN module           FORMAT A20
COLUMN server_process    FORMAT A10
COLUMN spid             FORMAT A10

SELECT s.sid, s.serial#, s.username, s.module, s.server AS server_process,
       p.spid, p.pid
FROM   v$session s
JOIN   v$process p ON p.addr = s.paddr
WHERE  s.sid = SYS_CONTEXT('USERENV', 'SID');

PROMPT ================================================================
PROMPT Day 06 setup complete.
PROMPT This session SID,SERIAL# is: &demo_sid_serial
PROMPT Record it. It identifies the exact session -- and, via V$PROCESS,
PROMPT the exact server process -- you will trace through demo.sql.
PROMPT STATISTICS_LEVEL=ALL is set for this session only; no instance-wide
PROMPT change was made. Proceed to demo.sql.
PROMPT ================================================================
