const { newDeck, addTitleSlide, addContentSlide, addRecapSlide, COLOR } = require("./theme");

const pres = newDeck("Day 5: Architecture Bootcamp III — Process Architecture & Connections");

addTitleSlide(pres, {
  dayNum: 5,
  title: "Architecture Bootcamp III — Process Architecture & Connections",
  subtitle: "Dedicated vs. shared server, the listener's real job, and the six background processes that keep an instance alive.",
});

addContentSlide(pres, 5, {
  title: "Where We Are",
  kicker: "Architecture Bootcamp III",
  diagram: { type: "chain", boxH: 1.0, small: true, highlightIndex: 2, items: [
    { label: "Day 3", caption: "Instance & Memory" },
    { label: "Day 4", caption: "Storage / Redo / Undo" },
    { label: "Day 5", caption: "Processes & Connections (today)" },
    { label: "Day 6", caption: "Statement Execution" },
  ] },
  keyTakeaway: "Part 3 of 4 in the Architecture Bootcamp — pure architecture, no tuning framing yet.",
  slideLabel: "2",
});

addContentSlide(pres, 5, {
  title: "Two Ways In",
  kicker: "Connection Architecture",
  diagram: { type: "twobox",
    leftTitle: "Dedicated Server (the default)",
    leftLines: [
      "One private OS server process per client connection",
      "PGA holds that session's state — simple, predictable",
      "Cost: memory & process-table entries at high connection counts",
    ],
    rightTitle: "Shared Server (opt-in)",
    rightLines: [
      "Dispatchers (Dnnn) queue requests from many clients",
      "A shared server pool (Snnn) pulls and executes them",
      "UGA lives in the SGA — no single process is 'yours'",
    ],
  },
  keyTakeaway: "Shared server solves a connection-count problem, not a CPU problem — most systems never touch it.",
  slideLabel: "3",
});

addContentSlide(pres, 5, {
  title: "How a Connection Becomes a Process",
  kicker: "The Connection Path",
  bullets: [
    "Dedicated path: Client → Listener matches the service → fork/exec creates a new dedicated server process",
    "Shared path: Client → Dispatcher → shared request queue in the SGA → a shared server process picks it up",
    "BEQ local connections (e.g., sqlplus / as sysdba on the DB host) bypass the listener entirely",
  ],
  diagram: { type: "chain", boxH: 1.0, small: true, items: [
    { label: "Client", caption: "sqlplus / app connects" },
    { label: "Listener", caption: "Matches service, hands off" },
    { label: "Fork / Exec", caption: "New OS process created" },
    { label: "Dedicated Server", caption: "Owns the session for its life" },
  ] },
  keyTakeaway: "Once handed off, the listener is completely out of the conversation for the rest of that session's life.",
  notes: "Emphasize the BEQ bypass explicitly: a hang on / as sysdba can never be a listener problem.",
  slideLabel: "4",
});

addContentSlide(pres, 5, {
  title: "Telling Them Apart",
  kicker: "V$SESSION and V$PROCESS",
  bullets: [
    "V$SESSION.SERVER is the one-query answer to 'dedicated or shared?'",
    "Join V$SESSION.PADDR = V$PROCESS.ADDR to map a session to its OS process",
    "V$PROCESS.SPID is the OS PID — correlate it with ps -ef at the OS level",
  ],
  diagram: { type: "table",
    header: ["SERVER value", "Meaning"],
    rows: [
      ["DEDICATED", "One private OS server process for this session (the default)"],
      ["SHARED", "Serviced via dispatcher + shared server pool; UGA lives in the SGA"],
      ["PSEUDO", "Temporarily unattached to any server process, mid-request under shared server"],
      ["POOLED", "Database Resident Connection Pooling (DRCP) — a third, related model"],
    ],
  },
  keyTakeaway: "Memorize this query — it comes up constantly in real troubleshooting.",
  slideLabel: "5",
});

addContentSlide(pres, 5, {
  title: "Meet the Background Processes I — The Cleanup Crew",
  kicker: "PMON vs. SMON",
  diagram: { type: "twobox",
    leftTitle: "PMON — Process Monitor",
    leftLines: [
      "Session-level cleanup",
      "Rolls back a dead session's uncommitted transaction",
      "Releases its locks, frees its SGA resources",
      "Restarts dead dispatchers / shared servers",
    ],
    rightTitle: "SMON — System Monitor",
    rightLines: [
      "Instance/system-level cleanup",
      "Performs instance (crash) recovery at startup",
      "Cleans up temporary segments no longer needed",
      "Coalesces free space in dictionary-managed tablespaces",
    ],
  },
  keyTakeaway: "PMON reacts to a dead session; SMON handles system-wide housekeeping and crash recovery — not the same job.",
  slideLabel: "6",
});

addContentSlide(pres, 5, {
  title: "Meet the Background Processes II — The Writers",
  kicker: "DBWn vs. LGWR",
  diagram: { type: "twobox",
    leftTitle: "DBWn — Database Writer",
    leftLines: [
      "Writes dirty buffers from the buffer cache to datafiles",
      "Lazy, asynchronous",
      "Triggered by checkpoints, a dirty-buffer threshold, or no free buffer",
    ],
    rightTitle: "LGWR — Log Writer",
    rightLines: [
      "Writes redo log buffer entries to the online redo logs",
      "Commit-synchronous — COMMIT waits for LGWR to confirm",
      "Also flushes every ~3 sec, at 1/3 full, or before DBWn writes",
    ],
  },
  keyTakeaway: "Write-ahead logging: LGWR's redo must be on disk before DBWn may write the matching dirty buffer.",
  slideLabel: "7",
});

