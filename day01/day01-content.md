# Day 1 — Welcome & The Hook: "The 45-Minute Mystery"

## Topic
Course opening. Two jobs in one hour: introduce the instructor and the shape of the 34-day journey in ten minutes flat, then prove — live, on real (if lab-scale) data, using a real free community tool — that this course teaches a repeatable investigative skill, not a collection of tuning tips. No feature tour. No certification roadmap. No vendor history. Just a batch job that was fine yesterday and took 45 minutes today, solved from symptom to proven root cause before the hour is up.

## Duration
60 minutes

## Difficulty
Beginner

## Learning Objectives
By the end of this session, a student should be able to:

1. Describe the six-stage shape of the 34-day course (Hook → Architecture → Diagnostics → Evidence Toolkit → SQL/Plans/Optimizer → Memory/I/O/Concurrency → Capstone) and explain how each stage builds on the one before it.
2. State the Measure → Observe → Hypothesize → Prove → Change → Validate loop from memory, in their own words, and recognize it as the spine of every remaining day of the course.
3. Read a visual, color-coded chart of database activity over time (via OraPub's free ASH Visualization Tool) well enough to tell a CPU-bound period from a wait-event-bound period at a glance.
4. Trace a performance symptom — "the job took too long" — through an active-session picture down to one specific SQL_ID, one dominant wait event, and one plan line that changed.
5. Distinguish a genuine, proven root cause from a plausible-sounding first guess, having watched (and helped rule out) at least two false leads in the same investigation.
6. Explain, at a beginner level, why re-gathering accurate statistics was the correct fix here, and why a hint, a forced index, or a shared-pool flush would each have been the wrong one.

## Theory
Kept deliberately short today — the whole point of Day 1 is that the demo teaches more than the slides could.

Performance engineering, as this course teaches it, is not a body of facts to memorize ("always index foreign keys," "bigger SGA is faster," "run this advisor"). It's a repeatable investigation, the same shape every time, regardless of whether the symptom is a slow batch job, a hung screen, or a report that used to take five minutes and now takes fifty. That shape is one loop, repeated on every single day of this course:

**Measure → Observe → Hypothesize → Prove → Change → Validate.**

*Measure* what's actually happening, in numbers, before touching anything. *Observe* the shape of that measurement — where is time actually going? *Hypothesize* a specific, falsifiable explanation, not a vague one. *Prove* it with evidence before acting on it. *Change* the one thing the evidence points at. *Validate* the change with the same kind of measurement you started with — never "it feels faster."

Two supporting ideas matter today, and only today, at an introductory level — the rest of their formal treatment is Day 15 (ASH) and beyond:

**DB Time** is, informally, the total amount of time the database spent doing work for sessions — CPU time plus wait time, added up. It's the closest thing Oracle has to a single number for "how much work happened." A job that took 45 minutes instead of 4 didn't necessarily do more work in the business sense (same number of orders, same number of rows) — it spent far more DB Time getting that same work done, and that gap between "same output, way more time" is exactly the kind of thing this course trains you to notice and explain.

**Active session count** — literally, how many sessions are doing something (not idle) at a given moment — is the roughest possible proxy for DB Time you can build with a single query, and it's enough for today. A picture of active-session count over time, color-coded by what each session is spending its time on, is precisely what the OraPub ASH Visualization Tool draws, and precisely what turns "the job was slow" from a vague complaint into a shape you can read.

That's the entire theory budget for today. Everything else — what ASH actually is, how it samples, how AWR retains history — is intentionally deferred. Today you only need enough to read a picture and follow an investigation.

## Key Concepts
- **The investigative loop** — Measure → Observe → Hypothesize → Prove → Change → Validate — the spine of this entire course, introduced today and repeated on every remaining day.
- **Symptom vs. root cause** — "the job took 45 minutes" is a symptom; "ORDER_ITEMS statistics were locked at values understating the table by ~12x" is a root cause. This course always chases the second one.
- **False leads are normal, not failures** — a real investigation checks and rules out plausible-but-wrong explanations before landing on the right one. Today rules out "more data" and "blocking" before finding the real cause.
- **DB Time** — the database's total accounting of time spent working (CPU + wait), informally introduced today, formally taught Day 7.
- **Active session count** — a rough, honest, one-query proxy for "how busy is the instance right now," used today as the seed of the picture AVT draws.
- **A picture is a starting point, not an answer** — the AVT chart tells you WHEN something changed and roughly WHAT KIND of time dominates; it still takes a SQL_ID, a wait event, and a plan line to prove WHY.
- **Plan regression** — the same query, same data, producing a different (and much worse) execution plan than it used to, introduced today at a "the plan line changed" level of depth; the mechanics (join methods, cost model, cardinality) come in Stages 5–8.

## Important Views/Commands
Kept minimal on purpose — this is Day 1, and the full V$/AWR/ASH ecosystem is Day 9 and Day 15's job. Today's demo does reach directly into a few real views (see Practical Demo and `diagnose.sql`) because the investigation has to be genuine, not simulated — but conceptually, only two ideas are load-bearing today:

| Concept | What it tells you today | Full treatment |
|---|---|---|
| **DB Time** | The total time the database spent working — the "currency" a slow job spends too much of | Day 7 (`V$SYS_TIME_MODEL`, `V$SESS_TIME_MODEL`) |
| **Active session count** | A rough, immediate proxy for how much DB Time is being spent right now | Day 15 (formal ASH architecture, `V$ACTIVE_SESSION_HISTORY` vs. `DBA_HIST_ACTIVE_SESS_HISTORY`) |

## Practical Demo — "The 45-Minute Mystery" (the Hook itself)

This IS the Hook. It follows the course's standard eight-step reproducible format, mapped onto the day's script files. Every numbered step below is real, runnable SQL (see `setup.sql`, `demo.sql`, `diagnose.sql`, `fix.sql`, `validate.sql`) — nothing here is a summary standing in for a script that doesn't exist.

**1. BASELINE.** Before class (the night before, or that morning), the instructor runs `setup.sql`, which calls `sp_seed_recon_baseline_history` to genuinely execute the real reconciliation job — `sp_run_daily_reconciliation`, a join across `ORDERS → ORDER_ITEMS → PAYMENTS` for one business date, reconciling order totals against completed payments — for each of the last seven business dates. This is measured, not invented, history, logged into `RECON_RUN_LOG`: every prior run finishes in well under a minute of DB Time against a few thousand partition-pruned orders, using a `NESTED LOOPS` plan driving from `ORDERS` into an `INDEX RANGE SCAN` on `ORDER_ITEMS`. This is "every prior run was green."

**2. BREAK IT.** Still in `setup.sql`, before class: `sp_inject_stale_stats_problem` backs up `ORDER_ITEMS`'s real, accurate statistics (via `DBMS_STATS.EXPORT_TABLE_STATS`, so nothing is lost), then overwrites them with statistics understating the table by roughly 12x, and locks them with `DBMS_STATS.LOCK_TABLE_STATS`. This reproduces a real, common incident shape: stats that were accurate months ago, frozen by a `LOCK_TABLE_STATS` call someone made for an unrelated reason and never revisited, silently drifting wrong as the table grew through ordinary business operation. By the time class starts, the incident has already "happened this morning," exactly as finance's email describes it.

**3. OBSERVE.** Live, in front of the class (`demo.sql`, Step 2): the instructor kicks off today's run of `sp_run_daily_reconciliation` as a background `DBMS_SCHEDULER` job, then opens the OraPub ASH Visualization Tool (free, credited by name — see `orapub.com/tools` — this is a real community tool, not course-original software) pointed at the instance. Side by side: a pre-captured screenshot of a clean BASELINE run (solid green/CPU band, done in under a minute) and the live chart for the job just launched (a few seconds of green, then a widening red/wait-event band that keeps growing as the class watches). This is the moment the whole Hook is built around.

**4. INVESTIGATE.** Live, working through `diagnose.sql`'s CHAIN STEPS A–I: confirm the SQL_ID the picture points at (Step A); check and rule out **FALSE LEAD #1 — "it's just more data today"** by comparing today's order count against the baseline history in `RECON_RUN_LOG` (Step B — ruled out, volume is normal); check and rule out **FALSE LEAD #2 — "something must be blocking it"** by checking `V$SESSION.BLOCKING_SESSION` (Step C — ruled out, nothing is blocking it, the session is genuinely busy); confirm the dominant wait event is User I/O, specifically `db file scattered read` / `direct path read` (Steps D–E); and quantify the SQL's cost in Oracle's own numbers via `V$SQLAREA` (Step F).

**5. PROVE.** Still `diagnose.sql`, Steps G–I: `DBMS_XPLAN.DISPLAY_CURSOR` shows `TABLE ACCESS FULL` on `ORDER_ITEMS` today, versus every baseline run's `NESTED LOOPS`/`INDEX RANGE SCAN` (recorded via each run's `plan_hash_value` in `RECON_RUN_LOG`) — the plan line that changed (Step G). The `ALLSTATS LAST` variant of the same plan shows *why*: on the full-scan line, Estimated Rows is roughly 12x smaller than Actual Rows (Step H) — the optimizer thinks `ORDER_ITEMS` is far smaller than it is. `USER_TAB_STATISTICS` confirms it directly: `NUM_ROWS` understated, `STATTYPE_LOCKED = 'ALL'` (Step I). This is proof, not inference — the exact defect, named and confirmed in the optimizer's own numbers and the dictionary's own metadata.

