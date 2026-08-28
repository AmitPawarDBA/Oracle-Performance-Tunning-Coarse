# Day 2 — Systematic Investigation: From Symptom to SQL

## Topic
Running the full investigative chain — active sessions → expensive SQL → wait event → execution plan → hypothesis → prove — independently, start to finish, against a concurrency-driven production incident on the `PERF_LAB` OLTP schema.

## Duration
60 minutes

## Difficulty
Beginner

## Learning Objectives
By the end of this session, students will be able to:
1. Recap and correctly apply Day 1's vocabulary — DB Time, active sessions, CPU time vs. wait time — without instructor narration.
2. Query `V$SESSION` to identify who is active right now and what they are waiting on.
3. Join `V$SESSION` to `V$SQL`/`V$SQLAREA` to identify which SQL statement is responsible for observed activity.
4. Read a *basic* execution plan (`DBMS_XPLAN.DISPLAY_CURSOR`, `FORMAT => 'BASIC'`) well enough to tell a full scan from an indexed access — no join-method or cost-tuning depth yet.
5. Investigate and rule out at least one plausible false lead using evidence, not assumption, before accepting a hypothesis.
6. Form a testable hypothesis and prove it in a safe, non-invasive way before touching any schema object.
7. Apply a proportionate fix, then validate it quantitatively using the same evidence chain used to diagnose the problem.
8. Run this entire chain independently, without instructor guidance, on a second, previously unseen incident.

## Theory (minimal — Day 1 recap only)
Day 1 was the Hook: a live demo, watched, not driven. Today is the same chain — but the class runs it. Before diving in, a five-minute recap of Day 1's vocabulary, because everything today depends on it:

- **DB Time** — the total time Oracle sessions spent either executing on CPU or actively waiting for something, summed across all sessions. It is the single number that tells you "how much work (and non-work) the database is doing," and it is why a system can look "busy" with low CPU and still have a real performance problem.
- **Active session** — a session that is either consuming CPU right now or waiting for a non-idle resource right now. A connected-but-idle session (e.g. waiting on `SQL*Net message from client` for user think time) is *not* active in the sense that matters for diagnosis — this distinction is exactly what separates a real database problem from a quiet application.
- **CPU vs. wait** — every unit of DB Time is either CPU time (the session was actually running on a processor) or wait time (the session was blocked on something — I/O, a lock, a latch, another session). The first branch of every investigation is: is this CPU-bound or wait-bound? Today's incident is wait-bound, and specifically I/O-wait-bound — you will prove that, not assume it.

That's it for new theory today. No new views, no new wait event taxonomy beyond what's needed to read today's evidence — the point of Day 2 is *doing* the chain, not learning more vocabulary. The full wait-event taxonomy is Days 17–18; deep plan reading is Days 21–22; AWR/ASH history is Days 12–16. Today deliberately stays inside what Day 1 already gave you, applied for real.

## Key Concepts
- **The investigation chain is a fixed sequence, not a grab-bag of queries**: active sessions → rule out false leads → expensive SQL → wait event → execution plan → hypothesis → prove → fix → validate. Skipping steps (especially "prove") is how DBAs end up fixing the wrong thing.
- **A false lead investigated and ruled out is not wasted time — it's the discipline.** Locking, network, and "it's always the database" are the three most common reflexive first guesses in a real incident. Checking and ruling them out with evidence (not skipping past them) is what separates systematic investigation from guessing.
- **Many active sessions on the same object is not automatically blocking.** `BLOCKING_SESSION` and `V$LOCK` tell you whether sessions are actually stuck behind each other; concurrent-but-independent full scans on the same table look superficially similar but have a completely different root cause and fix.
- **An access path that was "fine" can become a production incident purely through a change in concurrency**, with zero code deployment and zero data corruption involved. This is a different class of root cause than "the plan changed" — same investigative tools, different kind of story.
- **Prove before you change.** Confirming the hypothesis in a safe, read-only, non-invasive way (Step 4 in today's demo) before running any DDL is not optional ceremony — it's what prevents a wrong or premature fix in front of a live incident.

## Important Views/Commands
This is the toolkit available at this point in the course — deliberately basic. AWR/ASH *history* views, SQL Monitor, and deep plan-shape analysis are not used today; they arrive in later stages.

| View / Command | What it tells you today |
|---|---|
| `V$SESSION` | Who is connected, who is ACTIVE, their wait class/event, their current `SQL_ID`, and `BLOCKING_SESSION` |
| `V$SQL` | Per-cursor statistics for currently cached SQL: executions, buffer gets, disk reads, elapsed time |
| `V$SQLAREA` | Aggregated version of `V$SQL` — one row per SQL_ID, convenient for "how expensive is this statement overall" |
| `V$SESSION_WAIT` | The specific wait event and time-in-wait for a session right now (legacy view name, still valid and still commonly used) |
| `V$ACTIVE_SESSION_HISTORY` | In-memory (last ~1 hour), sampled every second — a cross-check that doesn't depend on catching a session at one exact instant |
| `V$LOCK` | Confirms or rules out real locking/blocking between sessions |
| `DBMS_XPLAN.DISPLAY_CURSOR` (`FORMAT => 'BASIC'`) | The actual execution plan for a cached SQL_ID — today, used only to answer "full scan or indexed access?" |
| `DBMS_APPLICATION_INFO.SET_MODULE` | How a session's current activity gets tagged with a recognizable module/action (used in today's lab setup so you can spot the "screen" responsible in `V$SESSION`; taught properly on Day 8) |