addContentSlide(pres, 5, {
  title: "Meet the Background Processes III — Bookkeeping & Archiving",
  kicker: "CKPT vs. ARCn",
  diagram: { type: "twobox",
    leftTitle: "CKPT — Checkpoint Process",
    leftLines: [
      "Never writes a data block itself",
      "Signals DBWn to write",
      "Updates the control file and datafile headers with checkpoint info",
    ],
    rightTitle: "ARCn — Archiver",
    rightLines: [
      "Only present in ARCHIVELOG mode",
      "Copies a filled online redo log before that group is reused",
      "Makes point-in-time recovery and standby databases possible",
    ],
  },
  keyTakeaway: "CKPT records and signals; DBWn always performs the actual datafile I/O.",
  slideLabel: "8",
});

addContentSlide(pres, 5, {
  title: "Demo Recap — Kill and Observe",
  kicker: "Live Demo",
  tag: "demo",
  bullets: [
    "Tag a disposable session: DBMS_APPLICATION_INFO.SET_MODULE('DAY05_DEMO_SESSION', ...)",
    "Find it in V$SESSION filtered on MODULE — confirm SERVER = 'DEDICATED'",
    "Join to V$PROCESS on PADDR = ADDR to get its OS SPID",
    "ALTER SYSTEM KILL SESSION 'sid,serial#' IMMEDIATE — re-verify the MODULE tag immediately first",
    "Re-query V$SESSION: the row disappears once PMON finishes cleanup",
  ],
  keyTakeaway: "Only ever kill a session you created for this demo, tagged and re-verified by MODULE/PROGRAM before every kill.",
  notes: "Repeat the safety note verbally before this step: only ever run ALTER SYSTEM KILL SESSION or an OS-level kill against a session created specifically for this demo, freshly re-verified by its MODULE tag immediately beforehand.",
  slideLabel: "9",
});

addContentSlide(pres, 5, {
  title: "Demo Recap — Write Workload",
  kicker: "Live Demo",
  tag: "demo",
  bullets: [
    "Baseline V$SYSSTAT: redo size, redo entries, redo writes, physical writes, user commits",
    "Run PERF_LAB.DAY05_GENERATE_WRITE_LOAD, then capture V$SYSSTAT again",
    "Compare the deltas — direction and existence matter more than exact numbers",
    "Join V$BGPROCESS to V$PROCESS to get LGWR's and DBWn's live SPIDs",
    "Correlate those SPIDs with ps/top — LGWR is commit-driven, DBWn is lazier",
  ],
  keyTakeaway: "The write-workload numbers are environment dependent — frame this around direction of change, not absolute numbers.",
  notes: "On a shared/throttled lab VM the deltas may be much smaller than on a dedicated instructor machine.",
  slideLabel: "10",
});

addContentSlide(pres, 5, {
  title: "Real-World Scenario: \"The Connection Just Hangs\"",
  kicker: "Production Scenario",
  tag: "scenario",
  diagram: { type: "twobox",
    leftTitle: "False Lead: Service Not Registered",
    leftLines: [
      "Classic guess: ORA-12514, listener doesn't know the service",
      "But LSNRCTL SERVICES already shows PERFPDB registered and ready",
      "A missing service fails fast — it does not hang",
    ],
    rightTitle: "Root Cause: Silent Port Mismatch",
    rightLines: [
      "tnsnames.ora still points at the old PORT=1522",
      "Nothing listens there now; the firewall silently drops the attempt",
      "TCP handshake sits until timeout — the user sees it as 'it hangs'",
    ],
    leftColor: COLOR.redFalse,
    rightColor: COLOR.greenGood,
  },
  keyTakeaway: "A fast, explicit TNS error means you reached something that said no; a silent hang means you never reached anything at all.",
  notes: "This is fully diagnosable with Day 5's toolkit alone — nothing here required a wait-event or session-tracing investigation.",
  slideLabel: "11",
});

addRecapSlide(pres, 5, {
  bullets: [
    "V$SESSION.SERVER tells you dedicated, shared, pseudo, or pooled — in one query.",
    "The listener's job ends at connection handoff; BEQ (local) connections never touch it at all.",
    "PMON cleans up dead sessions; SMON cleans up the instance — different scope, different triggers.",
    "DBWn writes lazily; LGWR writes synchronously at commit — the contrast to remember above all others.",
    "CKPT signals and records; DBWn always performs the actual datafile I/O.",
  ],
  homework: "1) Check whether your instance uses shared server (DISPATCHERS) and query V$DISPATCHER/V$SHARED_SERVER. 2) In your own words, contrast ALTER SYSTEM KILL SESSION vs. DISCONNECT SESSION IMMEDIATE. 3) Sketch the full client-to-SQL-prompt path for a dedicated-server connection — bring it to Day 6.",
  nextUp: "Tomorrow: you now know every piece — we watch them all work together on one SQL statement.",
});

pres.writeFile({ fileName: "/home/claude/oracle-performance-course/day05/day05-slides.pptx" }).then(() => console.log("day05 done"));