**6. FIX.** `fix.sql`, live: `DBMS_STATS.UNLOCK_TABLE_STATS`, then `DBMS_STATS.GATHER_TABLE_STATS` with `no_invalidate => FALSE` so the fix takes effect immediately rather than on Oracle's default rolling schedule. The instructor explicitly narrates why this fix and not an alternative — a hint or SQL Profile would only patch this one statement while every other query against `ORDER_ITEMS` kept reasoning from the same wrong numbers; a shared-pool flush would force a reparse that recomputes the same wrong plan from the same wrong (still locked) statistics; a new index isn't needed because a perfectly good one already exists and is simply not trusted.

**7. VALIDATE.** `validate.sql`, live: re-run `sp_run_daily_reconciliation` for today's date, labeled `TODAY_FIXED`. Compare, quantitatively, against both `TODAY_LIVE` (the broken run) and the `BASELINE` history in one query: elapsed time back in the normal range, `plan_hash_value` matching the baseline runs' plan (not the broken run's), and an ASH wait-profile query showing the fixed run is overwhelmingly ON CPU, not User I/O. Point back at the AVT screen: the live chart's red band stops growing and the picture returns to green. This is a quantified before/after, not a feeling.

**8. RESET.** After class (or between cohorts), `reset.sql` drops any leftover demo job, guarantees `ORDER_ITEMS` stats are unlocked and fresh, restores the Hands-on Lab's `PAYMENTS` index to visible, clears `RECON_RUN_LOG`/`RECON_RESULTS`, and re-seeds a fresh week of baseline history plus a freshly injected stale-stats problem — so the very next cohort gets the identical, fully reproducible Hook. `cleanup.sql` is the heavier, full-teardown version used only when decommissioning the Day 1 lab entirely.

**ENVIRONMENT DEPENDENT:** the exact number of minutes the broken run takes, and the exact number of seconds the baseline/fixed runs take, depend entirely on the lab host's CPU and storage throughput. What is NOT environment-dependent, and is guaranteed by the injection mechanism in `setup.sql`, is the *shape*: a plan that changes from indexed access to a full scan, a wait profile that flips from CPU-bound to User-I/O-bound, and an Estimated-vs-Actual row gap of roughly 12x on the `ORDER_ITEMS` line. Teach the shape; let the room's own hardware supply the numbers.

## Real-World Scenario — "The 45-Minute Mystery"

**Symptom.** The nightly batch reconciliation job — the one that compares each day's order totals against completed payments and normally finishes in about four minutes — took forty-five minutes last night. Finance noticed first, not IT: the daily reconciliation numbers that are supposed to be in their inbox by 6 AM didn't land until well past 6:45, and someone emailed asking, reasonably, "why were yesterday's numbers late?"

**Initial evidence.** The job didn't fail — no error, no alert, nothing in the job scheduler's log except a much longer runtime than usual. `RECON_RUN_LOG` shows the exact same job, run the exact same way, every night for weeks, always finishing in well under a minute of DB Time. Last night's run is the first outlier in that entire history.

**False lead #1 — "it's just more data."** The most natural guess: maybe there was an unusually large batch of orders last night — a promotion, a delayed feed catching up, something that genuinely means more work. Checked directly against `RECON_RUN_LOG`'s `order_count` column: last night's order count is well within the normal range of every prior night. Ruled out, with evidence, in under a minute. This is the whole point of measuring before hypothesizing further — a plausible guess that would have sent someone down the wrong path (provisioning more hardware, scheduling the job earlier) is closed off immediately.

**False lead #2 — "something is blocking it."** Second natural guess for "one session, stuck, taking forever": another session is holding a lock it's waiting on. Checked directly against `V$SESSION.BLOCKING_SESSION` for the job's session: empty. The session isn't blocked by anyone — it's genuinely, actively doing a large amount of work on its own. Ruled out.

**Root cause.** `ORDER_ITEMS`'s statistics were locked at values understating the table's real size by roughly twelve times — the residue of a `DBMS_STATS.LOCK_TABLE_STATS` call made weeks earlier for an unrelated, since-forgotten reason. The optimizer, working from those frozen numbers, concluded that reading the entire `ORDER_ITEMS` table in one full scan was cheaper than doing a few thousand small, targeted index lookups — and it was right, given the numbers it had. The numbers were simply wrong, and locked, so nothing had corrected them as the table kept growing through ordinary daily operation.

**Fix.** Unlock `ORDER_ITEMS`'s statistics and gather fresh, accurate ones, with immediate cursor invalidation so the fix takes effect on the very next execution — not a hint, not a forced index, not a shared-pool flush, because none of those repair the actual wrong input the optimizer is reasoning from.

**Validation.** The next run of the job finishes in the same range as every night before the incident, using the same execution plan every prior night used (confirmed by `plan_hash_value`, not just "it looked fast"), and its ASH wait profile is CPU-bound again, not I/O-bound.

**Lesson learned.** A `LOCK_TABLE_STATS` call is sometimes exactly the right emergency stabilization move during an active incident — and exactly the kind of change that quietly turns into next month's new incident if nobody puts a reminder on it to revisit and unlock once the original reason is gone. The bug wasn't "someone made a mistake once." It was "a temporary decision had no expiration date."

## Hands-on Lab — Watch, Annotate, Then Reproduce

**Part 1 — Watch and annotate (during the live demo).** While the instructor runs the Hook, students keep a running one-line note for each `diagnose.sql` chain step: what was checked, what the result was, and — critically — for the two false leads, what it would have meant if the check had come back positive instead of negative. This builds the habit of treating every check as a real fork in the investigation, not a scripted formality.

**Part 2 — Reproduce independently on a second, different problem.** Once the instructor's investigation reaches VALIDATE, the instructor runs `sp_inject_invisible_index_problem`, which makes the leading index on `PAYMENTS(ORDER_ID)` invisible to the optimizer. This flips the same reconciliation query's join to `PAYMENTS` — a 5,000,000-row table — from an indexed lookup to a full scan. Same symptom family (a join that used to be cheap now spends its time on User I/O wait instead of CPU), but a **structurally different root cause** — an invisible index, not stale/locked statistics — so students are genuinely investigating, not recalling the instructor's answer.

Working independently (or in pairs), students re-run `diagnose.sql`'s Chain Steps A, D, E, F, and G against this second run, plus the specific check named in Chain Step J (`SELECT index_name, visibility, status FROM user_indexes WHERE table_name = 'PAYMENTS'`). Deliverable: a short written statement, in the same shape as today's Real-World Scenario, covering symptom, evidence, and root cause — no fix or validation required yet (fixing an invisible index is intentionally left as a natural bridge into Day 2, which drives the full chain to a proven fix independently).

## Troubleshooting Challenge

You're shown a second AVT-style chart from a different job on a different night: a solid green band for about two minutes, then a short, sharp red spike lasting roughly thirty seconds, then green again for three more minutes before the job finishes. Total runtime is only slightly longer than normal.

What does this shape suggest, compared to today's all-red-for-forty-minutes pattern? What would you check first, and how would your first move differ from today's demo? (Hint: think about what a brief, isolated spike versus a sustained band each tend to imply about whether the problem is "the whole query got worse" versus "something briefly got in the way.")

## Q&A — "What Did You Notice?" (discussion, not a knowledge check)

This is a conversation, not a quiz — the first graded knowledge checks start Day 2. Use these to make sure the room is oriented and curious, not to test recall.

1. Before we ever looked at a single SQL_ID, what did the AVT picture alone already tell us — and what could it *not* tell us yet?
2. We checked two false leads before finding the real cause. Why check them at all instead of jumping straight to "let's look at the plan"? What would it have cost us to skip that step?
3. The fix was two `DBMS_STATS` calls, not a single dramatic action. Does that feel like it undersells the incident, or is that exactly the point?
4. If you'd been the one who ran `DBMS_STATS.LOCK_TABLE_STATS` weeks ago for a legitimate reason, what — realistically — would have reminded you to come back and unlock it?

**Optional lightweight prompt (start of the habit, not graded):** Before we opened `diagnose.sql` today, if I'd only told you "a job that takes 4 minutes took 45" and nothing else — what's the very first thing you'd have checked? Hold onto your answer; we'll compare it to the actual first step of tomorrow's investigation on Day 2.

## Interview Questions

1. "Your manager tells you 'the database is slow.' What's the first thing you actually check, and why that instead of something else?"
2. "What's the difference between a symptom and a root cause in a performance incident? Give a concrete example, even a made-up one."
3. "Why is it risky to add an index, bump a parameter, or apply a hint as your very first response to 'this query is slow'?"

## Instructor Notes

**Timing.** Intro ~5 min, roadmap ~5 min, Hook ~35 min (Baseline/Break-It recap ~3, Observe/AVT ~7, Investigate/false-leads ~12, Prove ~5, Fix ~4, Validate ~4), Q&A ~5 min, buffer/homework ~5 min. The Hook is the session — protect its 35 minutes above everything else; if you're running long, compress the roadmap slide, never the demo.

**What to say while the ASH picture is loading.** Dead air here is fine — resist the urge to fill it by talking over the chart. A useful line while the red band is visibly growing: "Notice I haven't looked at a single line of SQL yet, and I already know something changed and roughly when. That's the whole value of a picture before a query." If AVT takes a few seconds to refresh, narrate the mechanism in one sentence ("it's re-sampling active sessions, same idea as that active-session-count query we just ran") — don't drift into ASH internals; that's Day 15.

**Before class, without fail:**
- Run `setup.sql` completely (baseline history + stale-stats injection) — the room will notice immediately if `RECON_RUN_LOG` doesn't already show a week of fast baseline runs.
- Capture a fresh AVT screenshot of a clean baseline run to show side-by-side with the live chart — do this once, right after `setup.sql` finishes seeding history, before you inject the problem for that day's class.
- Confirm `GRANT CREATE JOB TO perf_lab` and V$ dictionary read access are actually in place — don't discover a missing grant live, in front of the room, during the one demo that's supposed to prove the course delivers.

**Common ways this demo goes wrong, and how to recover:**
- *AVT won't connect / isn't installed on the demo machine.* Fall back immediately to the pre-captured baseline screenshot plus the live `V$ACTIVE_SESSION_HISTORY` queries in `diagnose.sql` — the investigation still works with text output; you just lose the visual "aha," so name that loss out loud ("normally I'd show you this as a picture — today, let's read the same story in the query output instead") rather than pretending nothing changed.
- *The broken run finishes too fast to be visible live (fast lab hardware).* Widen the injected understatement in `sp_inject_stale_stats_problem` (change the `/ 12` divisor to something larger, e.g. `/ 40`) before class, or simply let the run finish and walk `diagnose.sql` against its completed ASH history — a completed run's samples are just as real as a live one's.
- *The broken run is still running well past the 35-minute Hook budget.* This is fine — you do not need the job to finish before moving to FIX. `diagnose.sql`'s evidence (wait event, plan, Estimated-vs-Actual gap, locked stats) is fully available while the job is still executing. Apply the fix, note out loud that the still-running broken execution keeps its old (bad) plan until it finishes or is restarted, and validate against a fresh run.
- *A student asks a question that reaches into Day 7/9/15 territory (formal DB Time, ASH internals, AWR retention).* Answer the specific question briefly, then explicitly park the depth: "Great question — that's exactly what Day 15 covers in full. For today, all we need is 'active sessions right now' as the rough picture."
- *The plan doesn't flip to a full scan after `sp_inject_stale_stats_problem` runs (rare, but possible on unusual optimizer parameter settings).* Check `user_tab_statistics` directly to confirm the injected numbers took; if they did and the plan still isn't flipping, this is itself a fine live teaching moment about how cost-based decisions depend on more than one input — but verify this in a rehearsal run before relying on it in front of a class.

## Student Notes

**The one loop to remember:** Measure → Observe → Hypothesize → Prove → Change → Validate. Every remaining day of this course is this loop applied to a different kind of problem.

**What we actually watched happen today, in one line each:**
- A picture (AVT) showed WHEN something changed and roughly WHAT KIND of time dominated — before any SQL was read.
- Two plausible-sounding guesses ("more data," "blocking") were checked and ruled out with evidence, not argued about.
- One SQL_ID, one wait event, and one plan line were found and confirmed with real Oracle output — not inferred from a hunch.
- The exact defect (locked, understated statistics) was proven with two concrete numbers: Estimated vs. Actual rows on one plan line, and `NUM_ROWS`/`STATTYPE_LOCKED` in the dictionary.
- The fix addressed that exact defect — not a workaround — and the fix was proven with a second, independent measurement, not a feeling.

**Cheat-sheet — the chain, in order:**

| Question | How we answered it today |
|---|---|
| Did something change, and roughly when? | The AVT picture — green vs. red bands over time |
| Is it really "more work," or something else? | Compare row/order counts against measured history |
| Is something blocking it? | `V$SESSION.BLOCKING_SESSION` |
| What is it actually waiting on? | `V$SESSION`/`V$ACTIVE_SESSION_HISTORY`, `event` column |
| Which SQL is responsible? | ASH samples grouped by `SQL_ID` |
| Has the plan changed? | `DBMS_XPLAN.DISPLAY_CURSOR`, compare `plan_hash_value` |
| Why did the plan change? | `ALLSTATS LAST` — Estimated vs. Actual rows |
| Is that provable in the dictionary, not just the plan? | `USER_TAB_STATISTICS` — `NUM_ROWS`, `STATTYPE_LOCKED` |

**What's different about this course, starting today:** no vendor history, no certification checklist, no slide deck walking through features nobody asked for yet. Every day starts from a symptom and works backward to proven evidence — never the other way around.

## PPT Outline

1. **Title slide.** "Oracle Database Performance Tuning & Troubleshooting — Day 1: Welcome & The Hook." Instructor name (Amit Pawar), course branding. *Not a demo slide.* Key takeaway: this course proves itself in the first hour. Speaker notes: one warm sentence, then move immediately — don't linger here.
2. **Instructor introduction.** Fill-in-the-blanks bullets (see template below), 4–5 prompts, not a fake biography. *Not a demo slide.* Key takeaway: "I've solved real production incidents; this course is built the way I actually investigate, evidence-first." Speaker notes: keep this under 5 minutes — set a visible timer if needed.
3. **Course philosophy, one line.** Large text: "Measure → Observe → Hypothesize → Prove → Change → Validate." *Not a demo slide.* Diagram suggestion: the six words as a left-to-right arrow chain, nothing else on the slide. Key takeaway: this loop repeats every single day of the course. Speaker notes: say it, don't over-explain it yet — the Hook is about to demonstrate it.
4. **Course roadmap, one screen.** The six-stage diagram: Hook → Architecture → Diagnostics → Evidence Toolkit (AWR/ASH) → SQL/Plans/Optimizer → Memory/I/O/Concurrency → Capstone (see ASCII/description below). *Not a demo slide.* Key takeaway: "here's the whole shape of where we're going, before we go anywhere." Speaker notes: name roughly which day-range each stage covers, but don't read the 34-row table — that's not this slide's job.
5. **PRODUCTION SCENARIO — Setting the scene.** "A batch reconciliation job that finishes in 4 minutes took 45 minutes last night. Finance wants to know why the numbers were late." *PRODUCTION SCENARIO slide.* Diagram suggestion: a simple clock/calendar graphic contrasting "4 min" vs. "45 min." Key takeaway: this is a real, business-visible incident shape, not an academic exercise. Speaker notes: pause here — let the stakes land before opening any tool.
6. **LIVE DEMO — Baseline, then reproduce it live.** Show the `RECON_RUN_LOG` baseline history query, then kick off today's run via `DBMS_SCHEDULER`. *LIVE DEMO slide.* Key takeaway: "every prior run looked like this — let's watch today's run happen in real time." Speaker notes: narrate that the job is now running in the background while we investigate.
7. **LIVE DEMO — Reading the picture.** Side-by-side AVT screenshots: clean baseline (green) vs. today, live (growing red). *LIVE DEMO slide.* Diagram suggestion: literally the two AVT chart captures, side by side. Key takeaway: "we know something changed and roughly when, before reading a single line of SQL." Speaker notes: stop talking for a few seconds; let the room look.
8. **LIVE DEMO — Ruling out false leads.** Two-column callout: "❌ More data? Checked — ruled out." / "❌ Blocking? Checked — ruled out." *LIVE DEMO slide.* Key takeaway: real investigations check plausible guesses instead of arguing about them. Speaker notes: this is the moment to say "this is the discipline the whole course is built around."
9. **LIVE DEMO — Narrowing to SQL_ID, wait event, and plan line.** Live queries from `diagnose.sql` Steps A, D–H. *LIVE DEMO slide.* Diagram suggestion: a funnel graphic — "all activity" → "one SQL_ID" → "one wait event" → "one plan line." Key takeaway: "picture to proof, in five queries." Speaker notes: pause on the Estimated-vs-Actual rows output — that number IS the punchline.
10. **LIVE DEMO — Fix and validate.** `fix.sql` unlock+gather, then `validate.sql`'s before/after comparison table. *LIVE DEMO slide.* Key takeaway: "same query, same data, correct plan — proven, not felt." Speaker notes: explicitly say why a hint or forced index would have been the wrong fix — this is a key talking point, not a footnote.
11. **Q&A — What did you notice?** The four discussion prompts, shown as bullets. *Not a demo slide.* Key takeaway: this was real investigation, and you just watched the whole loop happen once. Speaker notes: let silence sit; don't rush to fill it.
12. **Recap + homework.** Three bullets (the loop; picture-then-proof; false leads are normal) plus the homework assignment. *Not a demo slide.* Key takeaway: "tomorrow, you drive." Speaker notes: preview Day 2 in one sentence — "yesterday you watched; today you'll run this same chain yourself, start to finish."

**Instructor introduction template (slide 2 — fill in before teaching):**
- Name, years as a working Oracle DBA: _____
- One or two production incidents you personally solved that you're comfortable naming (industry/scale, not confidential specifics): _____
- The kind of environment you've worked in most (OLTP / reporting / mixed / regulated industry, etc.): _____
- Why you built this course evidence-first instead of slide-first — one or two sentences, in your own words: _____
- (Optional) One thing you still find genuinely hard or interesting about performance work, even after years of doing it: _____

**Course roadmap diagram (slide 4 — draw or render as a single row of six boxes with arrows):**
```
[ 1. HOOK ]  ->  [ 2. ARCHITECTURE ]  ->  [ 3. DIAGNOSTICS ]  ->
[ 4. EVIDENCE TOOLKIT (AWR/ASH) ]  ->  [ 5. SQL / PLANS / OPTIMIZER ]  ->
[ 6. MEMORY / I/O / CONCURRENCY ]  ->  [ CAPSTONE ]

Days 1-2        Days 3-9            Days 10-11         Days 12-18
                                                          |
                                     Days 19-27  <--------+
                                        |
                                     Days 28-33  ---> Day 34
```
Each box gets one caption line under it in the actual slide: HOOK — "prove the method works"; ARCHITECTURE — "know what you're looking at"; DIAGNOSTICS — "V$ views, wait events, OS metrics"; EVIDENCE TOOLKIT — "AWR/ASH, the daily-use toolkit"; SQL/PLANS/OPTIMIZER — "why the database chose that plan"; MEMORY/I/O/CONCURRENCY — "the deep resource-level stages"; CAPSTONE — "one incident, everything at once, no help."

## Homework

1. Sign up for a free OraPub account and download the ASH Visualization Tool (`orapub.com/tools`) if you have access to any 19c instance, lab or otherwise — you don't need to run it against anything real yet, just get it installed so Day 15 isn't the first time you've opened it.
2. Write three to five sentences describing a real time someone told you "it's slow" — at work, in a class, anywhere — and how you actually investigated it (or, if you didn't investigate it systematically at the time, how you would now, using today's loop). No need to share it; the point is making yourself write it down.
3. From memory, without looking back at today's material, write out the six words of the investigative loop in order. Check yourself against the Student Notes section above.
4. Preview for Day 2: today you watched the investigation happen. Tomorrow you drive the same chain yourself, independently, on a comparable incident, start to finish — review `diagnose.sql`'s Chain Steps A–I once more before class so the shape of the chain is fresh, not so you memorize today's specific answers.
