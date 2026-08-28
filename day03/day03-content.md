# Day 3 — Architecture Bootcamp I: Instance vs. Database, Memory at a Glance

## Topic
What an Oracle **instance** actually is, what an Oracle **database** actually is, why they are genuinely separate things (not two names for the same thing), and what the SGA and PGA are *for* at an architecture level — plus the conceptual difference between background and foreground (server) processes. Part 1 of the 4-day Architecture Bootcamp (Days 3–6).

## Duration
60 minutes

## Difficulty
Beginner

## Learning Objectives
By the end of this session, a student should be able to:

1. State the precise definitions of "instance" and "database" and explain why they are separate concepts, not synonyms.
2. Name the memory structures that make up the SGA and the PGA, and explain what each one is *for* (not yet how to size or tune it — that's Stage 10, Days 28–29).
3. Read `V$INSTANCE`, `V$DATABASE`, `V$PROCESS`, `V$BGPROCESS`, `V$SGA`, and `V$SGAINFO` and map every concept taught in this session to a real row or column in those views.
4. Explain the conceptual difference between a background process and a foreground (server) process, and name at least four mandatory background processes.
5. Explain, at a high level, how the CDB/PDB (multitenant) architecture fits into the instance/database picture — one instance, one physical database (the CDB), multiple pluggable containers.
6. Diagnose, from architecture knowledge alone, why a connection attempt to a specific PDB can fail even though the instance is up and healthy.

## Theory

Ask ten working DBAs to define "instance" and "database" off the cuff and at least a few will blur the two together — and the confusion is understandable, because in day-to-day language people say "the database is down" when they mean "the instance is down," and "connect to the database" when they mean "connect to the instance that has a database mounted." For daily conversation that's harmless. For actually understanding how Oracle behaves — and for every diagnostic session for the rest of this course — the distinction has to be exact.

**An instance is memory plus processes.** Specifically, an instance is the System Global Area (SGA) — a shared region of memory allocated in RAM when the instance starts — together with a set of background processes that Oracle starts alongside it. Nothing about an instance is stored on disk as "the instance." It exists only in RAM and in the OS process table, for as long as it is running, on the host where it was started. When you run `STARTUP NOMOUNT`, Oracle allocates the SGA and starts the background processes — full instance, zero database, because at that point Oracle hasn't even looked for a database yet.

**A database is a set of physical files.** Specifically, the datafiles that hold table and index data, the control file(s) that record the database's physical structure and identity, the online redo log files that record changes, and (once you're inside a CDB) the datafiles belonging to each pluggable database. A database is inert. It doesn't do anything by itself — it's just organized bytes sitting on storage, waiting for an instance to mount and open it.

The separation is the whole point of Oracle's `STARTUP` sequence, and this sequence is the cleanest possible proof that instance and database are different things:

- **NOMOUNT** — instance exists (SGA allocated, background processes running); no database is associated with it yet. `V$DATABASE` returns no rows because there is, from this instance's point of view, no database yet.
- **MOUNT** — the instance has read the control file and associated itself with a specific database's physical structure, but the datafiles are not yet accessible for queries. `V$DATABASE` now returns a row; `OPEN_MODE` reports `MOUNTED`.
- **OPEN** — the datafiles are open and consistent, and the database is usable. This is the state you find a healthy production system in almost all the time, which is exactly why the NOMOUNT and MOUNT states are the ones people forget exist.

The instance/database separation also explains something every DBA eventually needs to reason about even outside a RAC context: nothing in principle ties one instance to one database permanently. In a single-instance environment (what this lab runs), one instance mounts and opens exactly one database for its whole life, and in practice they feel inseparable. But architecturally the instance is what you start, and the database is what you point it at — and Oracle Real Application Clusters (RAC) makes that separation load-bearing by having *multiple* instances, on multiple hosts, each with its own SGA and background processes, all mounting and opening the *same* one database concurrently. RAC is only a forward pointer here (Day 32 covers it) — but seeing the shape of it now, on Day 3, is exactly why the instance/database distinction has to be solid before then.

