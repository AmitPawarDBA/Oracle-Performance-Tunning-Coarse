# Day 6 — Architecture Bootcamp IV: How Oracle Executes a Statement (the Bridge Day)

## Topic
How a single SQL statement travels through Oracle's architecture, end to end: parse → optimize → row source generation → execute → fetch. This is the fourth and final day of the Architecture Bootcamp (Days 3–6), and its entire purpose is synthesis — showing that the instance/memory model (Day 3), the storage/redo/undo model (Day 4), and the process model (Day 5) are not four separate topics but four views of the same machine, now shown running together against one statement.

## Duration
60 minutes

## Difficulty
Beginner (last Beginner-tier day — Day 7 begins the Intermediate tier and the course's performance-measurement stages)

## Learning Objectives
By the end of this session, students will be able to:
1. Name, in order, the five stages a SQL statement passes through — parse, optimize, row source generation, execute, fetch — and state which Oracle architecture component each stage uses.
2. Explain the difference between a hard parse and a soft parse in terms of what work is skipped, and identify both from `V$SQL`/`V$SQLAREA` evidence (`LOADS`, `PARSE_CALLS`, `EXECUTIONS`).
3. Trace a single query's execution across the library cache (Day 3), the data dictionary/segment metadata (Day 4), the buffer cache (Day 3), a PGA work area (Day 3), and the server process that drives all of it (Day 5) — by name, not by guesswork.
4. Read basic evidence from `V$SQL`, `V$SQLAREA`, an introductory `V$SQL_PLAN` query, and session-level execution statistics, without yet needing full execution-plan-reading skill (that begins Day 21–22).
5. Given a piece of diagnostic evidence, classify it as belonging to the parse phase, the optimize/plan phase, or the execute/fetch phase — the exact triage instinct Day 7 onward will build on.

## Theory (≈900 words)

Every day of this Architecture Bootcamp so far has deliberately looked at one static piece of Oracle in isolation, with zero performance-tuning framing attached. Day 3 mapped the **instance** — the SGA's memory structures (shared pool, buffer cache, redo log buffer, large pool) and the PGA — against the **database**, the physical files that memory represents, and drew the line between background and foreground processes. Day 4 went underneath the instance to the physical and logical storage model: tablespaces, segments, extents, blocks, and the redo/undo machinery that protects every change a transaction makes. Day 5 put people behind the picture: the listener handing off a connection to a dedicated (or shared) server process, and the fixed cast of background processes — PMON, SMON, DBWn, LGWR, CKPT, ARCn — each with exactly one job. Today does not add a sixth static concept. Today runs all of those pieces at once, in the order Oracle actually uses them, to answer one query. This is the bridge from "here is Oracle's architecture" to "here is how that architecture gets used" — and every stage of the course from Day 7 forward assumes you can trace this path without hesitation.

A statement's life has five stages: **parse, optimize, row source generation, execute, fetch**. Nothing here is new machinery — it is the same instance, same database, same processes already mapped. What is new is the sequence they run in.

**Parse** happens first, entirely inside the shared pool — the same library cache toured in Day 3's `V$SGA`/`V$INSTANCE` walkthrough. The server process (Day 5: this is the dedicated or shared server, the actual OS process working on the session's behalf) takes the raw SQL text, hashes it, and searches the library cache for an existing, shareable cursor with matching text and matching execution environment. If one is found, that is a **soft parse**: the server process reuses the already-parsed representation and, critically, the already-computed execution plan — the optimizer is not invoked at all. If none is found, that is a **hard parse**: the server process must perform syntax checking, semantic checking (resolving every table, column, and privilege reference — which means going straight to the data dictionary, the very views Day 4 used to confirm a table's segment, columns, and constraints), and then hand the statement to the optimizer for full cost-based evaluation. Hard parsing is expensive specifically because semantic checking and optimization both require genuine work against real dictionary data and real object statistics; soft parsing skips almost all of that by trusting a cursor already sitting in the shared pool — placed there by this session or by any other session that ran the identical text. This is exactly why literal SQL text versus bind variables matters so much later in the course (Day 19): every distinct literal value in a WHERE clause forces its own distinct hard parse, one the next session with a different literal cannot reuse.

**Optimize** is where the cost-based optimizer (CBO) decides how to answer the query. It reads object and column statistics out of the data dictionary — the same segment, extent, and block metadata Day 4 introduced when tracing a row down to its physical storage location — to estimate the cardinality of every candidate step, and it weighs access paths (full scan versus index access), join methods, and join order before settling on one plan. This stage runs only on a hard parse; a soft parse means the entire optimize stage is skipped, because a valid plan is already resident in the library cache.

**Row source generation** takes the optimizer's chosen plan — an abstract tree of operations — and turns it into an actual executable structure: a chain of row source procedures the execution engine can call directly. This, too, still lives inside the library cache, alongside the parsed representation and the plan.

**Execute** is where the server process (Day 5, again) actually performs the work the plan describes, and it is where Day 3's memory structures stop being static diagrams and start being touched for real. Every block the plan needs — a table block, an index block — is requested from the buffer cache in the SGA first. If it is already resident, that is a logical read (a cache hit) and the server process uses it directly. If it is not resident, the server process itself performs a physical read from the datafiles — Day 4's physical storage — into a free buffer. If the plan needs to sort or hash data (an `ORDER BY`, a `GROUP BY`, a hash join), the server process allocates a private work area out of its own PGA — Day 3 again: PGA is per-process and private, unlike the shared SGA — sized automatically under Oracle's automatic PGA memory management. If a work area does not fit in the memory Oracle grants it, the excess spills to the temporary tablespace on disk, a preview of Day 29's TEMP-spill diagnosis and not today's focus. Any DML in this statement would additionally engage Day 4's redo and undo mechanisms and Day 5's LGWR/DBWn background processes; today's read-only `SELECT` keeps that path conceptually in view without exercising it.

**Fetch** is the server process returning rows to the client, one array-sized batch at a time, over the same session connection Day 5 traced from listener to dedicated server.

The one sentence worth holding onto: every stage of statement execution is architecture already known, being used in a specific order, by the one process assigned to a session. Parsing lives in the library cache. Optimizing reads the data dictionary. Executing touches the buffer cache and the session's own PGA. All of it is driven start to finish by the server process. Nothing here is new — it is Days 3 through 5, finally shown running.

## Key Concepts
- The five-stage statement lifecycle: parse → optimize → row source generation → execute → fetch
- Hard parse vs. soft parse, and exactly what work a soft parse skips
- The library cache (shared pool, Day 3) as the home of both parsing and cursor sharing
- The data dictionary and object/column statistics (Day 4) as the optimizer's only source of truth
- Row source generation as the translation from abstract plan to executable structure
- The server process (Day 5) as the single active agent behind every stage
- The buffer cache (Day 3) mediating every block access: logical read (cache hit) vs. physical read (disk)
- PGA work areas (Day 3) as the private memory sorts, hashes, and aggregations use
- Why literal SQL vs. bind variables changes hard-parse frequency (previewed here, built out Day 19)
- SELECT vs. DML: today's query never touches redo/undo/LGWR/DBWn, but the path is there for the next transaction

## Important Views / Commands
Kept intentionally introductory — deep-dive tools for each of these start Day 7 onward (parse/cursor detail: Day 19; plan reading: Day 21–22; PGA/work areas: Day 29).

| View / Command | What it shows today | Depth reserved for |
|---|---|---|
| `V$SQL`, `V$SQLAREA` | Parse evidence for one statement: `LOADS` (hard parses), `PARSE_CALLS`, `EXECUTIONS`, `FIRST_LOAD_TIME`, `PARSING_SCHEMA_NAME` | Day 19 (cursor sharing, bind peeking) |
| `V$SQL_SHARED_CURSOR` | Why a textually-identical statement got its own child cursor instead of sharing one | Day 19 |
| `V$SQL_PLAN` | Raw plan-tree shape only — `ID`, `PARENT_ID`, `OPERATION`, `OPTIONS`, `OBJECT_NAME` — evidence that a plan exists, not analysis of it | Day 21–22 (`DBMS_XPLAN`, access paths, join methods) |
| `V$SQL_WORKAREA` | That a sort/hash work area was allocated for this SQL_ID, and whether it ran optimal/one-pass/multi-pass | Day 29 (PGA sizing, TEMP spills) |
| `V$MYSTAT` / `V$SESSTAT` + `V$STATNAME` | Session-level logical reads, physical reads, sorts (memory/disk) — a first taste of execution statistics | Day 10 (full wait/statistics toolkit) |
| `V$SESSION_EVENT` | That this session has recorded wait/event history at all — light touch only | Day 10 (wait event interpretation) |
| `V$SESSION` / `V$PROCESS` | The session and its server process, callback to Day 5 | Day 5 (already covered), reused throughout |
| `DBA_SEGMENTS` / `DBA_TAB_STATISTICS` | The dictionary metadata the optimizer actually read | Day 4 (already covered), Day 24 (statistics deep-dive) |
| `DBMS_SQL.PARSE` | Used in `fix.sql` to time a hard parse against a soft parse directly | — |
| `DBMS_XPLAN.DISPLAY_CURSOR` (named, not run) | Mentioned as the tool that will read plans properly, starting Day 21 | Day 21–22 |

## Practical Demo (8 steps — see `demo.sql` for the exact runnable sequence)

1. **Orient.** Confirm, before running anything: the SGA's shape (`V$SGAINFO`), this session's identity and its server process (`V$SESSION` joined to `V$PROCESS` — Day 5 callback), and that today's uniquely-tagged demo statement is not already in the library cache.
2. **Cold run — force a hard parse.** Run the demo query (a join of `CUSTOMERS`, `ORDERS`, `ORDER_ITEMS` with a `GROUP BY`/`ORDER BY`) with a unique comment tag, guaranteeing the library cache has never seen this exact text. Narrate: parse phase touches the shared pool; semantic checking touches the data dictionary (Day 4); optimize phase runs in full.
3. **Observe the hard-parse evidence.** Query `V$SQLAREA` for the new `SQL_ID`: `LOADS = 1`, `PARSE_CALLS = 1`, `EXECUTIONS = 1`. This row is the proof a hard parse just happened.
4. **Warm run — expect a soft parse.** Run the identical SQL text again, same session, immediately after. Narrate: the library cache lookup now hits; the optimizer is not invoked; the existing plan is reused.
5. **Observe the soft-parse evidence.** Re-query `V$SQLAREA`: `LOADS` is still `1` (no new hard parse), while `PARSE_CALLS` and `EXECUTIONS` have both incremented to `2`. This is the direct, numeric proof of reuse.
6. **Trace block access via buffer cache statistics.** Snapshot `session logical reads` and `physical reads` from `V$MYSTAT` before and after a third execution. Narrate: even on a soft parse, every row still requires a real block request through the buffer cache (Day 3); a miss becomes a physical read from the datafiles (Day 4).
7. **Observe PGA/work area usage for the sort.** Query `V$SQL_WORKAREA` for this `SQL_ID`: the `GROUP BY`/`ORDER BY` and the hash joins each needed a work area, allocated out of this server process's own PGA (Day 3), sized automatically under `PGA_AGGREGATE_TARGET`.
8. **Tie it back to Days 3–5, then reset.** Walk the full correspondence out loud — parse/library cache (Day 3), optimize/dictionary (Day 4), execute/buffer cache+PGA (Day 3)+server process (Day 5), fetch/server process (Day 5) — then reset this session's statistics level and module tag (`demo.sql` does this; `cleanup.sql`/`reset.sql` handle the shared-pool-level reset between cohorts).

**ENVIRONMENT DEPENDENT:** exact millisecond timings, physical-read counts, and buffer-cache-hit ratios in every step above depend on hardware, what a prior run already cached, and instance sizing — the *structure* of the evidence (LOADS staying flat across repeated executions, a work area appearing in `V$SQL_WORKAREA`) is what is guaranteed, never the specific numbers.

## Real-World Scenario — "I understand the pieces. How do they work together for one query?"

This is a **synthesis** scenario, not an incident — nothing is broken, and there is no root cause to find. A new team member who just finished the Architecture Bootcamp is asked by a senior DBA to explain, end to end, what happens when this exact query runs against `PERF_LAB`:

```sql
SELECT c.customer_id, c.customer_name, o.order_id, o.order_date,
       SUM(oi.quantity * oi.unit_price) AS order_total
FROM   perf_lab.customers   c
JOIN   perf_lab.orders      o  ON o.customer_id = c.customer_id
JOIN   perf_lab.order_items oi ON oi.order_id   = o.order_id
WHERE  o.order_date BETWEEN DATE '2026-01-01' AND DATE '2026-01-31'
AND    c.region = 'WEST'
GROUP BY c.customer_id, c.customer_name, o.order_id, o.order_date
ORDER BY order_total DESC;
```

The expected answer, walked out loud, is exactly the lifecycle from Theory, applied to this specific statement:

1. **A client submits the text** over the session connection Day 5 traced from listener to dedicated server. The **server process** for this session receives it.
2. **Parse.** The server process hashes the text and checks the library cache (Day 3's shared pool). First time this exact text (these literals, this whitespace) has run → cache miss → **hard parse**. Semantic checking resolves `CUSTOMERS`, `ORDERS`, and `ORDER_ITEMS` against the data dictionary — the same segment/object metadata walked on Day 4 — confirming they exist, are accessible, and have the referenced columns.
3. **Optimize.** The CBO reads `ORDERS`'s partitioning-by-`ORDER_DATE` metadata and sees the `WHERE` predicate can prune to the January 2026 partition; it reads `CUSTOMERS`'s statistics on the (skewed) `REGION` column to estimate how selective `REGION = 'WEST'` is; it evaluates join order and join method for the three-way join, and decides on a plan — access paths, join methods, join order all fixed at this moment.
4. **Row source generation** turns that plan into an executable row-source tree.
5. **Execute.** The server process walks the tree: it requests each needed block — pruned `ORDERS` partition blocks, matching `CUSTOMERS` blocks, matching `ORDER_ITEMS` blocks — from the **buffer cache** first (Day 3's SGA); anything not resident triggers a **physical read** from the datafiles (Day 4) into a buffer. The three-way join executes, and the `GROUP BY`/`ORDER BY` need a **sort work area** carved out of this server process's own **PGA** (Day 3) to aggregate `SUM(quantity * unit_price)` per order and sort the results by `order_total`.
6. **Fetch.** Rows stream back to the client in batches over the same connection, still driven entirely by the server process.
7. If a second analyst runs the **identical** text a minute later, steps 2–4 collapse to a **soft parse** — the library cache already holds the cursor and the plan — and only step 5–6 (execute/fetch) do real work again, against whatever is now resident in the buffer cache.

The point of the exercise is fluency, not discovery: every clause in the answer names a Day 3, Day 4, or Day 5 concept explicitly, with no gaps and no hand-waving ("it just runs it") anywhere in the chain.

## Hands-on Lab — Annotate a Statement-Execution Trace

**Goal:** produce an annotated piece of evidence — a real trace of one statement's lifecycle — and label each part with the architecture concept it demonstrates. This is deliberately "here is evidence of each phase happening," not "here is how to read a plan" (that is Day 21–22's job).

**Steps:**
1. Run `setup.sql`, then enable a basic SQL trace for the session: `EXEC DBMS_MONITOR.SESSION_TRACE_ENABLE(waits => TRUE, binds => FALSE);`
2. Run the Real-World Scenario query above once (cold) and once again (warm), exactly as in `demo.sql` Steps 2 and 4.
3. Disable tracing: `EXEC DBMS_MONITOR.SESSION_TRACE_DISABLE;` Locate the resulting trace file in the instance's `diagnostic_dest`/`trace` directory (**ENVIRONMENT DEPENDENT** — exact path depends on instance configuration; instructor to verify against a real 19c instance before class, and optionally run `tkprof` on it for a formatted view).
4. In parallel — and as the primary path when a raw trace file is not conveniently available — build the same evidence from `diagnose.sql`'s queries against `V$SQL`, `V$SQL_SHARED_CURSOR`, `V$SQL_PLAN` (introductory columns only), `V$SQL_WORKAREA`, and `V$SESSION_EVENT`.
5. For each piece of evidence collected (a `PARSE` line or a `V$SQL` row; the `V$SQL_PLAN` rows; the `V$SQL_WORKAREA` row; the `V$SESSION_EVENT` rows), students write one line identifying: (a) which of the five lifecycle stages it comes from, and (b) which Day 3/4/5 architecture component it proves was touched.
6. Submit the annotated evidence set (a short table: evidence → stage → architecture component) as the lab deliverable.

## Troubleshooting Challenge — "What Phase Does This Belong To?"

No incident to solve today — this is a **classification** drill, and it deliberately previews the diagnostic triage instinct Days 7 onward will build on. For each item, decide: **Parse-time issue**, **Optimizer/plan issue**, or **Execution/fetch issue**.

1. `V$SQLAREA` shows `PARSE_CALLS = 48,201` and `EXECUTIONS = 48,300` for one `SQL_ID`, with `LOADS = 1`.
   *(A trap: a high `PARSE_CALLS` count alone is not evidence of a problem — `LOADS = 1` means only one hard parse ever occurred; every other parse call was cheap. Not a parse-time issue.)*
2. The same `SQL_ID` instead shows `LOADS = 4,712` against `EXECUTIONS = 4,750`.
   *(This is a parse-time issue: nearly every execution is triggering its own hard parse — a classic literal-SQL/no-bind-variables symptom, the subject of Day 19.)*
3. `V$SQL_PLAN` shows two different `PLAN_HASH_VALUE`s for the same `SQL_ID`'s child cursors — one plan uses an index range scan on `ORDERS`, the other a full partition scan.
   *(Optimizer/plan issue: the same statement is being optimized differently across executions — plan instability, previewed here and covered properly in Optimizer & Statistics, Days 24–25.)*
4. A session shows a large `physical reads` delta and significant `db file scattered read` wait time for a query whose plan (`PLAN_HASH_VALUE`) has not changed and whose `LOADS = 1`.
   *(Execution/fetch issue: parsing and optimizing were both fine — the cost is in touching blocks, likely because the working set does not fit the buffer cache. Full wait-event diagnosis starts Day 10, I/O specifically Day 30.)*
5. `V$SQL_WORKAREA` shows `MULTIPASSES_EXECUTIONS > 0` for this statement's sort operation.
   *(Execution/fetch issue: the PGA work area granted is too small for the sort, forcing multiple passes through TEMP — parsing and the plan itself are not the problem. Full treatment Day 29.)*

## Q&A (5 questions)

1. **(Definitional-but-applied)** In your own words, what does a soft parse skip that a hard parse must do? Name the Oracle component involved in the step that gets skipped.
2. **(Troubleshooting)** You see `V$SQLAREA.LOADS = 1` and `EXECUTIONS = 500` for a statement. Is this statement being hard-parsed 500 times, once, or somewhere in between? How do you know?
3. **(Scenario-based)** A `SELECT` with a `GROUP BY` and a three-table join just ran. List, in order, every architecture component from Days 3–5 that was touched, and at which lifecycle stage each one was touched.
4. **("What would you do first?")** Given only a `SQL_ID` and told "this query feels slow," what is the very first thing you would check to determine whether the problem is even in the parse/optimize stage at all, versus the execute/fetch stage — and why start there?
5. **(Closing the Bootcamp)** Looking back across Days 3–6: which single Day 3 concept (instance vs. database, SGA vs. PGA, or background vs. foreground processes) turned out to matter the most once you actually watched a statement execute today, and why?

## Interview Questions

1. **Narrate the full statement lifecycle.** "Walk me through, in order, everything Oracle does between receiving a `SELECT` statement's text and returning the first row to the client. Be specific about which memory structure or process is involved at each step." *(This is the question explicitly designed to test full-lifecycle fluency — a strong answer names the library cache, the data dictionary, the buffer cache, the PGA, and the server process, in the correct order, unprompted.)*
2. What is the practical difference between a hard parse and a soft parse, and why does an application that uses literal values instead of bind variables tend to suffer disproportionately from hard parsing?
3. If two sessions run the exact same SQL text at the same time, can the second one avoid the optimizer entirely? What has to be true for that to happen, and what could prevent it (e.g., a different optimizer environment, a different schema, an intervening DDL)?

## Instructor Notes

- **This day's entire value is in the callbacks — do not let it become a fifth isolated topic.** Explicitly say the words "Day 3," "Day 4," and "Day 5" out loud multiple times during Theory and the Demo, not just once at the start. Suggested cadence: name Day 3 when introducing the library cache and again for the buffer cache/PGA; name Day 4 when semantic checking and the optimizer come up; name Day 5 the moment the server process is first mentioned as the active agent, and again at Fetch.
- Before starting Theory, spend 60–90 seconds having students recall, unprompted, one fact each from Day 3, Day 4, and Day 5 (e.g., "what's the difference between SGA and PGA," "what's a segment," "what does PMON do"). This primes the callback structure that the rest of the hour depends on.
- If Days 3–5 have not actually been taught yet to this particular cohort (e.g., a reordered delivery), open with a 3-minute crash recap of exactly the vocabulary this day needs: instance vs. database, SGA vs. PGA, shared pool/buffer cache, tablespace/segment/extent/block, redo/undo, dedicated server process, background process roles — otherwise the callbacks will land on nothing.
- The demo's hard-parse-then-soft-parse pattern is deliberately simple and deterministic (a unique tag guarantees the cold run is a hard parse). Resist the temptation to add cursor-sharing edge cases (bind mismatches, `V$SQL_SHARED_CURSOR` reasons) here — that is Day 19's job; today needs the clean, unambiguous case.
- When walking `V$SQL_PLAN` in Step 7/diagnose.sql, explicitly say "we are not learning to read this plan today — we are only confirming a plan exists and has a shape. Reading it starts Day 21." This manages expectations and prevents the room from derailing into premature plan-reading questions.
- Close the session by explicitly framing it as the end of the Bootcamp: "Everything from here — starting with Day 7's time model — assumes you can do what we just did: name the architecture piece behind any number you see."

## Student Notes

- This is the last Beginner-difficulty day. Day 7 begins the performance-measurement stages proper (response time, throughput, DB Time) — and it will lean directly on the lifecycle you learned today, especially the distinction between time spent parsing/optimizing versus time spent executing/fetching.
- Keep your own one-line version of the lifecycle map (parse→library cache/dictionary, optimize→dictionary, execute→buffer cache+PGA+server process, fetch→server process) somewhere you can glance at it — it is the mental model the rest of the course is built on top of.
- If `V$SQL_PLAN` or execution plans feel unfamiliar or intimidating after today's brief look, that is expected — real plan-reading technique does not start until Day 21–22. Today only needed you to confirm a plan exists, not to judge whether it is good.
- The hard-parse-vs-soft-parse distinction you practiced today will resurface directly on Day 19 (SQL Execution Lifecycle, Cursors & Bind Variables) — it is worth being genuinely comfortable with `LOADS` vs. `PARSE_CALLS` vs. `EXECUTIONS` before then.

## PPT Outline (10 slides)

1. **Title** — "Architecture Bootcamp IV: How Oracle Executes a Statement" — the bridge day, closing Days 3–6.
2. **Where we've been** — one-line recap each of Day 3 (instance/memory), Day 4 (storage/redo/undo), Day 5 (processes) — framed as "four puzzle pieces, about to become one picture."
3. **Today's question** — "You've mapped every piece of the machine. What happens when you actually turn it on?"
4. **The five-stage lifecycle (list)** — Parse → Optimize → Row Source Generation → Execute → Fetch, shown as a simple left-to-right chain, no detail yet.
5. **THE comprehensive diagram — "Statement Lifecycle, Fully Wired to the Bootcamp."** Full-slide diagram: a left-to-right pipeline of the five stages; above/below each stage, a callout box naming the exact Day 3/4/5 component engaged there — Parse→"Library Cache / Shared Pool (Day 3)" with a branch to "Data Dictionary — semantic check (Day 4)" on hard parse only; Optimize→"Data Dictionary / Object Stats (Day 4)"; Row Source Gen→"Library Cache (Day 3)"; Execute→ two parallel callouts "Buffer Cache (Day 3)" and "PGA Work Area (Day 3)", both stemming from "Server Process (Day 5)" drawn as the throughline actor beneath the entire pipeline; Fetch→"Server Process → Client (Day 5)". This single slide is the whole Bootcamp's payoff image — build it to be legible standalone, since it is the slide students will screenshot.
6. **Hard parse vs. soft parse** — side-by-side: what happens (syntax/semantic check, dictionary lookup, full optimization) vs. what's skipped (library cache hit, plan reused).
7. **Evidence, not guesswork** — screenshot-style mockup of the `V$SQLAREA` before/after (`LOADS` unchanged, `PARSE_CALLS`/`EXECUTIONS` incrementing) from the live demo.
8. **Execute is where memory gets real** — buffer cache logical vs. physical reads; PGA work areas for sort/hash — tying straight back to Day 3's SGA/PGA diagram.
9. **Real-World Scenario recap** — the three-table `PERF_LAB` join, annotated exactly as in the Real-World Scenario section, as a worked example students can point back to.
10. **Troubleshooting Challenge preview** — "Parse, Plan, or Execute?" three-column sorting exercise shown as a teaser, transitioning into the Q&A.
11. **What's next: Day 7** — one line: "You now know *how* a statement runs. Next: how do we *measure* how long each stage actually took?" — DB Time and the time model.
12. **Homework** — stated plainly on its own closing slide.

## Homework

Before Day 7 (Measuring Performance: Response Time, Throughput, DB Time & Time Model):

1. Re-run `demo.sql` once on your own, without narration prompts, and write a one-paragraph explanation (in your own words) of what happened at each of the five lifecycle stages for the query you ran — as if explaining it to a colleague who missed today's session.
2. Look up (do not run yet) the view `V$SYS_TIME_MODEL` and its session-level counterpart `V$SESS_TIME_MODEL`. Read the column list only. Bring one specific question about what you think a row in that view represents — Day 7 will build directly on today's lifecycle to answer it.
3. Think about this before Day 7 starts: today you watched a hard parse cost more than a soft parse. If you had to put a *number* on "how much more," where would you look? You do not need the answer yet — Day 7 begins teaching you how to actually measure it.
