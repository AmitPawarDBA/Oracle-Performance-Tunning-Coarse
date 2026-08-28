# Day 5 — Architecture Bootcamp III: Process Architecture & Connections

## Topic
Dedicated vs. shared server connections, listener basics, and the roles of the core Oracle background processes (PMON, SMON, DBWn, LGWR, CKPT, ARCn). Part 3 of the 4-day Architecture Bootcamp (Days 3–6). This is pure Oracle architecture — no performance-tuning framing yet. That starts in Stage 1 (Day 7 onward), once this foundation is in place.

## Duration
60 minutes

## Difficulty
Beginner

## Learning Objectives
By the end of this session, students will be able to:
1. Explain the difference between a dedicated server connection and a shared server connection, and state why shared server exists at all.
2. Determine, from `V$SESSION`, which connection type a given session is using.
3. Describe the TNS listener's actual job in establishing a connection — and correctly state when the listener is *not* involved at all.
4. Name each of the six core background processes (PMON, SMON, DBWn, LGWR, CKPT, ARCn) and describe, in plain language, what each one actually does.
5. Map an Oracle session to its underlying OS process, and vice versa, using `V$SESSION`, `V$PROCESS`, and OS-level tools.
6. Safely terminate a session they created for a demo, and explain what happens next (and which process does the cleanup).
7. Given a report of "the connection just hangs," reason through where in the connection path to look first, using architecture knowledge alone.

## Theory

Every Oracle DBA eventually gets asked some version of "why won't it connect?" — and the honest answer is that "it" is not one thing. A connection request has to travel through several distinct pieces of Oracle architecture before a user ever sees a SQL prompt, and today's session is about knowing exactly what each of those pieces is, so that when something goes wrong you know where to look instead of guessing.