**SGA and PGA are both "Oracle memory," but they are not the same kind of memory, and confusing them causes real misdiagnosis later in this course.** The SGA is shared: one region, allocated once when the instance starts, readable and writable by every session connected to that instance. Its job is to let many sessions cooperate — cache data blocks so the next session doesn't have to re-read them from disk (buffer cache), cache parsed SQL and PL/SQL so the next session doesn't have to re-parse identical statements (shared pool, including the library cache and dictionary cache), and buffer redo change vectors before they're written to the online redo logs (redo log buffer). Depending on configuration you'll also see a large pool (used by RMAN, parallel execution, and some shared-server operations), a Java pool, and a streams pool — all still shared, all still SGA. None of this is being sized or tuned today; today the point is only what each piece is *for*.

The PGA is private. Each server process gets its own PGA — memory Oracle allocates for that one process's work: sort operations, hash joins, bitmap merges, session-specific cursor state, and PL/SQL variables local to that session. No other session can read another session's PGA, and that's not an accident — a sort workspace or a private cursor context has no reason to be visible instance-wide. This is why "PGA and SGA are the same kind of memory" is a genuine misconception worth naming explicitly: mentally merging them leads people to expect memory-tuning changes (raising `PGA_AGGREGATE_TARGET`, say) to affect things that only SGA-resident structures actually control, like the buffer cache hit behavior — and vice versa. Getting this boundary right now avoids real confusion in Stage 10.

Finally, the background-vs-foreground process distinction: **background processes belong to the instance.** They start when the instance starts, run for as long as the instance runs, and each does one job for the instance as a whole — `PMON` cleans up after failed sessions, `SMON` handles instance recovery and space management, `DBWn` writes dirty buffers from the buffer cache to datafiles, `LGWR` writes redo from the log buffer to the online redo logs, `CKPT` updates checkpoint information in the control file and datafile headers, and `ARCn` (when the database runs in `ARCHIVELOG` mode) copies filled redo logs to archive storage before they're reused. **Foreground (server) processes belong to sessions.** Oracle starts one per client connection (in the default dedicated-server model) to actually execute that session's SQL against the SGA and, eventually, disk. Today's goal is just to see this distinction cleanly in `V$PROCESS` and `V$BGPROCESS` — the deep dive into exactly what each process does under load is Day 5's job.

After this session, a DBA should be able to draw the instance/database boundary from memory, explain what each SGA component and the PGA are for without reaching for a tuning parameter, and read `V$INSTANCE`/`V$DATABASE`/`V$PROCESS`/`V$BGPROCESS`/`V$SGA` cold on a system they've never seen before and correctly describe what they're looking at.

## Key Concepts

- **Instance** = SGA (shared memory) + background processes. Exists in RAM/OS only; has no independent existence on disk.
- **Database** = the physical files: datafiles, control file(s), online redo logs, and (in a CDB) each PDB's own datafiles.
- **Startup states** — `NOMOUNT` (instance only) → `MOUNT` (instance + control file, no open datafiles) → `OPEN` (fully usable).
- **SGA** — shared, instance-wide memory: buffer cache, shared pool (library cache + dictionary cache), redo log buffer, large pool, Java pool, streams pool.
- **PGA** — private, per-server-process memory: sort/hash work areas, session cursor state, session PL/SQL variables.
- **Background processes** — instance-scoped, start with the instance, one per functional role (`PMON`, `SMON`, `DBWn`, `LGWR`, `CKPT`, `ARCn`, and others).
- **Foreground / server processes** — session-scoped, one per client connection under dedicated server, execute that session's work.
- **CDB / PDB** — one instance mounts one physical database, the CDB (container database); the CDB contains `CDB$ROOT`, the `PDB$SEED` template, and one or more application pluggable databases (PDBs). The instance's SGA and background processes are shared by every container — they are not duplicated per PDB.
- **Instance identity vs. database identity** — `INSTANCE_NAME` (and in RAC, `THREAD#`/instance number) identifies the instance; `DB_NAME`/`DB_UNIQUE_NAME` identifies the database. They are independent values that happen to often look similar in a single-instance lab.

## Important Views/Commands

