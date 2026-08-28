-- =============================================================================
-- PERF_LAB Setup — Script 03 of 7
-- 03_create_indexes.sql
--
-- Purpose: establish the STARTING index footprint for the PERF_LAB schema.
--
-- *** THIS IS DELIBERATELY MINIMAL — READ THIS BEFORE ADDING INDEXES ***
--
-- This script does NOT build a tuned index set. Every PRIMARY KEY and
-- UNIQUE constraint in 02_create_tables.sql already created its own
-- supporting unique index automatically — that happened as an unavoidable
-- side effect of the constraint, not as a tuning decision, and this
-- script does not repeat or list those here (see the verification query
-- at the bottom instead).
--
-- Beyond those automatic PK/UNIQUE indexes, this script adds NOTHING.
-- In particular, it does NOT index foreign-key columns such as
-- ORDER_ITEMS.PRODUCT_ID, ORDER_ITEMS.ORDER_ID, ORDERS.CUSTOMER_ID,
-- ORDERS.SALES_REP_ID, PAYMENTS.ORDER_ID, SALES.PRODUCT_ID,
-- SALES.CUSTOMER_ID, or EMPLOYEES.DEPARTMENT_ID/MANAGER_ID — even though
-- indexing FK columns is common, sensible real-world practice (it avoids
-- full scans on the child table during parent-side deletes/updates, and
-- usually helps child-table lookup queries too).
--
-- This is intentional, not an oversight, for two reasons specific to
-- this course's design:
--
--   1. Oracle does NOT require an index on a foreign-key column to
--      enforce referential integrity. Leaving these columns unindexed
--      creates a fully valid, if performance-naive, starting schema —
--      exactly like a great many real production schemas a working DBA
--      actually inherits.
--
--   2. Several days in this course are built specifically around
--      diagnosing and fixing the consequences of that gap:
--        - Day 2  ("Systematic Investigation") demonstrates, end to end,
--          a production incident whose proven root cause IS the missing
--          index on ORDER_ITEMS.PRODUCT_ID — and Day 2's own fix.sql
--          creates that index as the day's conclusion, from evidence,
--          not from this setup script pre-empting the lesson.
--        - Day 23 ("Indexing & Data Access Strategy") is a dedicated lab
--          on designing (and deliberately mis-designing) indexes across
--          this schema; it needs a genuinely under-indexed starting
--          point to teach from.
--        - Day 22's join-method demos and Day 31's contention labs each
--          add whatever narrow, day-specific index or index-avoidance
--          scenario they need in their own setup.sql, layered on top of
--          this baseline rather than assumed to exist here.
--
-- If you are an instructor adapting this course for a context where you
-- do NOT want students to encounter these unindexed-FK problems (for
-- example, using PERF_LAB purely as background data for an unrelated
-- demo), add the missing FK-column indexes yourself after this script —
-- a commented-out template for exactly that is included at the bottom.
--
-- Run connected AS perf_lab, after 02_create_tables.sql.
-- =============================================================================

SET SERVEROUTPUT ON
SET FEEDBACK ON

PROMPT
PROMPT ================================================================================
PROMPT  PERF_LAB Setup — Step 3: index baseline (intentionally minimal)
PROMPT ================================================================================
PROMPT

-- -----------------------------------------------------------------------------
-- Nothing to CREATE here (see the header above). This step exists to
-- VERIFY the automatic PK/UNIQUE index footprint left by 02_create_tables.sql
-- and to make the "what's deliberately NOT indexed yet" gap explicit and
-- auditable, rather than silent.
-- -----------------------------------------------------------------------------

PROMPT ---- Indexes that exist right now (all created automatically by PK/UNIQUE constraints) ----
COLUMN index_name FORMAT A28
COLUMN table_name FORMAT A16
COLUMN uniqueness FORMAT A10
SELECT ui.table_name, ui.index_name, ui.uniqueness, ui.status
FROM   user_indexes ui
ORDER  BY ui.table_name, ui.index_name;

PROMPT
PROMPT ---- Index-to-column mapping for the above ----
COLUMN column_name FORMAT A20
SELECT table_name, index_name, column_position, column_name
FROM   user_ind_columns
ORDER  BY table_name, index_name, column_position;

PROMPT
PROMPT ---- Foreign-key columns that are DELIBERATELY unindexed at baseline ----
-- Cross-references every FK constraint's leading column against the index
-- column list above; any FK column NOT already covered by a PK/UNIQUE
-- index (i.e. every one of them, at this point in setup) is listed here
-- as a reminder of what later days' demos rely on being absent.
COLUMN constraint_name FORMAT A26
SELECT ac.table_name,
       ac.constraint_name,
       acc.column_name          AS fk_column,
       'NOT INDEXED (by design)' AS status
FROM   user_constraints    ac
JOIN   user_cons_columns   acc ON acc.constraint_name = ac.constraint_name
                               AND acc.owner           = ac.owner
WHERE  ac.constraint_type = 'R'                     -- foreign key constraints
AND    acc.position       = 1                       -- leading column of the FK
AND    NOT EXISTS (
         SELECT 1
         FROM   user_ind_columns ic
         WHERE  ic.table_name    = ac.table_name
         AND    ic.column_name   = acc.column_name
         AND    ic.column_position = 1
       )
ORDER  BY ac.table_name, ac.constraint_name;

PROMPT
PROMPT ================================================================================
PROMPT  Index baseline confirmed: PK/UNIQUE indexes only. FK columns listed above
PROMPT  are intentionally unindexed — see the header of this script for why.
PROMPT  Next step: 04_generate_data.sql
PROMPT ================================================================================
PROMPT

-- =============================================================================
-- OPTIONAL — NOT RUN BY DEFAULT.
-- If you are adapting this course and want a conventionally-indexed
-- starting schema instead (i.e. you do NOT want the Day 2 / Day 23
-- lessons to work as designed), uncomment and run the block below AFTER
-- 04_generate_data.sql and 05_create_statistics.sql. Indexes are built
-- LOCAL on the two partitioned tables (ORDERS, SALES) since the FK
-- columns here are not the partition key, and a LOCAL index avoids the
-- global-index partition-maintenance overhead a non-partitioned index
-- would otherwise carry.
-- =============================================================================
/*
CREATE INDEX ix_orders_customer_id       ON orders (customer_id) LOCAL;
CREATE INDEX ix_orders_sales_rep_id      ON orders (sales_rep_id) LOCAL;
CREATE INDEX ix_order_items_order_id     ON order_items (order_id);
CREATE INDEX ix_order_items_product_id   ON order_items (product_id);
CREATE INDEX ix_payments_order_id        ON payments (order_id);
CREATE INDEX ix_sales_product_id         ON sales (product_id) LOCAL;
CREATE INDEX ix_sales_customer_id        ON sales (customer_id) LOCAL;
CREATE INDEX ix_employees_department_id  ON employees (department_id);
CREATE INDEX ix_employees_manager_id     ON employees (manager_id);
*/