**Dedicated server vs. shared server.** The default, and by far the most common, connection architecture is the **dedicated server model**: every client connection gets its own private Oracle server process on the database host, for the lifetime of that connection. One session, one process, one-to-one. This is simple, predictable, and what almost every training environment and most production OLTP systems use. Its cost is memory and OS overhead — each dedicated server process carries its own PGA (Program Global Area), and on a system with thousands of concurrent connections (think: a web application that doesn't pool connections well, or a large batch of reporting users), thousands of OS processes each with their own PGA can exhaust memory and process table entries long before the CPU is actually busy.

**Shared server** (formerly "Multi-Threaded Server," MTS) exists specifically to solve that scaling problem. Instead of one process per session, a small pool of **dispatcher** processes (`Dnnn`) accepts incoming requests from many clients and drops them into a common request queue in the SGA; a small pool of **shared server** processes (`Snnn`) pulls requests off that queue, executes them, and returns the response via a response queue back through a dispatcher to the right client. A session's private data (the UGA — User Global Area, holding things like sort space and session state) lives in the SGA (ideally the large pool) instead of in a dedicated process's PGA, because with shared server there is no single process a given session can call "its own" from one request to the next. Shared server is configured via the `DISPATCHERS` and `SHARED_SERVERS` initialization parameters and must be requested explicitly by the client (via `(SERVER=SHARED)` in the connect descriptor, or a database-side default). Most systems never touch it; it is a deliberate design choice for very high connection counts, not a default anyone stumbles into by accident.

**How to tell which one a session is using:** `V$SESSION.SERVER` tells you directly — it reads `'DEDICATED'`, `'SHARED'`, `'PSEUDO'` (a session temporarily not attached to any server process, mid-request under shared server), or `'POOLED'` (Database Resident Connection Pooling, a third, related-but-distinct model). This is the fact every DBA should be able to check in ten seconds, and it is the demo's first stop.

**The listener's real job.** The TNS listener (`lsnrctl`) is a network traffic director, not a query processor. Its entire job is: accept an incoming connection request on its configured port, match the requested service name against services registered with it (either statically in `listener.ora`, or — far more commonly — dynamically, when the database instance itself registers its services and load with every listener it knows about), and then hand the client off to a server process. For dedicated server, on Unix/Linux this is classically a `fork()`+`exec()` of a new dedicated Oracle server process, which then owns the socket directly — at which point **the listener is completely out of the conversation** for the rest of that session's life. This is the single most important fact for today's real-world scenario: once a session is connected, the listener has nothing more to do with it, so a listener problem can *cause* a failed or hanging connection attempt, but it cannot cause an already-connected session to behave badly. One more wrinkle worth knowing: local connections made with the bequeath (`BEQ`) protocol — for example `sqlplus / as sysdba` run directly on the database host — never touch the listener at all. If someone reports a hang while connected locally with `/ as sysdba`, the listener is provably irrelevant to that report before you check anything else.

**Background processes — the crew that keeps the instance alive.** Every Oracle instance runs a fixed set of background processes, visible in `V$BGPROCESS` and, at the OS level, as processes named `ora_<name>_<SID>`. The ones this course focuses on today:

- **PMON (Process Monitor)** — cleans up after *sessions and processes*. When a server process dies or a session is killed, PMON detects it, rolls back any uncommitted transaction that dead session held, releases its locks, frees its resources in the SGA, and restarts dead dispatchers/shared servers if needed. Think "session-level janitor."
- **SMON (System Monitor)** — cleans up at the *instance/system* level, not the session level. Its jobs include performing instance (crash) recovery at startup, cleaning up temporary segments that are no longer needed, and coalescing free space in dictionary-managed tablespaces. **PMON and SMON are not doing the same kind of cleanup** — PMON reacts to a dead session; SMON handles system-wide housekeeping and instance recovery. Confusing the two is one of the most common architecture misconceptions among newer DBAs.
- **DBWn (Database Writer, one or more: DBW0, DBW1, ...)** — writes modified ("dirty") buffers from the buffer cache to the datafiles. It writes lazily and asynchronously — triggered by checkpoints, by dirty buffers crossing a threshold, or when a foreground process can't find a free buffer — never simply "every time a row changes."
- **LGWR (Log Writer)** — writes redo log buffer entries to the online redo log files. This one *is* commit-synchronous: by default, a `COMMIT` does not return success to the client until LGWR has confirmed the redo for that transaction is on disk. LGWR also flushes on a timer (roughly every 3 seconds), when the redo buffer is a third full, and before DBWn is allowed to write a dirty buffer whose change isn't yet protected by redo on disk (the write-ahead logging rule).
- **CKPT (Checkpoint process)** — a common point of confusion: CKPT does **not** write data blocks. It signals DBWn to write, and it updates the control file and datafile headers with checkpoint information so instance recovery knows where to start. The actual I/O to datafiles is always DBWn's job.
- **ARCn (Archiver, one or more)** — only present when the database runs in `ARCHIVELOG` mode. When an online redo log fills and switches, ARCn copies it to the configured archive destination(s) before that log group can be reused, which is what makes point-in-time recovery and standby databases possible.

**One version nuance worth knowing:** in Oracle releases before 12c, PMON itself handled dynamic service registration with listeners. Since 12c, that job moved to a dedicated background process, **LREG** (Listener Registration), so on a 19c instance PMON's job is purely session cleanup — if you see older material claiming "PMON registers with the listener," that's outdated for the version this course targets.

**Misconception to retire today:** "every connection gets its own dedicated process no matter what." True for the common case, false as a universal rule — shared server and DRCP both exist precisely to break that one-to-one assumption, and a session's `V$SESSION.SERVER` value is how you find out which world you're actually in.

## Key Concepts
- Dedicated server: one OS process per session, PGA holds session state, simple and default.
- Shared server: dispatchers + shared server process pool, UGA lives in SGA, exists to scale connection count, not CPU.
- `V$SESSION.SERVER` is the definitive way to identify connection type for a session.
- The listener's job ends at connection handoff; it is not in the path of an established session's SQL calls.
- Local (`BEQ`) connections bypass the listener entirely.
- PMON = session/process-level cleanup. SMON = instance/system-level cleanup and crash recovery. Not the same job.
- DBWn writes dirty buffers lazily/asynchronously; LGWR writes redo synchronously at commit. Different triggers, different urgency.
- CKPT signals and records; it never performs the datafile I/O itself — that's always DBWn.
- ARCn only exists in `ARCHIVELOG` mode; it protects filled redo logs before reuse.
- Since 12c, LREG (not PMON) handles dynamic service registration with listeners.

## Important Views/Commands

| View / Command | What it tells you |
|---|---|
| `V$SESSION` | One row per session: `SID`, `SERIAL#`, `USERNAME`, `SERVER` (DEDICATED/SHARED/PSEUDO/POOLED), `PADDR`, `STATUS`, `PROGRAM`, `MACHINE`, `MODULE` |
| `V$PROCESS` | One row per Oracle process (foreground and background): `ADDR`, `SPID` (the OS PID), `PROGRAM`, `PGA_ALLOC_MEM` |
| `V$SESSION` joined to `V$PROCESS` on `V$SESSION.PADDR = V$PROCESS.ADDR` | Maps a logical Oracle session to the exact OS process serving it |
| `V$BGPROCESS` | One row per defined background process slot: `NAME`, `DESCRIPTION`, `PADDR` (join to `V$PROCESS` for the SPID; `PADDR = '00'` means that slot isn't started, e.g. optional ARCn slots) |
| `V$SYSSTAT` | Cumulative instance-wide statistics; filter on `'redo size'`, `'redo entries'`, `'redo writes'`, `'physical writes'`, `'user commits'` to watch LGWR/DBWn activity as deltas over time |
| `V$INSTANCE` | Instance name, host, status, version — the "what am I connected to" check |
| `V$RESOURCE_LIMIT` | Current vs. maximum utilization of `processes` and `sessions` — the first place to check for "can't connect" caused by resource exhaustion rather than a listener/network problem |
| `V$CIRCUIT`, `V$DISPATCHER`, `V$SHARED_SERVER` | Shared-server-specific views: circuits (client-to-dispatcher paths), dispatcher status, shared server process status — only populated when shared server is configured |
| `ALTER SYSTEM KILL SESSION 'sid,serial#' [IMMEDIATE]` | The safe, Oracle-aware way to end a session — marks it for PMON/the session itself to clean up |
| `ALTER SYSTEM DISCONNECT SESSION 'sid,serial#' [IMMEDIATE]` | Disconnects the client-side connection; for dedicated server this also terminates the server process |
| `LSNRCTL STATUS` | (conceptual — run at the OS, not SQL*Plus) Shows the listener's configured endpoints and every service currently registered with it, static or dynamic |
| `LSNRCTL SERVICES` | Shows registered services plus a breakdown of handler (dedicated/dispatcher) counts per service |
| OS `ps -ef \| grep ora_` | Lists every Oracle background process by name (`ora_pmon_<SID>`, `ora_smon_<SID>`, `ora_dbw0_<SID>`, `ora_lgwr_<SID>`, `ora_ckpt_<SID>`, `ora_arc0_<SID>`, ...) and every dedicated server process (`oracle<SID> (LOCAL=NO)` or similar) |
| OS `ps -p <spid> -o pid,pcpu,pmem,etime,cmd` / `top -p <spid>` | Correlates a specific OS PID (from `V$PROCESS.SPID`) to its live CPU/memory/uptime — **ENVIRONMENT DEPENDENT**, exact numbers vary by hardware |

## Practical Demo

This is a conceptual/observational day, so the demo is adapted from the course's usual Baseline→Break It→Observe→Investigate→Prove→Fix→Validate→Reset shape into eight architecture-focused steps. Every command is in `demo.sql`.

**Safety note up front, repeated in `demo.sql` and Instructor Notes: only ever kill a session you created for this demo, tagged and verified by `MODULE`/`PROGRAM` before every kill. Never run `ALTER SYSTEM KILL SESSION` or an OS-level `kill` against a session you did not personally start for this exercise.**

1. **Orient.** Connect as the lab DBA account. Check `V$INSTANCE` and `V$VERSION` to confirm what instance and version the class is looking at.
2. **Create a disposable dedicated-server session.** From a second terminal/session ("Session B"), connect as `PERF_LAB` and immediately tag it with `DBMS_APPLICATION_INFO.SET_MODULE('DAY05_DEMO_SESSION','disposable')` so it can be found unambiguously and never confused with a real session.
3. **Identify Session B.** From Session A, query `V$SESSION` filtered on `MODULE = 'DAY05_DEMO_SESSION'`; confirm `SERVER = 'DEDICATED'`.
4. **Map it to an OS process.** Join to `V$PROCESS` on `PADDR = ADDR` to get `SPID`; correlate that PID with `ps -ef | grep <spid>` at the OS (**ENVIRONMENT DEPENDENT** — exact process listing format varies slightly by OS/Oracle version).
5. **Kill it safely.** From Session A, run `ALTER SYSTEM KILL SESSION 'sid,serial#' IMMEDIATE` against Session B's exact `SID,SERIAL#` (re-verify the module tag immediately before the kill). Observe `STATUS` transition to `KILLED`.
6. **Observe PMON's cleanup.** Re-query `V$SESSION` — the row disappears once cleanup completes. Explain that PMON is the process that just did this work. *Optional instructor-only variant:* start a second disposable tagged session and, instead of `ALTER SYSTEM KILL SESSION`, terminate its OS process directly with `kill -9 <spid>` to show PMON detecting a hard process death (the crash-cleanup path) rather than a graceful Oracle-initiated kill — this step requires OS shell access and is explicitly instructor-only, never handed to students to run against arbitrary PIDs.
7. **Generate a write-heavy workload and watch LGWR/DBWn.** Capture a `V$SYSSTAT` baseline (`redo size`, `redo entries`, `redo writes`, `physical writes`, `user commits`), run `PERF_LAB.DAY05_GENERATE_WRITE_LOAD` (from `setup.sql`), then capture `V$SYSSTAT` again and show the deltas. Separately, join `V$BGPROCESS` to `V$PROCESS` to show LGWR's and DBWn's live SPIDs, and correlate with `ps`/`top` on those PIDs (**ENVIRONMENT DEPENDENT**).
8. **Reset.** Run `cleanup.sql` to confirm no disposable demo sessions or objects remain, returning the lab to a clean state for the next run.

## Real-World Scenario: "The connection just hangs"

**Symptom.** The application team reports that their app "just hangs" trying to connect to the database — no error, no login screen, the connection attempt simply sits there for a long time before eventually timing out. It happens for every user, every time, starting sometime this morning.

**Initial evidence.** The instructor confirms, on the database host: the instance is up (`V$INSTANCE.STATUS = 'OPEN'`), `LSNRCTL STATUS` shows the listener itself is up and accepting connections on its configured port, and `LSNRCTL SERVICES` shows the application's service (`PERFPDB`) registered with two dedicated-server handlers ready. `V$RESOURCE_LIMIT` shows `processes` and `sessions` nowhere near their limits.

**False lead investigated.** The first instinct is "the service must not be registered with the listener" — a classic, fast-failing cause (it produces `ORA-12514: TNS:listener does not currently know of service requested`, an immediate error, not a hang). But `LSNRCTL SERVICES` just proved the service *is* registered and ready. That rules this out — and it's an important distinction to teach: a missing/unregistered service fails fast; it does not hang.

**Root cause.** The database-side story is fine, which means the problem is upstream of the listener the app is even reaching. The app team's `tnsnames.ora` still points at `PORT=1522` — the port used before a maintenance window last night moved the listener to the standard `PORT=1521`. There is nothing listening on 1522 anymore, and the network firewall between the app tier and the DB host silently drops the connection attempt instead of returning a fast "connection refused" — so the client's TCP handshake just sits there until the OS/SQL*Net connect timeout eventually expires, which reads to the user as "it just hangs" rather than "it errors immediately."

**Fix.** Correct the `PORT` entry in the app server's `tnsnames.ora` (or the relevant `sqlnet.ora`/easy-connect string) to `1521`, matching the listener's actual current endpoint.

**Validation.** From the app server, `tnsping PERFPDB` now returns instantly instead of timing out, and a fresh connection completes immediately. On the database side, the new session appears in `V$SESSION` right away with `SERVER = 'DEDICATED'`.

**Lesson.** A hang and a fast error point to different places: a fast, explicit TNS error (like `ORA-12514`) usually means the client *reached* the listener and got a clear "no" — check service registration. A silent hang almost always means the client never got a clean answer at all — check whether the client can even reach the correct host/port in the first place, before assuming anything is wrong on the database side. This is fully diagnosable with Day 5's toolkit alone; nothing here required a wait-event or session-tracing investigation.

## Hands-on Lab: Map a Session to Its OS Process, and See What Every Background Process Is Doing Right Now

**Part 1 — Session-to-OS-process mapping.**
1. Open a fresh SQL*Plus (or SQLcl) session connected as `PERF_LAB` and tag it: `EXEC DBMS_APPLICATION_INFO.SET_MODULE('DAY05_LAB_SESSION','mapping-exercise');`
2. From a DBA session, run:
   ```sql
   SELECT s.sid, s.serial#, s.username, s.server, s.status,
          p.spid AS os_pid, p.program
   FROM   v$session s
   JOIN   v$process p ON p.addr = s.paddr
   WHERE  s.module = 'DAY05_LAB_SESSION';
   ```
3. At the OS, confirm the reported PID is real and belongs to an Oracle process: `ps -ef | grep <os_pid>` (**ENVIRONMENT DEPENDENT** — exact `ps` output columns vary by OS).
4. Record the `SID`, `SERIAL#`, `SPID`, and `SERVER` value for this session — this is the mapping a DBA needs before ever safely acting on a specific session.

**Part 2 — What's every background process doing right now.**
5. Run the `V$BGPROCESS` → `V$PROCESS` join in `diagnose.sql` to list every started background process (`PADDR != '00'`) with its `NAME`, `DESCRIPTION`, and OS `SPID`.
6. For LGWR and each started DBWn, correlate the `SPID` with `ps -p <spid> -o pid,pcpu,pmem,etime,cmd` (**ENVIRONMENT DEPENDENT**) and note which ones show recent CPU activity versus which are essentially idle at this moment.
7. Capture a `V$SYSSTAT` snapshot for `'redo size'` and `'physical writes'`, wait a short interval doing nothing, capture again, and confirm the deltas are small/near-zero on an idle lab — this is the baseline the write-workload step in the demo will be compared against.
8. Clean up: kill only the session you tagged in step 1, using its exact `SID,SERIAL#`, and re-run the query from step 2 to confirm it's gone.

## Troubleshooting Challenge

The lab environment starts throwing `ORA-00020: maximum number of processes exceeded` for new connection attempts during a mid-morning peak, while existing sessions keep working fine. This is a different failure shape from the "hangs" scenario above — here connections fail immediately and explicitly, and only *new* connections are affected. Using only what this session covered: check `V$RESOURCE_LIMIT` for `processes` and `sessions` (confirm `CURRENT_UTILIZATION` at or near `LIMIT_VALUE`); then look at `V$SESSION` joined to `V$PROCESS`, grouped by `MACHINE`/`PROGRAM`, to find which application host is holding an unusually large number of dedicated server connections open; conclude that a connection-pool bug in one app tier is opening new connections without ever closing old ones, slowly consuming every available process slot until nothing is left for anyone else. The immediate relief is identifying and closing the orphaned/idle sessions from that program (after confirming with the app team they're not mid-transaction); the real fix is the app team correcting their pool's connection-release logic, and — separately — an instructor discussion of whether the `PROCESSES` parameter itself was ever sized appropriately for the expected peak connection count in the first place.

## Q&A

1. **(What would you check first?)** A user says they can't connect and gets an error instantly, not a hang. Based on today's session, is your first instinct to look at the listener or at the database instance — and why does the *speed* of the failure matter to that decision?
2. **(Troubleshooting)** `V$SESSION.SERVER` for a session reads `'SHARED'`. Where does that session's private session state (its UGA) actually live, and why can't you assume that session has "its own" dedicated OS process the way most sessions do?
3. **(Scenario-based)** You need to safely terminate a session for a legitimate reason (e.g., it's holding a lock a business-critical job needs). Walk through exactly how you'd confirm you have the *correct* session before running `ALTER SYSTEM KILL SESSION`, and name the process that actually performs the cleanup afterward.
4. A colleague says "PMON and SMON basically do the same job — general cleanup." Correct this statement precisely: what does each one actually own, and give one concrete example of something only SMON does that PMON never does.

## Interview Questions

1. Explain, step by step, what happens between a client running `sqlplus user/pass@service` and that client getting a SQL prompt, for a standard dedicated-server connection. Where does the listener's involvement end?
2. What problem does shared server solve that dedicated server does not, and what is the architectural trade-off (what moves from the PGA to the SGA, and why does that matter)?
3. Name the six background processes covered today and, for each, give the one-sentence version of its job — then explain why "CKPT writes the dirty buffers to disk" is incorrect.

## Instructor Notes

- **Safety note (repeat this verbally before Step 5 of the demo, and again before the optional Step 6 variant):** only ever run `ALTER SYSTEM KILL SESSION` or an OS-level `kill` against a session created specifically for this demo and freshly re-verified by its `MODULE` tag immediately beforehand. Never demonstrate a kill against a session you did not personally start in this class — in a real environment this is how DBAs cause real incidents. The OS-level `kill -9` variant in Step 6 is instructor-only; do not have students run raw OS kills against arbitrary PIDs even in a lab, since a mistyped PID could hit a background process or another student's session.
- If the lab environment already has other student sessions connected, filter *everything* by the `MODULE = 'DAY05_DEMO_SESSION'` / `'DAY05_LAB_SESSION'` tags before showing any query result to the room — this avoids ever displaying (or worse, targeting) a real classmate's session by accident.
- The write-workload numbers in `V$SYSSTAT` are genuinely `ENVIRONMENT DEPENDENT` — on a shared/throttled lab VM the deltas may be much smaller than on a dedicated instructor machine. Frame the exercise around the *direction and existence* of the change, not specific absolute numbers.
- If `LSNRCTL STATUS`/`SERVICES` cannot be run live (e.g., students without OS/shell access to the DB host), walk through a captured sample output instead — the architecture lesson (what's registered, what a handler is) doesn't require live access, only the OS-PID correlation steps genuinely need shell access.
- Keep this day's framing strictly architectural. Resist the pull to start talking about "which wait event shows a slow LGWR" — that's Stage 4 territory (Day 17), not Day 5. Today answers "what is this process and what does it do," not "is it a bottleneck."

## Student Notes

- `V$SESSION.SERVER` is your one-query answer to "dedicated or shared?" — memorize this, it comes up constantly.
- The listener's job ends the moment your session is established (dedicated server) — don't waste time checking listener logs for a problem in a connection that's already three hours old and working until just now.
- Local `/ as sysdba` connections never touch the listener — rule it out immediately for that connection type.
- PMON = per-session cleanup after something dies. SMON = instance-wide cleanup and crash recovery. Different scope, different triggers.
- DBWn writes lazily; LGWR writes synchronously at commit. If you remember only one contrast from today, make it this one.
- CKPT never writes a data block itself — it tells DBWn to, and it updates the control file/headers.
- A fast, explicit connection error usually means you reached something that said "no." A silent hang usually means you never reached anything at all — check the network path before the database.

## PPT Outline

1. **Title** — Day 5: Architecture Bootcamp III — Process Architecture & Connections
2. **Where we are** — Bootcamp roadmap strip: Day 3 (Instance/Memory) → Day 4 (Storage/Redo/Undo) → **Day 5 (Processes/Connections)** → Day 6 (Statement Execution)
3. **Two ways in** — Dedicated server vs. shared server, side-by-side diagram: one box per client in dedicated model; many clients funneled through dispatchers → shared server pool in the other
4. **How a connection becomes a process** — Diagram: Client → Listener (matches service, hands off) → new dedicated server process (fork/exec) *or* → Dispatcher → shared request queue → Shared server process; include the BEQ local-connection bypass as a dotted-line shortcut around the listener box entirely
5. **Telling them apart** — `V$SESSION.SERVER` values table (DEDICATED/SHARED/PSEUDO/POOLED) and the `V$SESSION`↔`V$PROCESS` join via `PADDR=ADDR`
6. **Meet the background processes I — the cleanup crew** — PMON (session-level) vs. SMON (instance-level); one clear contrasting example for each
7. **Meet the background processes II — the writers** — DBWn (lazy, dirty-buffer writer) vs. LGWR (synchronous, commit-driven redo writer); the write-ahead-logging rule connecting them
8. **Meet the background processes III — bookkeeping & archiving** — CKPT (signals + records, never writes data) and ARCn (copies filled redo logs, only in ARCHIVELOG mode)
9. **Demo recap — kill and observe** — screenshot/recap of the safe kill sequence and PMON's cleanup; restate the safety rule prominently on this slide
10. **Demo recap — write workload** — `V$SYSSTAT` before/after deltas and the LGWR/DBWn SPID correlation
11. **Real-world scenario** — "the connection just hangs": the false lead (fast TNS error) vs. the actual root cause (silent network/port mismatch causing a slow timeout) — visual timeline of the symptom
12. **Wrap-up & next up** — today's key takeaways one-liner list, then a one-line teaser for Day 6: "you now know every piece — tomorrow we watch them all work together on one SQL statement"

## Homework

1. On any Oracle instance you have access to (or by reading the 19c documentation if you don't), find and record: is the instance configured for shared server (`DISPATCHERS` set)? If so, run the `V$DISPATCHER` and `V$SHARED_SERVER` queries from today's Important Views table and note how many of each are configured versus currently busy.
2. Write, in your own words (3–5 sentences), the difference between what happens when a session ends via `ALTER SYSTEM KILL SESSION` versus via `ALTER SYSTEM DISCONNECT SESSION IMMEDIATE`. If you're not sure, this is a good use of the 19c Database Administrator's Guide.
3. Sketch (paper is fine) the full path from a `sqlplus` command on a remote client to a SQL prompt for a dedicated-server connection, labeling every process/component involved. Bring it to Day 6 — you'll be extending this same diagram to cover statement execution.