| View / Command | What it tells you | Notes |
|---|---|---|
| `V$INSTANCE` | Instance identity and state: `INSTANCE_NAME`, `HOST_NAME`, `VERSION`, `STARTUP_TIME`, `STATUS`, `DATABASE_STATUS`, `INSTANCE_ROLE`, `PARALLEL` | One row — there is only one instance in a single-instance lab. `STATUS` shows `STARTED`/`MOUNTED`/`OPEN`. |
| `V$DATABASE` | Physical database identity: `NAME`, `DBID`, `CREATED`, `LOG_MODE`, `OPEN_MODE`, `DATABASE_ROLE`, `CDB`, `PLATFORM_NAME` | `CDB = 'YES'` confirms this is a container database. |
| `V$PDBS` | One row per pluggable database container: `CON_ID`, `PDB_NAME`, `OPEN_MODE`, `OPEN_TIME`, `RESTRICTED` | Always includes `PDB$SEED`; every real application PDB is a separate row. |
| `V$CONTAINERS` | One row per container including `CDB$ROOT` itself | Useful to see the whole container list in one query. |
| `V$PROCESS` | One row per OS process the instance owns: `PID`, `SPID` (OS process id), `PROGRAM`, `BACKGROUND` (`'1'` = background, `NULL` = foreground), `PGA_USED_MEM`, `PGA_ALLOC_MEM` | Joins to `V$SESSION` via `PADDR = ADDR` for foreground processes. |
| `V$BGPROCESS` | One row per background process slot: `NAME`, `DESCRIPTION`, `PADDR` | `PADDR != '00'` (or join to `V$PROCESS`) means that background process is currently running. |
| `V$SGA` | High-level SGA breakdown: `Fixed Size`, `Variable Size`, `Database Buffers`, `Redo Buffers` | Coarse view — four rows, in bytes. |
| `V$SGAINFO` | Fine-grained, named SGA component sizes plus `RESIZEABLE` flag | Better for mapping a component name (e.g. `Shared Pool Size`) to a byte value. |
| `V$PGASTAT` | Instance-wide PGA statistics: `total PGA allocated`, `total PGA used by SQL workareas`, etc. | Confirms PGA is tracked completely separately from SGA. |
| `V$PARAMETER` | Instance-identifying and memory-related parameters: `instance_name`, `db_name`, `db_unique_name`, `service_names`, `sga_target`, `sga_max_size`, `pga_aggregate_target` | Filter with `WHERE NAME IN (...)`. |
| `V$VERSION` | Oracle version banner | Confirms 19c. |
| `SHOW PARAMETER`, `STARTUP`/`SHUTDOWN` | SQL*Plus/SQLcl convenience commands | Referenced conceptually today; the full startup/shutdown mechanics belong to Day 5's process deep-dive. |

## Practical Demo

This is a conceptual architecture day, not an incident day — there's no system to break. The eight-step lab rhythm used across the course is adapted here into an **orient-and-map** flow: instead of Baseline → Break It → Observe → Investigate → Prove → Fix → Validate → Reset, today runs Baseline/Orient → four view-walks (one per concept) → two live "what would happen if" architecture questions → Validate understanding → Reset. Every step still maps to a concrete script (`demo.sql`, `diagnose.sql`).

**Step 1 — Baseline / Orient.** Connect as the lab's DBA-privileged account (e.g. `SYSTEM`) to the CDB root. Confirm where you are before looking at anything else: current container, current user, database name, instance name. This is the habit every good DBA builds first on an unfamiliar system, and it's exactly what Day 3's Real-World Scenario is built around.

**Step 2 — Walk `V$INSTANCE`.** Show `INSTANCE_NAME`, `HOST_NAME`, `VERSION`, `STARTUP_TIME`, `STATUS`. Explicitly connect `STATUS = OPEN` back to the NOMOUNT/MOUNT/OPEN theory just taught — this instance has already progressed through all three states, we're only ever looking at it after the fact.

**Step 3 — Walk `V$DATABASE` and `V$PDBS`.** Show `NAME`, `DBID`, `CDB`, `OPEN_MODE` from `V$DATABASE`, then show every row of `V$PDBS` — this is the first moment students see the CDB/PDB layer as literal query output rather than a diagram.