## Practical Demo
Full commands: `demo.sql` (orchestration), `diagnose.sql` (the reusable investigation chain), `fix.sql`, `validate.sql`, `cleanup.sql`, `reset.sql`. Setup: `setup.sql`.

**Business framing for the room:** *"A recall notice just went out on one product. Customer service is telling every caller 'let me check if your order had that item' — and they're all checking at the same time. The order-lookup screen that normally takes a few seconds now takes many, many seconds, and the support queue is backing up."*

### 1. Baseline
Run `sp_csr_order_lookup_by_product` once, alone, from a single session. Capture its `V$SQL` statistics: executions, buffer gets, disk reads, elapsed time per execution.
```sql
EXEC perf_lab.sp_csr_order_lookup_by_product(p_product_id => 4471);
```
**ENVIRONMENT DEPENDENT:** a full scan of a 20-million-row table run by one session will typically complete in a few seconds on Standard-tier lab hardware — record whatever your environment actually shows rather than assuming a number. The point of this step is not the absolute number, it's having a documented "before" to compare against later.

### 2. Break It
Launch the simulated recall-notice spike: 25 concurrent CSR sessions all running the same lookup for about 90 seconds.
```sql
EXEC perf_lab.sp_generate_csr_load_product(p_sessions => 25, p_duration_seconds => 90, p_product_id => 4471);
```

### 3. Observe
Before touching anything else, answer the cheapest, highest-value question first: is anything actually active right now, and on what?
```sql
SELECT COUNT(*) FROM v$session WHERE status='ACTIVE' AND type='USER';
SELECT NVL(wait_class,'ON CPU') wait_class, COUNT(*) FROM v$session
WHERE status='ACTIVE' AND type='USER' GROUP BY wait_class;
```
The room sees: dozens of active sessions, dominated by one wait class. This is the "something is genuinely different right now" confirmation — not yet a diagnosis.

