-- =============================================================================
-- PERF_LAB Setup — Script 04 of 7
-- 04_generate_data.sql
--
-- Purpose: populate all 10 PERF_LAB tables with realistic, appropriately
-- skewed data at the row-count profile the instructor selects (Small /
-- Standard / Large — see below). Run connected AS perf_lab, after
-- 03_create_indexes.sql:
--   sqlplus perf_lab/<password>@//localhost:1521/PERFPDB @04_generate_data.sql
--
-- -----------------------------------------------------------------------------
-- TIER / SCALE FACTOR
-- -----------------------------------------------------------------------------
-- Every row count below is expressed as "<Standard-tier count> * &c_scale",
-- where &c_scale is a single multiplier prompted for at the top of this
-- script. This is the ONLY thing that changes between tiers — no other
-- logic in this script (or in any dayNN/ script written against PERF_LAB)
-- changes based on tier:
--
--   Small tier    c_scale ~ 0.05 - 0.10   (laptop / Oracle Free-XE VM)
--   Standard tier c_scale = 1             (the row counts in the course
--                                          design doc; 4-8 CPU / 16-32GB VM)
--   Large tier    c_scale ~ 3 - 5         (bigger shared training server)
--
-- Standard-tier base counts (documented in docs/phase1-course-foundation.md
-- and in 02_create_tables.sql's per-table headers):
--   DEPARTMENTS         200
--   EMPLOYEES         10,000
--   CUSTOMERS        500,000
--   PRODUCTS          50,000
--   ORDERS          5,000,000
--   ORDER_ITEMS    20,000,000   (= ORDERS * 4, by construction — see step 6)
--   PAYMENTS        5,000,000   (= ORDERS * 1, by construction — see step 7)
--   TRANSACTIONS   10,000,000
--   SALES          10,000,000
--   LOG_EVENTS     20,000,000
--
-- ENVIRONMENT DEPENDENT / instructor note: total runtime for a full Standard-
-- tier load depends entirely on your storage I/O throughput, CPU core count,
-- and whether you've put PERF_LAB_DATA in NOLOGGING mode — this script does
-- NOT assume or set NOLOGGING (that is a deliberate instructor decision,
-- since it affects recoverability; see the note before step 6). As a rough
-- order-of-magnitude sense so a long run doesn't look "stuck": expect this
-- to run from tens of minutes up to a few hours on typical lab hardware for
-- the Standard tier, with ORDER_ITEMS and LOG_EVENTS (the two 20-million-row
-- tables) dominating total elapsed time. The Large tier can run considerably
-- longer (hours) — consider running it in the background (nohup) or
-- overnight rather than at a terminal.
--
-- -----------------------------------------------------------------------------
-- ROW-GENERATION TECHNIQUE
-- -----------------------------------------------------------------------------
-- Every table below is populated with a single set-based INSERT ... SELECT
-- using a two-level CONNECT BY row generator, NOT a row-by-row PL/SQL loop —
-- a PL/SQL loop inserting one row per iteration is unrealistically slow for
-- the 10-20 million row tables here. The generator pattern, used repeatedly:
--
--   SELECT (d1.n - 1) * 5000 + d2.n AS rn, ...
--   FROM   (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= CEIL(<target>/5000)) d1,
--          (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= 5000) d2
--   WHERE  (d1.n - 1) * 5000 + d2.n <= <target>
--
-- This produces rn = 1 .. <target> using two shallow CONNECT BY recursions
-- (depth <= 5000 each) cross-joined, instead of one CONNECT BY LEVEL <=
-- <target> recursion directly — direct single-level recursion into the tens
-- of millions is measurably slower and more memory-hungry than the two-level
-- cross-join form. The same shape is reused for every table so the scale
-- factor is the only moving part.
--
-- Every INSERT uses the APPEND hint (direct-path load) to minimize UNDO and
-- speed the load. Direct-path inserts are NOT visible to a query in the same
-- uncommitted transaction, so a COMMIT follows every table's load, before
-- any verification SELECT against that table.
--
-- FOREIGN KEYS ARE LEFT ENABLED throughout this script (not disabled and
-- re-validated afterward) so that what lands in PERF_LAB is a genuinely
-- referentially-valid dataset, not one that merely looks valid. Tables are
-- therefore loaded in dependency order: DEPARTMENTS, EMPLOYEES, CUSTOMERS,
-- PRODUCTS, ORDERS, ORDER_ITEMS, PAYMENTS, TRANSACTIONS, SALES, LOG_EVENTS.
-- If Large-tier load time becomes a real problem on your hardware, disabling
-- non-essential FK constraints for the load and re-enabling with NOVALIDATE
-- is a known technique — deliberately NOT done here, to keep this script
-- simple and its result unambiguous.
--
-- SCOPE NOTE: header/detail consistency is deliberately NOT enforced across
-- a few table pairs, to keep generation fast and simple — e.g. ORDERS.
-- order_total is independently randomized rather than derived from summing
-- the matching ORDER_ITEMS rows, and PAYMENTS.amount/payment_date are
-- independently randomized rather than derived from the linked ORDER row.
-- Referential integrity (the FKs) is fully real and enforced; business-level
-- numeric consistency between a header and its details is not. No day in
-- this course relies on ORDERS.order_total reconciling to SUM(ORDER_ITEMS.
-- line_total) — if you add a demo that does, generate that reconciliation
-- yourself in that day's own setup.sql rather than assuming it here.
-- =============================================================================

SET DEFINE ON
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK ON
SET TIMING ON
SET ECHO OFF

PROMPT
PROMPT ================================================================================
PROMPT  PERF_LAB Setup — Step 4: generate data
PROMPT ================================================================================
PROMPT

ACCEPT c_scale NUMBER DEFAULT 1 PROMPT 'Scale factor relative to Standard tier (Small ~0.05-0.10, Standard 1, Large 3-5) [1]: '

PROMPT
PROMPT Using c_scale = &c_scale  (Standard-tier row counts above are multiplied by this)
PROMPT

-- =============================================================================
-- 1. DEPARTMENTS — target ROUND(200 * &c_scale)
--
-- manager_id is left NULL here; it is backfilled in step 2b once EMPLOYEES
-- exists (DEPARTMENTS <-> EMPLOYEES is a genuine circular reference — see
-- 02_create_tables.sql's header for the same point at DDL time).
-- =============================================================================
PROMPT Generating DEPARTMENTS ...

INSERT /*+ APPEND */ INTO departments (
  department_id, department_code, department_name, cost_center, location
)
SELECT
  rn,
  'DEPT-' || LPAD(rn, 4, '0'),
  CASE MOD(rn,10)
    WHEN 0 THEN 'Sales' WHEN 1 THEN 'Marketing' WHEN 2 THEN 'Engineering'
    WHEN 3 THEN 'Finance' WHEN 4 THEN 'Human Resources' WHEN 5 THEN 'Operations'
    WHEN 6 THEN 'Customer Support' WHEN 7 THEN 'Information Technology'
    WHEN 8 THEN 'Legal' ELSE 'Procurement'
  END || ' Dept ' || rn,
  'CC-' || LPAD(rn, 4, '0'),
  CASE MOD(rn,6)
    WHEN 0 THEN 'Chicago, IL' WHEN 1 THEN 'Dallas, TX' WHEN 2 THEN 'Atlanta, GA'
    WHEN 3 THEN 'Denver, CO' WHEN 4 THEN 'Phoenix, AZ' ELSE 'Seattle, WA'
  END
FROM (
  SELECT (d1.n - 1) * 5000 + d2.n AS rn
  FROM   (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= CEIL(ROUND(200*&c_scale)/5000)) d1,
         (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= 5000) d2
  WHERE  (d1.n - 1) * 5000 + d2.n <= ROUND(200*&c_scale)
);

COMMIT;
PROMPT ---- DEPARTMENTS row count ----
SELECT COUNT(*) AS departments_loaded FROM departments;

-- =============================================================================
-- 2. EMPLOYEES — target ROUND(10000 * &c_scale)
--
-- manager_id is left NULL on this INSERT (same circular-reference reason as
-- DEPARTMENTS above: a self-referencing FK generated in a single INSERT ...
-- SELECT is not guaranteed to see earlier rows of the same statement as
-- committed parent data, so the hierarchy is built with a separate UPDATE
-- in step 2a, once every employee row already exists and is visible).
-- =============================================================================
PROMPT Generating EMPLOYEES ...

INSERT /*+ APPEND */ INTO employees (
  employee_id, employee_number, first_name, last_name, email, phone,
  hire_date, job_title, department_id, salary, employee_status
)
SELECT
  rn,
  'EMP-' || LPAD(rn, 7, '0'),
  fname,
  lname,
  LOWER(fname) || '.' || LOWER(lname) || '.' || rn || '@perflabcorp.example',
  '555-' || LPAD(TRUNC(DBMS_RANDOM.VALUE(2000000,9999999)), 7, '0'),
  DATE '2010-01-01' + TRUNC(DBMS_RANDOM.VALUE(0,5844)),
  CASE MOD(rn,12)
    WHEN 0 THEN 'Software Engineer' WHEN 1 THEN 'Senior Software Engineer'
    WHEN 2 THEN 'Database Administrator' WHEN 3 THEN 'Sales Representative'
    WHEN 4 THEN 'Account Manager' WHEN 5 THEN 'Marketing Specialist'
    WHEN 6 THEN 'HR Coordinator' WHEN 7 THEN 'Financial Analyst'
    WHEN 8 THEN 'Operations Manager' WHEN 9 THEN 'Customer Support Rep'
    WHEN 10 THEN 'IT Support Specialist' ELSE 'VP Operations'
  END,
  MOD(rn - 1, ROUND(200*&c_scale)) + 1,
  ROUND(DBMS_RANDOM.VALUE(45000,180000), 2),
  CASE WHEN rnd_st < 0.92 THEN 'ACTIVE'
       WHEN rnd_st < 0.97 THEN 'ON_LEAVE'
       ELSE 'TERMINATED'
  END
FROM (
  SELECT (d1.n - 1) * 5000 + d2.n AS rn,
         CASE MOD((d1.n - 1) * 5000 + d2.n,12)
           WHEN 0 THEN 'James' WHEN 1 THEN 'Mary' WHEN 2 THEN 'Robert' WHEN 3 THEN 'Patricia'
           WHEN 4 THEN 'John' WHEN 5 THEN 'Jennifer' WHEN 6 THEN 'Michael' WHEN 7 THEN 'Linda'
           WHEN 8 THEN 'David' WHEN 9 THEN 'Elizabeth' WHEN 10 THEN 'William' ELSE 'Barbara'
         END AS fname,
         CASE MOD((d1.n - 1) * 5000 + d2.n,13)
           WHEN 0 THEN 'Smith' WHEN 1 THEN 'Johnson' WHEN 2 THEN 'Williams' WHEN 3 THEN 'Brown'
           WHEN 4 THEN 'Jones' WHEN 5 THEN 'Garcia' WHEN 6 THEN 'Miller' WHEN 7 THEN 'Davis'
           WHEN 8 THEN 'Rodriguez' WHEN 9 THEN 'Martinez' WHEN 10 THEN 'Wilson'
           WHEN 11 THEN 'Anderson' ELSE 'Taylor'
         END AS lname,
         DBMS_RANDOM.VALUE AS rnd_st
  FROM   (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= CEIL(ROUND(10000*&c_scale)/5000)) d1,
         (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= 5000) d2
  WHERE  (d1.n - 1) * 5000 + d2.n <= ROUND(10000*&c_scale)
);

COMMIT;
PROMPT ---- EMPLOYEES row count ----
SELECT COUNT(*) AS employees_loaded FROM employees;

-- -----------------------------------------------------------------------------
-- 2a. Backfill EMPLOYEES.manager_id — a clean pyramid hierarchy, branching
-- factor 8, employee_id 1 as the sole root (CEO, manager_id NULL). The
-- formula TRUNC((employee_id-2)/8)+1 is monotonically non-decreasing and
-- always strictly less than employee_id for employee_id >= 2, so every
-- manager_id this UPDATE assigns already exists — no ORA-02291 risk.
-- -----------------------------------------------------------------------------
PROMPT Backfilling EMPLOYEES.manager_id (org hierarchy) ...

UPDATE employees
SET    manager_id = CASE WHEN employee_id = 1 THEN NULL
                          ELSE TRUNC((employee_id - 2) / 8) + 1
                     END;

COMMIT;

-- -----------------------------------------------------------------------------
-- 2b. Backfill DEPARTMENTS.manager_id now that EMPLOYEES exists.
-- -----------------------------------------------------------------------------
PROMPT Backfilling DEPARTMENTS.manager_id ...

UPDATE departments
SET    manager_id = MOD(department_id - 1, ROUND(10000*&c_scale)) + 1;

COMMIT;

-- =============================================================================
-- 3. CUSTOMERS — target ROUND(500000 * &c_scale)
--
-- *** DELIBERATE SKEW — do not "fix" this — see 02_create_tables.sql and
-- Day 24's cardinality/histogram lab, which depends on it being exactly
-- this lopsided: ***
--   REGION:          WEST 40%, EAST 25%, CENTRAL 15%  (= 80% in 3 of 6 values)
--                     NORTH/SOUTH/INTERNATIONAL split the remaining 20%
--   CUSTOMER_STATUS:  ACTIVE 70%, INACTIVE 20%, SUSPENDED 7%, CLOSED 3%
-- =============================================================================
PROMPT Generating CUSTOMERS ...

INSERT /*+ APPEND */ INTO customers (
  customer_id, customer_number, first_name, last_name, email, phone,
  address_line1, address_line2, city, state_province, postal_code,
  region, customer_status, customer_type, credit_limit, date_registered, last_order_date
)
SELECT
  rn,
  'CUST-' || LPAD(rn, 9, '0'),
  fname,
  lname,
  LOWER(fname) || '.' || LOWER(lname) || '.' || rn || '@example.com',
  '555-' || LPAD(TRUNC(DBMS_RANDOM.VALUE(2000000,9999999)), 7, '0'),
  rn || ' ' || street,
  CASE WHEN MOD(rn,5) = 0 THEN 'Suite ' || MOD(rn,400) ELSE NULL END,
  city,
  st,
  LPAD(MOD(rn,99999), 5, '0'),
  CASE WHEN rnd_region < 0.40 THEN 'WEST'
       WHEN rnd_region < 0.65 THEN 'EAST'
       WHEN rnd_region < 0.80 THEN 'CENTRAL'
       WHEN rnd_region < 0.867 THEN 'NORTH'
       WHEN rnd_region < 0.933 THEN 'SOUTH'
       ELSE 'INTERNATIONAL'
  END,
  CASE WHEN rnd_status < 0.70 THEN 'ACTIVE'
       WHEN rnd_status < 0.90 THEN 'INACTIVE'
       WHEN rnd_status < 0.97 THEN 'SUSPENDED'
       ELSE 'CLOSED'
  END,
  CASE WHEN rnd_type < 0.75 THEN 'RETAIL'
       WHEN rnd_type < 0.93 THEN 'WHOLESALE'
       ELSE 'VIP'
  END,
  ROUND(DBMS_RANDOM.VALUE(0,25000), 2),
  DATE '2019-01-01' + TRUNC(DBMS_RANDOM.VALUE(0,2500)),
  CASE WHEN rnd_status < 0.70 THEN DATE '2024-01-01' + TRUNC(DBMS_RANDOM.VALUE(0,730)) ELSE NULL END
FROM (
  SELECT (d1.n - 1) * 5000 + d2.n AS rn,
         CASE MOD((d1.n - 1) * 5000 + d2.n,12)
           WHEN 0 THEN 'James' WHEN 1 THEN 'Mary' WHEN 2 THEN 'Robert' WHEN 3 THEN 'Patricia'
           WHEN 4 THEN 'John' WHEN 5 THEN 'Jennifer' WHEN 6 THEN 'Michael' WHEN 7 THEN 'Linda'
           WHEN 8 THEN 'David' WHEN 9 THEN 'Elizabeth' WHEN 10 THEN 'William' ELSE 'Barbara'
         END AS fname,
         CASE MOD((d1.n - 1) * 5000 + d2.n,13)
           WHEN 0 THEN 'Smith' WHEN 1 THEN 'Johnson' WHEN 2 THEN 'Williams' WHEN 3 THEN 'Brown'
           WHEN 4 THEN 'Jones' WHEN 5 THEN 'Garcia' WHEN 6 THEN 'Miller' WHEN 7 THEN 'Davis'
           WHEN 8 THEN 'Rodriguez' WHEN 9 THEN 'Martinez' WHEN 10 THEN 'Wilson'
           WHEN 11 THEN 'Anderson' ELSE 'Taylor'
         END AS lname,
         CASE MOD((d1.n - 1) * 5000 + d2.n,8)
           WHEN 0 THEN 'Main St' WHEN 1 THEN 'Oak Ave' WHEN 2 THEN 'Maple Dr' WHEN 3 THEN 'Cedar Ln'
           WHEN 4 THEN 'Elm St' WHEN 5 THEN 'Park Blvd' WHEN 6 THEN 'Sunset Rd' ELSE 'River Way'
         END AS street,
         CASE MOD((d1.n - 1) * 5000 + d2.n,10)
           WHEN 0 THEN 'Chicago' WHEN 1 THEN 'Dallas' WHEN 2 THEN 'Atlanta' WHEN 3 THEN 'Denver'
           WHEN 4 THEN 'Phoenix' WHEN 5 THEN 'Seattle' WHEN 6 THEN 'Boston' WHEN 7 THEN 'Miami'
           WHEN 8 THEN 'Columbus' ELSE 'Portland'
         END AS city,
         CASE MOD((d1.n - 1) * 5000 + d2.n,10)
           WHEN 0 THEN 'IL' WHEN 1 THEN 'TX' WHEN 2 THEN 'GA' WHEN 3 THEN 'CO'
           WHEN 4 THEN 'AZ' WHEN 5 THEN 'WA' WHEN 6 THEN 'MA' WHEN 7 THEN 'FL'
           WHEN 8 THEN 'OH' ELSE 'OR'
         END AS st,
         DBMS_RANDOM.VALUE AS rnd_region,
         DBMS_RANDOM.VALUE AS rnd_status,
         DBMS_RANDOM.VALUE AS rnd_type
  FROM   (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= CEIL(ROUND(500000*&c_scale)/5000)) d1,
         (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= 5000) d2
  WHERE  (d1.n - 1) * 5000 + d2.n <= ROUND(500000*&c_scale)
);

COMMIT;
PROMPT ---- CUSTOMERS row count ----
SELECT COUNT(*) AS customers_loaded FROM customers;

PROMPT ---- CUSTOMERS region skew (sanity check — WEST/EAST/CENTRAL should sum to roughly 80%) ----
COLUMN region FORMAT A16
SELECT region, COUNT(*) AS cnt, ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM   customers
GROUP  BY region
ORDER  BY cnt DESC;

-- =============================================================================
-- 4. PRODUCTS — target ROUND(50000 * &c_scale)
-- =============================================================================
PROMPT Generating PRODUCTS ...

INSERT /*+ APPEND */ INTO products (
  product_id, product_sku, product_name, category, subcategory, brand,
  unit_price, unit_cost, product_status, is_discontinued, weight_kg
)
SELECT
  rn,
  'SKU-' || LPAD(rn, 8, '0'),
  brand || ' ' || category || ' Model ' || rn,
  category,
  category || ' - ' || CASE MOD(rn,4) WHEN 0 THEN 'Standard' WHEN 1 THEN 'Premium'
                                        WHEN 2 THEN 'Economy' ELSE 'Pro' END,
  brand,
  unit_price,
  ROUND(unit_price * DBMS_RANDOM.VALUE(0.4,0.7), 2),
  CASE WHEN rnd_status < 0.85 THEN 'ACTIVE'
       WHEN rnd_status < 0.95 THEN 'DISCONTINUED'
       ELSE 'OUT_OF_STOCK'
  END,
  CASE WHEN rnd_status < 0.85 THEN 'N'
       WHEN rnd_status < 0.95 THEN 'Y'
       ELSE 'N'
  END,
  ROUND(DBMS_RANDOM.VALUE(0.05,25), 3)
FROM (
  SELECT (d1.n - 1) * 5000 + d2.n AS rn,
         CASE MOD((d1.n - 1) * 5000 + d2.n,8)
           WHEN 0 THEN 'Electronics' WHEN 1 THEN 'Apparel' WHEN 2 THEN 'Home & Garden'
           WHEN 3 THEN 'Sporting Goods' WHEN 4 THEN 'Toys & Games' WHEN 5 THEN 'Books'
           WHEN 6 THEN 'Health & Beauty' ELSE 'Automotive'
         END AS category,
         CASE MOD((d1.n - 1) * 5000 + d2.n,10)
           WHEN 0 THEN 'Acme' WHEN 1 THEN 'Zenith' WHEN 2 THEN 'Northpoint' WHEN 3 THEN 'BlueRiver'
           WHEN 4 THEN 'Vertex' WHEN 5 THEN 'Summit' WHEN 6 THEN 'Cascade' WHEN 7 THEN 'Ironclad'
           WHEN 8 THEN 'Meridian' ELSE 'Anchor'
         END AS brand,
         ROUND(DBMS_RANDOM.VALUE(5,1000), 2) AS unit_price,
         DBMS_RANDOM.VALUE AS rnd_status
  FROM   (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= CEIL(ROUND(50000*&c_scale)/5000)) d1,
         (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= 5000) d2
  WHERE  (d1.n - 1) * 5000 + d2.n <= ROUND(50000*&c_scale)
);

COMMIT;
PROMPT ---- PRODUCTS row count ----
SELECT COUNT(*) AS products_loaded FROM products;

-- =============================================================================
-- 5. ORDERS — target ROUND(5000000 * &c_scale)
--    order_date spans a fixed 2024-01-01 .. ~2025-12-31 window (matches the
--    interval-partitioning boundary in 02_create_tables.sql and the SALES
--    boundary in step 9 below — Day 27's partition-wise join needs both
--    tables' monthly partitions aligned). Adjust both boundaries together
--    if you want the data to read as "current" for your class date.
-- =============================================================================
PROMPT Generating ORDERS (this populates an interval-partitioned table — Oracle
PROMPT will create each monthly partition automatically as it is first needed) ...

INSERT /*+ APPEND */ INTO orders (
  order_id, customer_id, order_date, order_status, order_channel, ship_date,
  required_date, order_total, tax_amount, shipping_amount, discount_amount,
  payment_method, shipping_address_line1, shipping_city, shipping_state,
  shipping_postal_code, sales_rep_id, notes
)
SELECT
  rn,
  MOD(rn - 1, ROUND(500000*&c_scale)) + 1,
  ord_date,
  ord_status,
  CASE WHEN rnd_channel < 0.55 THEN 'WEB'
       WHEN rnd_channel < 0.80 THEN 'MOBILE'
       WHEN rnd_channel < 0.92 THEN 'STORE'
       ELSE 'PHONE'
  END,
  CASE WHEN ord_status IN ('PENDING','PROCESSING','CANCELLED') THEN NULL
       ELSE ord_date + TRUNC(DBMS_RANDOM.VALUE(1,7))
  END,
  ord_date + TRUNC(DBMS_RANDOM.VALUE(3,14)),
  ord_total,
  ROUND(ord_total * 0.07, 2),
  ROUND(DBMS_RANDOM.VALUE(0,25), 2),
  CASE WHEN rnd_disc < 0.2 THEN ROUND(ord_total * 0.10, 2) ELSE 0 END,
  CASE MOD(rn,4) WHEN 0 THEN 'CREDIT_CARD' WHEN 1 THEN 'DEBIT_CARD'
                 WHEN 2 THEN 'PAYPAL' ELSE 'BANK_TRANSFER' END,
  rn || ' Shipping Way',
  CASE MOD(rn,10)
    WHEN 0 THEN 'Chicago' WHEN 1 THEN 'Dallas' WHEN 2 THEN 'Atlanta' WHEN 3 THEN 'Denver'
    WHEN 4 THEN 'Phoenix' WHEN 5 THEN 'Seattle' WHEN 6 THEN 'Boston' WHEN 7 THEN 'Miami'
    WHEN 8 THEN 'Columbus' ELSE 'Portland'
  END,
  CASE MOD(rn,10)
    WHEN 0 THEN 'IL' WHEN 1 THEN 'TX' WHEN 2 THEN 'GA' WHEN 3 THEN 'CO'
    WHEN 4 THEN 'AZ' WHEN 5 THEN 'WA' WHEN 6 THEN 'MA' WHEN 7 THEN 'FL'
    WHEN 8 THEN 'OH' ELSE 'OR'
  END,
  LPAD(MOD(rn,99999), 5, '0'),
  CASE WHEN rnd_rep < 0.70 THEN MOD(rn - 1, ROUND(10000*&c_scale)) + 1 ELSE NULL END,
  CASE WHEN MOD(rn,25) = 0 THEN 'Customer requested expedited handling.' ELSE NULL END
FROM (
  -- Note the two-level nesting here: ord_status is derived from rnd_status
  -- one query block OUT from where rnd_status is defined, not alongside it
  -- — a CASE expression cannot reference a sibling column alias within the
  -- same SELECT list (rnd_status wouldn't be resolvable yet at that point).
  SELECT rn, ord_date, ord_total, rnd_channel, rnd_disc, rnd_rep,
         CASE WHEN rnd_status < 0.55 THEN 'DELIVERED'
              WHEN rnd_status < 0.70 THEN 'SHIPPED'
              WHEN rnd_status < 0.80 THEN 'PROCESSING'
              WHEN rnd_status < 0.88 THEN 'PENDING'
              WHEN rnd_status < 0.95 THEN 'CANCELLED'
              ELSE 'RETURNED'
         END AS ord_status
  FROM (
    SELECT (d1.n - 1) * 5000 + d2.n AS rn,
           DATE '2024-01-01' + TRUNC(DBMS_RANDOM.VALUE(0,730)) AS ord_date,
           ROUND(DBMS_RANDOM.VALUE(20,2000), 2) AS ord_total,
           DBMS_RANDOM.VALUE AS rnd_status,
           DBMS_RANDOM.VALUE AS rnd_channel,
           DBMS_RANDOM.VALUE AS rnd_disc,
           DBMS_RANDOM.VALUE AS rnd_rep
    FROM   (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= CEIL(ROUND(5000000*&c_scale)/5000)) d1,
           (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= 5000) d2
    WHERE  (d1.n - 1) * 5000 + d2.n <= ROUND(5000000*&c_scale)
  )
);

COMMIT;
PROMPT ---- ORDERS row count ----
SELECT COUNT(*) AS orders_loaded FROM orders;
PROMPT ---- ORDERS partitions created so far (interval partitioning) ----
SELECT COUNT(*) AS orders_partitions FROM user_tab_partitions WHERE table_name = 'ORDERS';

-- =============================================================================
-- 6. ORDER_ITEMS — target = ORDERS row count * 4 (exactly), i.e.
--    ROUND(5000000*&c_scale) * 4, which equals ROUND(20000000*&c_scale) up
--    to rounding at the edges — close enough for a lab dataset, and it
--    guarantees a clean, even 4-items-per-order pattern via
--    order_id = CEIL(rn/4), line_number = MOD(rn-1,4)+1.
--
-- This is the single largest INSERT in this script — 20,000,000 rows at
-- Standard tier. ENVIRONMENT DEPENDENT: if you want to trade recoverability
-- for load speed here, put PERF_LAB_DATA in NOLOGGING and add the NOLOGGING
-- keyword to this table before running this step; not done by default.
-- =============================================================================
PROMPT Generating ORDER_ITEMS (largest table — this is typically the longest-running step) ...

INSERT /*+ APPEND */ INTO order_items (
  order_item_id, order_id, product_id, line_number, quantity, unit_price,
  discount_pct, line_total, tax_amount
)
SELECT
  rn,
  CEIL(rn / 4),
  MOD(rn - 1, ROUND(50000*&c_scale)) + 1,
  MOD(rn - 1, 4) + 1,
  qty,
  price,
  disc,
  ROUND(qty * price * (1 - disc/100), 2),
  ROUND(qty * price * (1 - disc/100) * 0.07, 2)
FROM (
  SELECT (d1.n - 1) * 5000 + d2.n AS rn,
         TRUNC(DBMS_RANDOM.VALUE(1,10)) AS qty,
         ROUND(DBMS_RANDOM.VALUE(5,500), 2) AS price,
         CASE WHEN DBMS_RANDOM.VALUE < 0.15 THEN ROUND(DBMS_RANDOM.VALUE(5,30), 2) ELSE 0 END AS disc
  FROM   (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= CEIL((ROUND(5000000*&c_scale)*4)/5000)) d1,
         (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= 5000) d2
  WHERE  (d1.n - 1) * 5000 + d2.n <= ROUND(5000000*&c_scale) * 4
);

COMMIT;
PROMPT ---- ORDER_ITEMS row count ----
SELECT COUNT(*) AS order_items_loaded FROM order_items;

-- =============================================================================
-- 7. PAYMENTS — target ROUND(5000000 * &c_scale), one payment per order
--    (order_id = rn maps 1:1 onto the ORDERS just generated, since both
--    use the identical ROUND(5000000*&c_scale) target). A real system would
--    have some orders with zero, or more than one, payment attempt — kept
--    1:1 here purely to keep the generator simple; nothing in this course
--    depends on that ratio being anything other than "every order has a
--    payment row to join to."
-- =============================================================================
PROMPT Generating PAYMENTS ...

INSERT /*+ APPEND */ INTO payments (
  payment_id, order_id, payment_date, payment_status, amount, card_last4,
  authorization_code, gateway_reference, processed_at
)
SELECT
  rn,
  rn,
  pay_date,
  CASE WHEN rnd_status < 0.70 THEN 'CAPTURED'
       WHEN rnd_status < 0.80 THEN 'AUTHORIZED'
       WHEN rnd_status < 0.85 THEN 'PENDING'
       WHEN rnd_status < 0.93 THEN 'FAILED'
       WHEN rnd_status < 0.98 THEN 'REFUNDED'
       ELSE 'VOIDED'
  END,
  ROUND(DBMS_RANDOM.VALUE(20,2000), 2),
  LPAD(TRUNC(DBMS_RANDOM.VALUE(0,9999)), 4, '0'),
  'AUTH' || LPAD(TRUNC(DBMS_RANDOM.VALUE(0,999999)), 6, '0'),
  'GWY-' || LPAD(rn, 10, '0'),
  CAST(pay_date AS TIMESTAMP) + NUMTODSINTERVAL(DBMS_RANDOM.VALUE(60,3600), 'SECOND')
FROM (
  SELECT (d1.n - 1) * 5000 + d2.n AS rn,
         DATE '2024-01-01' + TRUNC(DBMS_RANDOM.VALUE(0,733)) AS pay_date,
         DBMS_RANDOM.VALUE AS rnd_status
  FROM   (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= CEIL(ROUND(5000000*&c_scale)/5000)) d1,
         (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= 5000) d2
  WHERE  (d1.n - 1) * 5000 + d2.n <= ROUND(5000000*&c_scale)
);

COMMIT;
PROMPT ---- PAYMENTS row count ----
SELECT COUNT(*) AS payments_loaded FROM payments;

-- =============================================================================
-- 8. TRANSACTIONS — target ROUND(10000000 * &c_scale)
--    Deliberately NOT foreign-keyed (see 02_create_tables.sql) — account_id
--    and reference_id are loose numeric pointers into the CUSTOMERS/ORDERS
--    ID space, not enforced. amount is unsigned; transaction_type carries
--    the ledger direction (a common GL convention), so no negative amounts.
-- =============================================================================
PROMPT Generating TRANSACTIONS ...

INSERT /*+ APPEND */ INTO transactions (
  transaction_id, transaction_date, transaction_type, account_id,
  reference_type, reference_id, amount, gl_account_code, description
)
SELECT
  rn,
  DATE '2024-01-01' + TRUNC(DBMS_RANDOM.VALUE(0,960)),
  CASE WHEN rnd_type < 0.35 THEN 'DEBIT'
       WHEN rnd_type < 0.70 THEN 'CREDIT'
       WHEN rnd_type < 0.80 THEN 'ADJUSTMENT'
       WHEN rnd_type < 0.92 THEN 'FEE'
       ELSE 'REFUND'
  END,
  TRUNC(DBMS_RANDOM.VALUE(1, ROUND(500000*&c_scale) + 1)),
  CASE MOD(rn,4) WHEN 0 THEN 'ORDER' WHEN 1 THEN 'PAYMENT' WHEN 2 THEN 'MANUAL' ELSE 'SYSTEM' END,
  TRUNC(DBMS_RANDOM.VALUE(1, ROUND(5000000*&c_scale) + 1)),
  ROUND(DBMS_RANDOM.VALUE(5,5000), 2),
  'GL-' || LPAD(MOD(rn,500), 4, '0'),
  'Auto-generated ledger entry #' || rn
FROM (
  SELECT (d1.n - 1) * 5000 + d2.n AS rn,
         DBMS_RANDOM.VALUE AS rnd_type
  FROM   (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= CEIL(ROUND(10000000*&c_scale)/5000)) d1,
         (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= 5000) d2
  WHERE  (d1.n - 1) * 5000 + d2.n <= ROUND(10000000*&c_scale)
);

COMMIT;
PROMPT ---- TRANSACTIONS row count ----
SELECT COUNT(*) AS transactions_loaded FROM transactions;

-- =============================================================================
-- 9. SALES — target ROUND(10000000 * &c_scale)
--    RANGE PARTITIONED BY SALE_DATE — same 2024-01-01 starting boundary as
--    ORDERS (step 5), required for Day 27's partition-wise join demo.
--    order_id is a loose, sometimes-NULL reference (not FK-enforced — see
--    02_create_tables.sql): about 60% of SALES rows tie back to a web/app
--    order, the rest represent in-store/POS sales with no originating
--    ORDERS row.
-- =============================================================================
PROMPT Generating SALES (interval-partitioned; partitions created automatically) ...

INSERT /*+ APPEND */ INTO sales (
  sale_id, sale_date, product_id, customer_id, region, quantity_sold,
  unit_price, total_amount, order_id
)
SELECT
  rn,
  sale_dt,
  MOD(rn - 1, ROUND(50000*&c_scale)) + 1,
  CASE WHEN rnd_cust < 0.90 THEN MOD(rn - 1, ROUND(500000*&c_scale)) + 1 ELSE NULL END,
  CASE MOD(rn,6)
    WHEN 0 THEN 'WEST' WHEN 1 THEN 'EAST' WHEN 2 THEN 'CENTRAL'
    WHEN 3 THEN 'NORTH' WHEN 4 THEN 'SOUTH' ELSE 'INTERNATIONAL'
  END,
  qty,
  price,
  qty * price,
  CASE WHEN rnd_ord < 0.60 THEN MOD(rn - 1, ROUND(5000000*&c_scale)) + 1 ELSE NULL END
FROM (
  SELECT (d1.n - 1) * 5000 + d2.n AS rn,
         DATE '2024-01-01' + TRUNC(DBMS_RANDOM.VALUE(0,730)) AS sale_dt,
         TRUNC(DBMS_RANDOM.VALUE(1,20)) AS qty,
         ROUND(DBMS_RANDOM.VALUE(5,500), 2) AS price,
         DBMS_RANDOM.VALUE AS rnd_cust,
         DBMS_RANDOM.VALUE AS rnd_ord
  FROM   (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= CEIL(ROUND(10000000*&c_scale)/5000)) d1,
         (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= 5000) d2
  WHERE  (d1.n - 1) * 5000 + d2.n <= ROUND(10000000*&c_scale)
);

COMMIT;
PROMPT ---- SALES row count ----
SELECT COUNT(*) AS sales_loaded FROM sales;
PROMPT ---- SALES partitions created so far ----
SELECT COUNT(*) AS sales_partitions FROM user_tab_partitions WHERE table_name = 'SALES';

-- =============================================================================
-- 10. LOG_EVENTS — target ROUND(20000000 * &c_scale)
--
-- log_timestamp is explicitly spread over the ~180 days before "now" rather
-- than left at its SYSTIMESTAMP default, so this reads as a real historical
-- log instead of 20 million rows all timestamped at load time.
-- =============================================================================
PROMPT Generating LOG_EVENTS (second-largest table) ...

INSERT /*+ APPEND */ INTO log_events (
  log_id, log_timestamp, event_type, event_source, severity, session_id,
  user_id, host_name, message, event_detail
)
SELECT
  rn,
  SYSTIMESTAMP - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(0,180*86400), 'SECOND'),
  evt_type,
  evt_source,
  CASE WHEN rnd_sev < 0.80 THEN 'INFO'
       WHEN rnd_sev < 0.90 THEN 'DEBUG'
       WHEN rnd_sev < 0.96 THEN 'WARN'
       WHEN rnd_sev < 0.99 THEN 'ERROR'
       ELSE 'FATAL'
  END,
  'SESS-' || TRUNC(DBMS_RANDOM.VALUE(1,5000000)),
  TRUNC(DBMS_RANDOM.VALUE(1, ROUND(500000*&c_scale) + ROUND(10000*&c_scale) + 1)),
  'app-srv-' || LPAD(MOD(rn,20) + 1, 2, '0') || '.internal',
  'Auto-generated log message for event ' || rn,
  CASE WHEN MOD(rn,10) = 0 THEN '{"code":' || MOD(rn,999) || ',"note":"synthetic"}' ELSE NULL END
FROM (
  SELECT (d1.n - 1) * 5000 + d2.n AS rn,
         CASE MOD((d1.n - 1) * 5000 + d2.n,8)
           WHEN 0 THEN 'LOGIN' WHEN 1 THEN 'LOGOUT' WHEN 2 THEN 'ORDER_PLACED'
           WHEN 3 THEN 'PAYMENT_PROCESSED' WHEN 4 THEN 'ERROR' WHEN 5 THEN 'API_CALL'
           WHEN 6 THEN 'PAGE_VIEW' ELSE 'SYSTEM_CHECK'
         END AS evt_type,
         CASE MOD((d1.n - 1) * 5000 + d2.n,5)
           WHEN 0 THEN 'WEB_APP' WHEN 1 THEN 'MOBILE_APP' WHEN 2 THEN 'API_GATEWAY'
           WHEN 3 THEN 'BATCH_JOB' ELSE 'ADMIN_CONSOLE'
         END AS evt_source,
         DBMS_RANDOM.VALUE AS rnd_sev
  FROM   (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= CEIL(ROUND(20000000*&c_scale)/5000)) d1,
         (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= 5000) d2
  WHERE  (d1.n - 1) * 5000 + d2.n <= ROUND(20000000*&c_scale)
);

COMMIT;
PROMPT ---- LOG_EVENTS row count ----
SELECT COUNT(*) AS log_events_loaded FROM log_events;

-- =============================================================================
-- 11. Reseed every IDENTITY generator to start beyond the explicit key
-- values just bulk-loaded, so later single-row inserts (day-by-day demos
-- that INSERT ... VALUES without specifying the surrogate key) don't
-- collide with these rows. START WITH LIMIT VALUE re-anchors the identity
-- sequence to (current max + 1) as of now — see 02_create_tables.sql's
-- "SURROGATE KEYS" note for why this two-step (explicit bulk load, then
-- reseed) approach was chosen over letting IDENTITY generate every value.
-- =============================================================================
PROMPT Reseeding IDENTITY generators past the bulk-loaded key ranges ...

ALTER TABLE departments   MODIFY department_id  GENERATED BY DEFAULT ON NULL AS IDENTITY (START WITH LIMIT VALUE);
ALTER TABLE employees     MODIFY employee_id    GENERATED BY DEFAULT ON NULL AS IDENTITY (START WITH LIMIT VALUE);
ALTER TABLE customers     MODIFY customer_id    GENERATED BY DEFAULT ON NULL AS IDENTITY (START WITH LIMIT VALUE);
ALTER TABLE products      MODIFY product_id     GENERATED BY DEFAULT ON NULL AS IDENTITY (START WITH LIMIT VALUE);
ALTER TABLE orders        MODIFY order_id       GENERATED BY DEFAULT ON NULL AS IDENTITY (START WITH LIMIT VALUE);
ALTER TABLE order_items   MODIFY order_item_id  GENERATED BY DEFAULT ON NULL AS IDENTITY (START WITH LIMIT VALUE);
ALTER TABLE payments      MODIFY payment_id     GENERATED BY DEFAULT ON NULL AS IDENTITY (START WITH LIMIT VALUE);
ALTER TABLE transactions  MODIFY transaction_id GENERATED BY DEFAULT ON NULL AS IDENTITY (START WITH LIMIT VALUE);
ALTER TABLE sales         MODIFY sale_id        GENERATED BY DEFAULT ON NULL AS IDENTITY (START WITH LIMIT VALUE);
ALTER TABLE log_events    MODIFY log_id         GENERATED BY DEFAULT ON NULL AS IDENTITY (START WITH LIMIT VALUE);

PROMPT
PROMPT ================================================================================
PROMPT  Data generation summary
PROMPT ================================================================================
SELECT 'DEPARTMENTS'  AS table_name, COUNT(*) AS row_count FROM departments  UNION ALL
SELECT 'EMPLOYEES',           COUNT(*) FROM employees    UNION ALL
SELECT 'CUSTOMERS',           COUNT(*) FROM customers    UNION ALL
SELECT 'PRODUCTS',            COUNT(*) FROM products     UNION ALL
SELECT 'ORDERS',              COUNT(*) FROM orders       UNION ALL
SELECT 'ORDER_ITEMS',         COUNT(*) FROM order_items  UNION ALL
SELECT 'PAYMENTS',            COUNT(*) FROM payments     UNION ALL
SELECT 'TRANSACTIONS',        COUNT(*) FROM transactions UNION ALL
SELECT 'SALES',               COUNT(*) FROM sales        UNION ALL
SELECT 'LOG_EVENTS',          COUNT(*) FROM log_events
ORDER  BY table_name;

PROMPT
PROMPT ================================================================================
PROMPT  Data generation complete.
PROMPT  Next step: 05_create_statistics.sql
PROMPT ================================================================================
PROMPT