**Step 4 — Walk `V$SGA` and `V$SGAINFO`.** Show the coarse four-row `V$SGA` breakdown, then the finer `V$SGAINFO` component list. Explicitly name what each nonzero component is *for*, tying it back to the Theory section (buffer cache → cached blocks, shared pool → parsed SQL/dictionary, redo buffer → pending redo, large pool → RMAN/PQ if configured).

**Step 5 — Walk `V$PROCESS` and `V$BGPROCESS`.** Show the full background process list first (`PMON`, `SMON`, `DBW0`, `LGWR`, `CKPT`, plus whichever others are running), each with a one-line "what this does" from Theory. Then show `V$PROCESS` filtered to `BACKGROUND = '1'` (same rows, from the process side) and `BACKGROUND IS NULL` (foreground/server processes — including the very session running this query).

**Step 6 — Investigate: two live "what would happen if" questions.** (a) *"If I run this same `V$SGA` query from inside `PERFPDB` instead of the CDB root, does the SGA total change?"* — run it in both containers, observe it's identical, and explain why (SGA belongs to the instance, not to any one container). (b) *"Do background processes exist per-PDB, or per-instance?"* — query `V$BGPROCESS` from inside `PERFPDB` too, observe the same process list, same conclusion.

**Step 7 — Validate understanding.** Ask students to state, in their own words and without looking at notes, what each view just proved. This is a checkpoint, not a quiz — the real Q&A comes later.

**Step 8 — Reset.** Return the session to `CDB$ROOT`, clear any SQL*Plus column formatting used for the demo. Nothing was created or modified today, so "reset" is entirely about leaving a clean session for the next block, not undoing a change (see `reset.sql`).

## Real-World Scenario — "A New DBA Inherits an Unfamiliar System"

**Setup.** You've just joined a team and been handed a connection string and a password. Nobody has time to walk you through the environment today — you're told "it's an Oracle system, go get familiar with it," and left alone with a terminal. This happens constantly in real careers, and the instinct that separates a DBA who's comfortable from one who's guessing is exactly the orientation habit built into today's demo.

**The orientation queries.** You connect and, before touching any application data, run the same four view-walks from the demo: `V$INSTANCE`, `V$DATABASE`, `V$PDBS`, `V$SGA`. In under two minutes you now know: this is a single 19c instance named `PERFCDB1` (example), running on host `perflab01`, up for eleven days; the database is named `PERFCDB`, and — this is the detail that matters — `V$DATABASE.CDB` reports `YES`.

**The small mystery.** You query `V$PDBS` expecting one row for "the database" and get *two*: `PDB$SEED` and `PERFPDB`. Your first instinct, if you didn't know better, might be to assume there are two separate application databases here and start wondering which one is "the real one," or worse, to try connecting to `PDB$SEED` looking for application tables. Both instincts are wrong, and knowing why is the entire point of today's session: `PDB$SEED` is not an application database at all — it's the read-only template Oracle uses internally whenever a new PDB gets created by cloning; it is never meant to be connected to for application work and normally sits in `READ ONLY` mode. `PERFPDB` is the one actual application container, and it's the one whose service name your connection string should point to for real work.

**Resolving it.** You confirm the read by checking `OPEN_MODE` for each row — `PDB$SEED` shows `READ ONLY`, `PERFPDB` shows `READ WRITE` — and by checking `V$SERVICES`/`V$PARAMETER (service_names)` to see which service maps to which container. Two rows in `V$PDBS` didn't mean "two databases to choose between." It meant "one instance, one physical database (the CDB), and exactly one of its containers is meant for application traffic." You've just correctly reconstructed the architecture of a system you'd never seen before, purely from dictionary views — no documentation, no tribal knowledge, no guessing.

**The lesson.** A DBA who understands the instance/database/CDB/PDB separation can walk onto any unfamiliar 19c system and, in a few minutes and a handful of read-only queries, know exactly what they're looking at. A DBA who doesn't will misread `V$PDBS`'s two rows as "two databases," waste time looking for data in the wrong container, or — worse, in a real incident — restart or reconfigure the wrong thing because the mental model was wrong from the start.