### 4. Investigate
Run the full chain in `diagnose.sql`, step by step, narrating each result:
- **Chain Step A** — snapshot every active `PERF_LAB` session: SID, module, wait class/event, `BLOCKING_SESSION`, `SQL_ID`.
- **Chain Step B (false lead #1 — locking)** — check `BLOCKING_SESSION` and `V$LOCK` for real TX/TM contention. Result: nothing. Ruled out with evidence, not assumption.
- **Chain Step C (false lead #2 — network)** — check whether the dominant wait class is actually `User I/O` (real DB work) rather than idle `SQL*Net` waits (which would point at the network/app tier instead). Result: `User I/O` dominates. Ruled out.
- **Chain Step D** — join active sessions to `V$SQL` on `SQL_ID` to find which statement explains nearly all of the active-session count.
- **Chain Step E** — pull that SQL_ID's `V$SQLAREA` statistics: buffer gets per execution in the tens of thousands is the signature of a full scan, not a selective lookup.
- **Chain Step F** — confirm the specific wait event via `V$SESSION_WAIT`: `db file scattered read` / `direct path read`.
- **Chain Step G** — cross-check independently with `V$ACTIVE_SESSION_HISTORY`: same SQL_ID, same event, dominant in the last several minutes of samples.
- **Chain Step H** — pull the basic plan with `DBMS_XPLAN.DISPLAY_CURSOR(..., 'BASIC')`: `TABLE ACCESS FULL` on `ORDER_ITEMS`.

### 5. Prove
Before writing any DDL, prove the hypothesis — "no index exists on `PRODUCT_ID`, so a full scan is the *only* available access path, not a poor optimizer choice" — safely. Run the query with an `INDEX` hint against the real table: Oracle ignores the hint and still shows a full scan, because there is genuinely no index to use. That is the proof.
```sql
EXPLAIN PLAN FOR
SELECT /*+ INDEX(oi) */ oi.order_id, oi.product_id, oi.quantity, oi.unit_price
FROM order_items oi WHERE oi.product_id = 4471;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(FORMAT => 'BASIC +PREDICATE'));
```

### 6. Fix
Create the missing index, `ONLINE` so it doesn't block the already-struggling concurrent readers, then gather statistics on it explicitly (see `fix.sql` for the full rationale write-up):
```sql
CREATE INDEX ix_order_items_product_id ON order_items(product_id) ONLINE;
EXEC DBMS_STATS.GATHER_INDEX_STATS('PERF_LAB', 'IX_ORDER_ITEMS_PRODUCT_ID');
```
Verify the plan changed before declaring victory.

### 7. Validate
Re-run the exact Baseline call and the exact 25-session spike, and re-run the same diagnostic queries. Compare, quantitatively, against the Step 1/3 numbers: buffer gets per execution should drop by roughly two to three orders of magnitude, the dominant wait class should shift away from sustained `User I/O`, and the plan should now show `INDEX RANGE SCAN` on the new index. See `validate.sql` for the full before/after table.

### 8. Reset
Run `reset.sql` to drop the index and Day 2 helper objects, restoring a clean, re-runnable state for the next class or self-study run.

## Real-World Scenario

**Symptoms:** Customer service reports that the "Order Lookup by Product" screen, normally responsive, is now taking many seconds per search during business hours. The support queue backlog is growing. IT has received a handful of tickets calling it "frozen."

**Initial evidence:** The on-call DBA opens a session and runs `SELECT COUNT(*) FROM v$session WHERE status='ACTIVE'` — the count is far higher than the normal baseline for this time of day, and nearly all of them belong to the CS application's connection pool.

**False lead investigated and ruled out:** The first instinct in the incident channel is *"twenty-five sessions stuck on the same screen — something must be locked."* The DBA checks `V$SESSION.BLOCKING_SESSION` and `V$LOCK` for TX/TM contention across those sessions. Every session comes back with `BLOCKING_SESSION IS NULL` and there are no blocking rows in `V$LOCK`. This is not a locking incident — each session is doing its own independent (and expensive) work, not queued behind another session. The DBA documents this finding in the incident channel before moving on, specifically so nobody re-raises "check for locks" twenty minutes later.

A second, quieter false lead surfaces from the app team: *"Is this a network blip? Users say the screen just spins."* The DBA checks the wait class breakdown and shows the dominant wait is `User I/O`, not idle `SQL*Net` time — the database is genuinely busy doing real work, not waiting on the network. This is also documented and ruled out.

**Root cause:** Joining active sessions to `V$SQL` shows one SQL_ID — the product-lookup query behind the CS screen — accounts for nearly every active session. Its `V$SQLAREA` statistics show buffer gets per execution in the tens of thousands, consistent with scanning all of `ORDER_ITEMS` (20 million rows) rather than a selective lookup. `V$SESSION_WAIT` confirms `db file scattered read` / `direct path read` as the dominant event, and `V$ACTIVE_SESSION_HISTORY` independently agrees over the last several minutes of samples. A basic `DBMS_XPLAN.DISPLAY_CURSOR` plan confirms `TABLE ACCESS FULL` on `ORDER_ITEMS`. The lookup-by-product feature was shipped without a supporting index on `PRODUCT_ID` — it worked fine when run occasionally by one CSR at a time, because a single full scan, while not cheap, was tolerable. The recall notice caused dozens of CSRs to run the same expensive query concurrently, and the shared I/O path and buffer cache simply could not absorb that many simultaneous full scans of a 20-million-row table. Nothing was "broken" — an access path that was always expensive became a production incident purely because of a concurrency spike.

**Fix:** `CREATE INDEX ix_order_items_product_id ON order_items(product_id) ONLINE;` followed by an explicit statistics gather on the new index, applied as a separate, deliberate step — not bundled silently into the investigation.

**Validation:** Baseline single-session timing and buffer gets dropped by roughly two to three orders of magnitude; re-running the 25-session spike no longer produces a sustained population of `User I/O`-waiting active sessions; the plan now shows `INDEX RANGE SCAN` on the new index instead of `TABLE ACCESS FULL`.

**Lesson learned:** A missing index is often framed as "the plan is wrong," but here the plan was *correct* for the only access path available — the real defect was a feature shipped without considering its access path at realistic concurrency, not at the "it works for one user in QA" concurrency it was tested at. This is why "when did it start, and what changed in the *workload*, not just the code" belongs in every investigation alongside "what changed in the code."

## Hands-on Lab
**Now you drive — instructor steps back to a consulting role only.** A second, structurally similar but distinct problem has been injected into the lab: the **Payment Reconciliation screen**, which recently added a "search by payment method" filter (`PAYMENTS.PAYMENT_METHOD`) for the finance team. It was shipped as "just an internal report, nobody will run it much" — and, predictably, several reconciliation clerks now run it concurrently every morning during month-end close.

Using only `setup.sql`'s `sp_generate_csr_load_payment` procedure to reproduce the spike, run the **entire chain independently**, start to finish:
1. Baseline a single execution of `sp_csr_payment_lookup_by_method`.
2. Break it: `EXEC perf_lab.sp_generate_csr_load_payment(p_sessions => 20, p_duration_seconds => 90, p_payment_method => 'CREDIT_CARD');`
3. Observe active session count and wait class breakdown.
4. Investigate: rule out locking, rule out network, identify the responsible SQL_ID, pull its statistics, confirm the wait event, cross-check with ASH, read the basic plan.
5. Prove the hypothesis safely before writing any DDL.
6. Propose (and, if time allows, apply) the fix.
7. Validate quantitatively.
8. Reset.

Do not reuse `diagnose.sql` by find-and-replace without reading each query — the point of the lab is running the *reasoning*, not copy-pasting a script against a new table name. Write your own version of the chain in a scratch file, referring back to `diagnose.sql` only if you get stuck on syntax.

## Troubleshooting Challenge
After you create `ix_order_items_product_id` and validate the fix, a new ticket comes in: **most** CS reps report the screen is fast now, but one specific team — the "VIP Accounts" desk — is still reporting multi-second response times on the exact same screen.

Investigate using the same chain. Guiding questions (do not skip straight to the answer):
- Is the VIP desk's session even running the same SQL_ID as before? Check `V$SESSION`/`V$SQL` for their sessions specifically.
- If it's a *different* SQL_ID with similar symptoms, what would make an otherwise-identical query fail to use the new index — a wrapped column (`TO_CHAR(product_id) = :b1`), an implicit datatype conversion, a leading wildcard, an `OR` condition mixed in, or a stale cached cursor from before the fix?
- What's the fastest way to confirm which of those it is, using only today's toolkit (no deep plan reading yet — just `BASIC` format and the predicate section)?

*Instructor note: this is intentionally open-ended and does not have a scripted setup — treat it as a discussion/whiteboard exercise unless you want to inject a genuinely different SQL variant (e.g., a VIP-desk screen that filters `WHERE TO_CHAR(product_id) = :product_id` due to a legacy string-based UI field) into your own copy of the lab.*

## Q&A
1. **(Troubleshooting)** You join active sessions to `V$SQL` and find the top SQL_ID by active-session count accounts for only 6 of 40 active sessions — no single statement dominates. What does that change about your next step, compared to today's demo where one SQL_ID explained almost everything?
2. **(What would you check first?)** You get paged: "the database is slow." Before running a single diagnostic query, what is the very first thing you check, and why does checking it first — rather than jumping straight to `V$SQL` — matter?
3. **(Scenario-based)** Two different teams file tickets fifteen minutes apart: Team A says "the app just hangs," Team B says "reports are taking forever." `V$SESSION` shows 12 active sessions, 10 in `User I/O` wait and 2 with `BLOCKING_SESSION` populated pointing at a third, idle session. Walk through how you'd separate these into two different investigations rather than treating them as one incident.
4. Why does today's demo insist on proving the hypothesis (Step 4, the `INDEX` hint test) *before* running `CREATE INDEX`, instead of just creating the index and seeing if it helps?
5. `BLOCKING_SESSION` is `NULL` for every session in an incident with dozens of concurrently active sessions on the same table. Does that fully rule out contention as a factor? What else, beyond row-level locking, could still be a form of contention here?

## Interview Questions
1. "Walk me through how you'd investigate a report of 'the application is slow' using only base `V$` views — no AWR, no third-party tooling." (Expects: the ordered chain — active sessions, false-lead ruling-out, SQL identification, wait event, basic plan — not a scattershot list of queries.)
2. "You find 30 active sessions all running the same SQL_ID with a `db file scattered read` wait. Is the fix always 'add an index'? What else could explain that picture, and how would you tell them apart?" (Expects: recognizes that a genuinely large necessary scan, a bad join order producing an unnecessary scan, and a missing index all look similar at this level of evidence, and that the plan/predicate detail is what separates them.)
3. "Why might many active sessions on the same table NOT be a locking problem?" (Expects: distinguishing independent concurrent work from actual blocking, and naming the specific views — `BLOCKING_SESSION`, `V$LOCK` — used to tell them apart.)

## Instructor Notes
**Talking points:**
- Open by explicitly naming the shift from Day 1: "Yesterday I drove and you watched. Today you're going to run this exact chain yourselves, on a problem I haven't shown you the answer to." Say this out loud — it sets the tone for the whole day.
- Keep the Day 1 recap tight — five minutes, no more. If the room is shaky on DB Time/active sessions/CPU-vs-wait, that's a signal to slow down *today's* pacing, not to re-teach Day 1 in full.
- Narrate the false leads as real incident-channel chatter ("someone on Slack says 'must be locking'") rather than as a scripted quiz question — it should feel like the natural first guess a working DBA would make, which is exactly why checking it matters.

**Handing control to students:**
- After the Practical Demo, explicitly step back: sit down, stop narrating, and only answer direct questions when asked (Socratically redirect where possible — "what would you check to find that out?" rather than supplying the query).
- Circulate rather than watch one screen — most first-time independent investigations stall at the same one or two points (below), and it's faster to unstick six students in five minutes each than to let one derail the room.

**Common first-independent-investigation mistakes, and how to coach through them:**
- *Jumping straight to "add an index" without running the chain.* Some students will recognize the pattern from the demo and shortcut to the fix. Redirect: "Show me the evidence first — which SQL_ID, which wait event, which plan operation — pretend I don't believe you yet."
- *Treating "many active sessions on one table" as automatic proof of locking*, skipping the `BLOCKING_SESSION`/`V$LOCK` check entirely. Coach: "What would locking actually look like in `V$SESSION`? Go check, don't assume."
- *Copy-pasting `diagnose.sql` with a find-and-replace of table/column names* rather than reasoning through each step for the new scenario. This produces a working answer but doesn't build the skill — ask them to explain, in their own words, what each query is proving before moving to the next.
- *Forgetting to check for a stale cached cursor after applying a fix* (validate.sql Step 3) — a student creates the index, re-runs the query, and it still shows a full scan because the old cursor with the old plan is still what's being displayed. Use this as a live teaching moment about cursor sharing, not a failure — it previews Day 19.
- *Declaring victory on "it felt faster"* without pulling the actual before/after numbers. Push back every time: "What's the number? Compared to what number?"

## Student Notes
- The chain, memorize it: **active sessions → rule out false leads → expensive SQL → wait event → execution plan → hypothesis → prove → fix → validate.**
- `V$SESSION.STATUS = 'ACTIVE'` is not the same as "connected." A connected-but-idle session is not part of your incident.
- Checking `BLOCKING_SESSION` and `V$LOCK` takes thirty seconds and either confirms or eliminates an entire category of root cause. Always run it, even when you're fairly sure it isn't locking.
- Buffer gets per execution is one of the fastest "full scan vs. selective access" signals available before you even look at the plan — tens of thousands of gets for a lookup query is a red flag on its own.
- `FORMAT => 'BASIC'` in `DBMS_XPLAN.DISPLAY_CURSOR` is enough to answer "full scan or indexed access" — you do not need to understand cost, cardinality, or join methods yet to use today's chain effectively.
- Prove your hypothesis before you change anything. An `INDEX` hint that Oracle ignores because no index exists is itself evidence, not a failed test.
- A missing index is not always the answer just because it was the answer today — the value of the chain is that it tells you *which* fix fits *this* evidence, and today it happened to be an index.

## PPT Outline
1. **Title slide** — "Day 2: Systematic Investigation — From Symptom to SQL." Subtitle: "Yesterday you watched it happen. Today you drive." | Speaker notes: name the shift in responsibility immediately.
2. **Objective** — Today's single goal: run the full chain independently, end to end, on a new incident. | Diagram suggestion: the six-stage arrow chain (active sessions → false leads → SQL → wait → plan → hypothesis → prove → fix → validate). | Speaker notes: this diagram reappears at the top of every remaining diagnostic day in the course — get students used to it now.
3. **Day 1 recap (5 min)** — DB Time / active session / CPU vs. wait, one line each. | Speaker notes: keep to five minutes flat, watch the clock.
4. **Today's incident, framed as a business problem** — recall notice, CS screen, spiking call volume. `PRODUCTION SCENARIO` tag. | Diagram suggestion: a simple before/after two-panel — "one CSR, occasional use" vs. "25 CSRs, same minute." | Speaker notes: let the business framing land before showing any SQL.
5. **Baseline & Break It** `LIVE DEMO` tag — run the single-session baseline, then launch the 25-session spike. | Speaker notes: narrate what you expect to see before running it, so the class has a prediction to check against.
6. **Observe** `LIVE DEMO` tag — the active-session-count and wait-class queries. | Diagram suggestion: a simple bar chart, "active sessions by wait class," before/after style, filled in live from real query output. | Speaker notes: pause here — ask the room "what's your first hypothesis?" before continuing.
7. **False lead #1 — locking** `LIVE DEMO` tag — check and rule out `BLOCKING_SESSION`/`V$LOCK`. | Speaker notes: explicitly say "this is the natural first guess, and it's wrong — here's how we know."
8. **False lead #2 — network** `LIVE DEMO` tag — wait-class breakdown showing real `User I/O`, not idle network waits. | Key takeaway: ruling something out with evidence is real investigative progress, not wasted time.
9. **Finding the SQL, the wait, and the plan** `LIVE DEMO` tag — Chain Steps D–H in sequence. | Diagram suggestion: three-box flow — SQL_ID → wait event → plan operation — each box filling in as the query runs. | Speaker notes: this is the heart of the day; take it slowly, one query at a time, and name what each result proves.
10. **Prove, Fix, Validate** `LIVE DEMO` tag — the index-hint proof, `CREATE INDEX`, and the before/after comparison. | Key takeaway: "prove before you change" is not optional ceremony.
11. **Hands-on Lab handoff** `PRODUCTION SCENARIO` tag — introduce the Payment Reconciliation screen incident, then step back. | Speaker notes: this is the actual handoff moment — say clearly "I'm not driving anymore, you are" and stop presenting.
12. **Wrap-up & bridge to Day 3** — recap the chain one more time; preview that Days 3–6 build the architecture knowledge underneath everything used today. | Key takeaway: "Every day from here builds on this chain — you'll use it again and again, just with deeper tools each time."

## Homework
1. Write a one-page incident report for today's demo incident, in the same format as the Real-World Scenario above (symptoms, evidence, false lead(s) ruled out, root cause, fix, validation, lesson learned) — but in your own words, as if reporting it to a manager who wasn't in the room.
2. Complete the Hands-on Lab (Payment Reconciliation) fully if it wasn't finished in class, including your own before/after validation numbers.
3. Read the Oracle Database Performance Tuning Guide 19c section on "Identifying Resource-Intensive SQL" (Chapter on SQL Tuning within the performance guide) and note one thing it recommends checking that today's chain did not use — bring it to Day 3 for discussion.
4. Optional stretch: using the Troubleshooting Challenge scenario, write the actual SQL for a VIP-desk query variant that would defeat the new index (e.g. via a wrapped column or implicit conversion) and verify your prediction against the plan.
