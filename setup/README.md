# PERF_LAB Setup Scripts

These seven scripts build the lab environment used throughout *Oracle Database Performance Tuning & Troubleshooting* (34 days, Oracle 19c baseline): the `PERF_LAB` schema — a 10-table order-processing/payments application with two interval-partitioned tables (`ORDERS`, `SALES`) and deliberately skewed data in `CUSTOMERS` that several later days (notably Day 24's cardinality/histogram lab) are built around. Run them **in order, 00 through 06**, each connected as the account its header specifies:

| # | Script | Run as | What it does |
|---|---|---|---|
| 00 | `00_environment_check.sql` | DBA-privileged account (e.g. `SYSTEM`) | Read-only pre-flight check: 19c version, CDB/PDB setup, privileges. Fix any FAIL before continuing. |
| 01 | `01_create_user.sql` | DBA-privileged account | Creates the `PERF_LAB_DATA` tablespace and the `PERF_LAB` user with the minimum privileges the course needs. **Change the placeholder password.** |
| 02 | `02_create_tables.sql` | `PERF_LAB` | Creates all 10 tables, PK/FK/CHECK constraints, and the two partitioned tables. |
| 03 | `03_create_indexes.sql` | `PERF_LAB` | No new indexes by design — verifies the automatic PK/UNIQUE index baseline and documents which FK columns are intentionally left unindexed (that gap is the setup for Day 2's and Day 23's labs). |
| 04 | `04_generate_data.sql` | `PERF_LAB` | Bulk-loads all 10 tables via set-based `INSERT ... SELECT` row generators — no row-by-row loops. Prompts for a scale factor (see below). |
| 05 | `05_create_statistics.sql` | `PERF_LAB` | Gathers optimizer statistics for the whole schema, forcing histograms on the columns Day 04 deliberately skewed. |
| 06 | `06_verify_environment.sql` | `PERF_LAB` | Read-only final check: actual row counts vs. expected (scaled) counts, object counts, and a stats sanity check, with a PASS/WARN/FAIL summary. |

A typical run looks like:

```
sqlplus system/<password>@//localhost:1521/PERFPDB @00_environment_check.sql
sqlplus system/<password>@//localhost:1521/PERFPDB @01_create_user.sql
sqlplus perf_lab/<password>@//localhost:1521/PERFPDB @02_create_tables.sql
sqlplus perf_lab/<password>@//localhost:1521/PERFPDB @03_create_indexes.sql
sqlplus perf_lab/<password>@//localhost:1521/PERFPDB @04_generate_data.sql
sqlplus perf_lab/<password>@//localhost:1521/PERFPDB @05_create_statistics.sql
sqlplus perf_lab/<password>@//localhost:1521/PERFPDB @06_verify_environment.sql
```

## Small / Standard / Large tiers

The schema's shape (tables, columns, constraints, partitioning, skew) never changes — only the row-count *volume* does, controlled by a single scale factor (`&c_scale`) you're prompted for at the start of `04_generate_data.sql` and again in `06_verify_environment.sql` (enter the same value both times). The Standard-tier row counts documented in each script's header (e.g. `CUSTOMERS` 500,000, `ORDER_ITEMS` 20,000,000) are simply multiplied by this factor:

- **Small tier** — `c_scale` ≈ 0.05–0.10 (roughly 5–10% of Standard). Fits a laptop VM or Oracle Database Free/XE; use this for personal study, a quick smoke-test of a day's demo, or any environment without much disk/CPU to spare.
- **Standard tier** — `c_scale = 1`. The tier the course is designed and timed around: a 4–8 CPU / 16–32 GB VM. This is the default if you just press Enter at the prompt.
- **Large tier** — `c_scale` ≈ 3–5 (roughly 3–5x Standard). For a beefier shared training server where you want I/O-bound and parallelism demos to have more headroom to show a difference.

Pick your tier once, before running `04_generate_data.sql`, based on the hardware you actually have — there is no logic anywhere in `04`–`06` that branches on which tier you chose; it is purely an input to the row-count formulas. Whatever you choose, `06_verify_environment.sql` needs the *same* value to know what counts to expect — if you're setting this up for someone else or returning to it later and aren't sure what was used, that script's header explains how to recover it from the actual row counts.

Data generation and statistics gathering are the two genuinely long-running steps here (everything else — user/table/index creation — completes in seconds). Both scripts flag this as **ENVIRONMENT DEPENDENT** in their own headers with a rough sense of expected duration; at Large tier in particular, expect to run `04` and `05` in the background (e.g. `nohup`) rather than watch them at a terminal.

## Rebuilding the whole environment from scratch

`01_create_user.sql` and `02_create_tables.sql` deliberately assume a clean slate — they are not written to be re-run against a schema that already has these objects, because silently dropping and rebuilding a 20M+ row schema on every run would make `04_generate_data.sql` and `05_create_statistics.sql` painfully slow to iterate on.

If you want to test or rehearse the full build more than once (after changing the scale factor, editing table DDL, or just rehearsing before a cohort starts), run `rebuild_from_scratch.sql` first — connected as the same DBA-privileged account as `01_create_user.sql` — then start again from `01`:

```
sqlplus system/<password>@//localhost:1521/PERFPDB @rebuild_from_scratch.sql
sqlplus system/<password>@//localhost:1521/PERFPDB @01_create_user.sql
sqlplus perf_lab/<password>@//localhost:1521/PERFPDB @02_create_tables.sql
...
```

`rebuild_from_scratch.sql` drops the `PERF_LAB` user (`CASCADE` — every object and row it owns) and the `PERF_LAB_DATA` tablespace (`INCLUDING CONTENTS AND DATAFILES`). It is destructive by design and has no confirmation prompt, so only run it against a disposable training lab instance you mean to wipe.

## Per-day demos are separately re-runnable — no full rebuild needed for those

The environment-rebuild path above is for the base schema only. Every individual day's lab (`dayNN/setup.sql` through `dayNN/reset.sql`) is already designed to be tested and re-run on top of this same base schema as many times as you like without ever touching `setup/`:

- `dayNN/setup.sql` is safe to re-run — it defensively drops/recreates only that day's own demo objects (never the shared PERF_LAB tables) before creating them fresh.
- `dayNN/reset.sql` returns that day's demo to exactly the state `setup.sql` left it in (fix undone, injected problem re-asserted, any generated data/log rows cleared, leftover jobs/sessions cleared) so you can rehearse the same demo end to end again immediately — no need to re-run `setup/00`-`06` in between.
- `dayNN/cleanup.sql` fully tears that day's own objects back out if you want to decommission a day entirely, without affecting the shared schema or any other day.

So the normal workflow for testing a day before class is: `@setup.sql` → `@demo.sql` → `@diagnose.sql` → `@fix.sql` → `@validate.sql` → `@reset.sql` → repeat from `@demo.sql` as many times as you want to rehearse.