## Hands-on Lab — Mapping a Live Instance's Architecture End-to-End

**Objective.** Using only dictionary/`V$` views (no performance angle), build a complete, written architecture map of the lab instance — what it's made of, not how well it's running.

**Exact views to query, in this order, and the conclusion each one should produce:**

1. `V$VERSION` — record the exact 19c release string. *Conclusion: confirm the Oracle version you're working against before assuming any feature/view behavior.*
2. `V$INSTANCE` — record `INSTANCE_NAME`, `HOST_NAME`, `STARTUP_TIME`, `STATUS`. *Conclusion: this instance has been continuously up since `STARTUP_TIME`; it is currently `OPEN`.*
3. `V$DATABASE` — record `NAME`, `DBID`, `CDB`, `LOG_MODE`, `OPEN_MODE`, `PLATFORM_NAME`. *Conclusion: this is (or isn't) a multitenant CDB, and whether it's running in `ARCHIVELOG` mode.*
4. `V$PDBS` and `V$CONTAINERS` — record every container, its `CON_ID`, and its `OPEN_MODE`. *Conclusion: a full container inventory — which one is the seed, which one(s) are real application PDBs.*
5. `V$PARAMETER` filtered to `instance_name`, `db_name`, `db_unique_name`, `service_names` — record all four values side by side. *Conclusion: instance identity and database identity are independent strings that happen to look related in this lab — write down where they differ, however slightly.*
6. `V$SGA` and `V$SGAINFO` — record every named component and its size. *Conclusion: a labeled inventory of what's actually inside this instance's shared memory right now.*
7. `V$PGASTAT` (row `total PGA allocated`) — record the value. *Conclusion: a second, completely separate memory total exists outside the SGA — proof PGA and SGA are not the same pool.*
8. `V$BGPROCESS` joined to `V$PROCESS` — record every currently-running background process name and its OS `SPID`. *Conclusion: a full list of "what the instance itself is doing" independent of any session.*
9. `V$PROCESS` filtered to `BACKGROUND IS NULL`, joined to `V$SESSION` — record how many foreground/server processes exist right now and which session each belongs to (including your own). *Conclusion: foreground process count tracks connection count, not instance count — this will matter again on Day 5.*

**Deliverable.** A short written architecture summary (half a page is enough) covering: instance name/host/uptime, database name/DBID/CDB status, full container list, SGA component inventory with sizes, and background process inventory. A student who can produce this for a system they'd never seen before, in under fifteen minutes, has met today's objective.

## Troubleshooting Challenge — "Why Won't This Connection Open the PDB?"

**Symptom.** A student (or teammate) reports: *"I can connect to the CDB root fine with SYSTEM, but when I try to connect using the `PERFPDB` service, I get `ORA-01033: ORACLE initialization or shutdown in progress`. Nothing else has changed."*

**Diagnostic path (architecture reasoning only, no perf angle):**

1. Connect to `CDB$ROOT` as the DBA account — if that succeeds, the instance itself is healthy and open. This immediately narrows the problem to something container-specific, not instance-wide.
2. Query `V$PDBS` (or `V$CONTAINERS`) and check `PERFPDB`'s `OPEN_MODE`. If it reads `MOUNTED` instead of `READ WRITE`, that's the root cause: the PDB is mounted (its datafiles are known to the instance) but not open (they're not accessible for queries yet) — exactly the MOUNT-vs-OPEN distinction from today's Theory, just applied one layer down at the container level instead of at the whole-database level.
3. Confirm the fix conceptually: `ALTER PLUGGABLE DATABASE PERFPDB OPEN;` from the CDB root moves that one container from `MOUNTED` to `READ WRITE`, without needing to touch the instance or any other container at all.
4. Re-check `V$PDBS.OPEN_MODE` to validate, then confirm the original connection string now succeeds.

**The teaching point.** This error has nothing to do with the instance being unhealthy — it's proof that "open" is a *container-level* state in a CDB, not just an instance-level one, and that a perfectly healthy instance can still refuse a specific PDB's connections. Reasoning through this cleanly requires exactly the mental model this session built: instance state and (per-container) database state are tracked separately, and a symptom that looks instance-wide ("I can't connect!") can actually be scoped to one container.

## Q&A

1. **(Recall)** What two things make up an Oracle instance, and what makes up an Oracle database? Give one concrete example of something that belongs to each.
2. **(Explain why)** Why can an instance exist without a mounted database at all? Under what real circumstance would you actually see an instance sitting in that state?
3. **(Explain why)** SGA is described as "shared" and PGA as "private." What would actually go wrong — mechanically — if two sessions' sort work areas lived in the same shared memory region instead of separate private ones?
4. **(Scenario reasoning, not perf)** A colleague says: *"I increased the instance's SGA, so now the database has more room to store data."* What's factually wrong with that sentence, and what would you say to correct their mental model without being condescending about it?

## Interview Questions

1. "Explain, in your own words, the difference between an Oracle instance and an Oracle database. Then describe one real situation where getting that distinction wrong would actually cause a mistake."
2. "What lives in the SGA, and how is that different from what lives in the PGA? Name at least three SGA components and explain what each is for."
3. "Walk me through what a background process is for, as a category, and name three mandatory background processes along with the job each one does."

## Instructor Notes

- **Pacing:** Theory runs long on this particular day relative to most (it's the foundation the next three Bootcamp days build on) — budget roughly 20 minutes theory, 20 minutes demo, 10 minutes scenario, 5 minutes lab kickoff, 5 minutes Q&A. Don't let this slip past 25 minutes of theory; the view-walk in the demo reinforces everything better than more slides would.
- **Where students get stuck:** almost always at the NOMOUNT state — many working DBAs have genuinely never seen it, because production systems are almost always found already OPEN. If time allows and a spare sandbox instance is available, a live `SHUTDOWN IMMEDIATE` followed by `STARTUP NOMOUNT` and a `V$DATABASE` query returning `ORA-01507`/no rows is the single most convincing five minutes of the whole session — students who see "the instance is clearly running, and yet there is no database" internalize the separation permanently. If no spare instance is available, narrate it and show the expected output instead; don't do this against the shared PERF_LAB instance other days depend on.
- **Don't get pulled into tuning.** Multiple students will ask "so what's a good SGA size?" — this is Stage 10 (Days 28–29)'s job, not today's. Park it explicitly: "great question, we're coming back to that on Day 28 once you've seen how memory actually gets used under load — today is only what it's *for*."
- **Don't get pulled into RAC.** The forward pointer to RAC in the instance/database section is intentional and should stay a single sentence in class — Day 32 owns that material. Resist the urge to sketch cache fusion on the whiteboard today.
- **Version note:** `V$PROCESS.BACKGROUND` (`'1'`/`NULL`) has existed since 12.1 — worth a one-line mention if anyone in the room has 11g muscle memory, since older habits sometimes filter `V$BGPROCESS` alone and assume `V$PROCESS` has no equivalent marker.
- **Screen habit to model:** literally run `SHOW CON_NAME` (or query `SYS_CONTEXT('USERENV','CON_NAME')`) before every other query during the live demo, out loud, every time. This is the single habit from today most likely to prevent real container-confusion mistakes later in students' careers.

## Student Notes

**The one sentence to remember:** *An instance is memory and processes; a database is files on disk. They are related, not identical — and Oracle's own startup sequence (NOMOUNT → MOUNT → OPEN) is the proof.*

**Cheat-sheet mapping (view → what it proves):**

| If you want to know... | Query... |
|---|---|
| Is the instance itself healthy? | `V$INSTANCE` |
| What database is mounted, and is this a CDB? | `V$DATABASE` |
| What containers (PDBs) exist and are they open? | `V$PDBS` / `V$CONTAINERS` |
| What's in shared memory right now? | `V$SGA` / `V$SGAINFO` |
| What's in this session's private memory? | `V$PGASTAT`, `V$PROCESS.PGA_*` for your own PID |
| What is the instance itself doing (independent of any session)? | `V$BGPROCESS` |
| What is my session's own server process doing? | `V$PROCESS` joined to `V$SESSION` where `BACKGROUND IS NULL` |

**Misconceptions to actively un-learn:**
- "Instance and database are the same thing." → They're related but separable; NOMOUNT proves it.
- "SGA and PGA are the same kind of memory." → SGA is shared and instance-wide; PGA is private and per-process.
- "A CDB with two rows in `V$PDBS` means two application databases." → One of those rows is very likely `PDB$SEED`, a template, not an app database.
- "Bigger SGA = bigger database." → SGA is a cache sized independently of how much data actually exists on disk (see `fix.sql` for real numbers proving this).

## PPT Outline

1. **Title slide** — "Day 3: Architecture Bootcamp I — Instance vs. Database, Memory at a Glance." Course branding, instructor name (Amit Pawar).
2. **Learning objectives** — the six bullet objectives from this document, verbatim.
3. **The myth callout** — large text: *"An instance and a database are NOT the same thing."* One-line teaser, no explanation yet — sets up the rest of the deck.
4. **Diagram — Instance vs. Database (two boxes).** Left box labeled "INSTANCE" containing "SGA" and a small stack of background-process icons (PMON/SMON/DBWn/LGWR/CKPT/ARCn); right box labeled "DATABASE" containing icons for datafiles, control file, redo logs. A single labeled arrow between them: "MOUNT." *Diagram suggestion: simple two-rectangle architecture diagram, RAM-colored box on the left, disk-colored box on the right.*
5. **Diagram — Startup states.** Three-stage horizontal flow: NOMOUNT → MOUNT → OPEN, with a small "instance present? database present?" checkbox pair under each stage (NOMOUNT: instance ✓, database ✗; MOUNT: both ✓ but datafiles closed; OPEN: both ✓, fully usable).
6. **SGA at a glance.** Diagram of the SGA as one large box subdivided into labeled regions: Buffer Cache, Shared Pool (Library Cache + Dictionary Cache), Redo Log Buffer, Large Pool, Java Pool, Streams Pool — each with a one-phrase "what it's for" caption.
7. **PGA at a glance.** Diagram showing several small separate boxes, one per server process, each labeled "PGA (private)" — visually contrasting "one shared box" (slide 6) against "many small private boxes" (this slide).
8. **SGA vs. PGA comparison table slide.** Two-column table: Shared / Instance-wide / Allocated at instance startup / Visible to all sessions **vs.** Private / Per-process / Allocated per connection / Visible only to that process.
9. **Background vs. foreground processes.** Diagram: instance box spawning background processes at startup (arrow labeled "instance starts"), separate from a row of client connections each spawning one server process (arrow labeled "client connects") — visually showing background processes as few/fixed and foreground processes as scaling with connections.
10. **CDB/PDB architecture.** Diagram: one instance box connected to one CDB box; inside the CDB box, three smaller boxes: `CDB$ROOT`, `PDB$SEED`, and the application PDB (e.g. `PERFPDB`) — all sharing the one SGA/background-process instance drawn alongside.
11. **Live demo recap slide.** The view-to-concept mapping table from Student Notes, shown as a clean reference table for students to photograph/screenshot.
12. **Recap + homework slide.** Three bullet takeaways (instance ≠ database; SGA shared vs. PGA private; background vs. foreground) plus the homework assignment below.

## Homework

1. On any 19c instance you have access to (the lab instance, or your own sandbox), run the full nine-query Hands-on Lab sequence independently — without looking at today's demo script — and produce the half-page architecture summary described in the Lab section.
2. Write, in your own words (3–5 sentences), why an instance can exist without a mounted database, using the NOMOUNT state as your example. Avoid copying the course's wording — use your own.
3. Draw (by hand or in any tool you like) the instance-vs-database two-box diagram from memory, including at least four background processes and four SGA components. Compare it against the PPT diagram tomorrow.
4. Preview question for Day 4: query `DBA_DATA_FILES` and `DBA_TABLESPACES` against `PERF_LAB`'s tablespaces, and just look at the output — no analysis required yet. Day 4 picks up exactly where today's "database = files on disk" idea left off, at the tablespace/segment/extent/block level.
