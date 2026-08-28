const { newDeck, addTitleSlide, addContentSlide, addRecapSlide, COLOR } = require("./theme");

const pres = newDeck("Day 3: Architecture Bootcamp I");

addTitleSlide(pres, {
  dayNum: 3,
  title: "Architecture Bootcamp I — Instance vs. Database, Memory at a Glance",
  subtitle: "What an instance is, what a database is, and why they are not the same thing.",
});

addContentSlide(pres, 3, {
  title: "Learning Objectives",
  kicker: "By the end of this session",
  bullets: [
    "State the precise definitions of “instance” and “database” and explain why they are separate concepts, not synonyms.",
    "Name the memory structures that make up the SGA and the PGA, and explain what each one is for.",
    "Read V$INSTANCE, V$DATABASE, V$PROCESS, V$BGPROCESS, V$SGA, and V$SGAINFO and map every concept to a real row or column.",
    "Explain the conceptual difference between a background process and a foreground (server) process, and name at least four mandatory background processes.",
    "Explain, at a high level, how the CDB/PDB (multitenant) architecture fits into the instance/database picture.",
    "Diagnose, from architecture knowledge alone, why a connection attempt to a specific PDB can fail even though the instance is up and healthy.",
  ],
  keyTakeaway: "This is the foundation the next three Architecture Bootcamp days build on.",
  notes: "Read these fairly quickly — the real teaching is in the theory and demo that follow, not in dwelling on this list.",
  slideLabel: "2",
});

addContentSlide(pres, 3, {
  title: "The Myth",
  kicker: "Setting Up The Rest Of This Deck",
  diagram: { type: "quote", text: "“An instance and a database are NOT the same thing.”" },
  keyTakeaway: "Say “the database is down” and “connect to the database” enough times and the two blur together — today we make the line exact.",
  notes: "No explanation yet — this is a one-line teaser. Let it sit for a second before moving to the next slide.",
  slideLabel: "3",
});

addContentSlide(pres, 3, {
  title: "Instance vs. Database",
  kicker: "Two Genuinely Separate Things",
  diagram: {
    type: "twobox",
    leftTitle: "INSTANCE  (RAM)",
    leftLines: [
      "SGA — shared memory, allocated at startup",
      "Background processes: PMON, SMON, DBWn, LGWR, CKPT, ARCn",
      "Exists only in RAM / OS process table",
      "Created by STARTUP NOMOUNT",
    ],
    rightTitle: "DATABASE  (DISK)",
    rightLines: [
      "Datafiles — table and index data",
      "Control file(s) — physical structure and identity",
      "Online redo log files — record of changes",
      "Inert: just organized bytes until an instance mounts it",
    ],
    leftColor: COLOR.deepBlue,
    rightColor: COLOR.midnight,
  },
  keyTakeaway: "MOUNT is the arrow between them: the instance associates itself with one database's physical structure.",
  notes: "Point at the left box first — an instance is memory plus processes, full stop. Then the right box — a database is just files on disk, doing nothing by itself.",
  slideLabel: "4",
});

addContentSlide(pres, 3, {
  title: "The STARTUP Sequence — Cleanest Proof They're Separate",
  kicker: "NOMOUNT → MOUNT → OPEN",
  diagram: {
    type: "chain",
    items: [
      { label: "NOMOUNT", caption: "Instance: YES  |  Database: NO — SGA allocated, no database known yet" },
      { label: "MOUNT", caption: "Instance: YES  |  Database: YES — control file read, datafiles not yet open" },
      { label: "OPEN", caption: "Instance: YES  |  Database: YES — datafiles open, fully usable" },
    ],
    boxH: 0.85,
  },
  keyTakeaway: "Production is almost always found already OPEN — which is exactly why NOMOUNT and MOUNT get forgotten.",
  notes: "This is the single most convincing five minutes of the session if a spare sandbox is available: SHUTDOWN IMMEDIATE, STARTUP NOMOUNT, then a V$DATABASE query returning no rows.",
  slideLabel: "5",
});

addContentSlide(pres, 3, {
  title: "SGA At A Glance",
  kicker: "Shared, Instance-Wide Memory",
  diagram: {
    type: "chain",
    small: true,
    items: [
      { label: "Buffer Cache", caption: "Cached data blocks" },
      { label: "Shared Pool", caption: "Library cache + dictionary cache" },
      { label: "Redo Log Buffer", caption: "Pending redo change vectors" },
      { label: "Large Pool", caption: "RMAN, parallel execution" },
      { label: "Java Pool", caption: "Java VM memory" },
      { label: "Streams Pool", caption: "Streams / replication" },
    ],
    boxH: 1.1,
  },
  keyTakeaway: "One region, allocated once at instance startup, readable and writable by every session — not being sized or tuned today.",
  notes: "Name what each nonzero component is for as you point to it; this ties directly back to Theory and previews V$SGAINFO in the live demo.",
  slideLabel: "6",
});

addContentSlide(pres, 3, {
  title: "PGA At A Glance",
  kicker: "Private, Per-Process Memory",
  bullets: [
    "Each server process gets its own PGA — no other session can read it.",
    "Holds sort operations, hash joins, bitmap merges.",
    "Holds session-specific cursor state and PL/SQL variables.",
    "Contrast with slide 6: one shared box vs. many small private boxes.",
  ],
  diagram: {
    type: "chain",
    small: true,
    items: [
      { label: "PGA (private)", caption: "Session 1" },
      { label: "PGA (private)", caption: "Session 2" },
      { label: "PGA (private)", caption: "Session 3" },
      { label: "PGA (private)", caption: "Session N" },
    ],
    boxH: 1.1,
  },
  keyTakeaway: "Raising PGA_AGGREGATE_TARGET does not touch buffer cache behavior, and vice versa — they are different pools.",
  notes: "Explicitly name the misconception: SGA and PGA are both “Oracle memory” but are not the same kind of memory.",
  slideLabel: "7",
});

addContentSlide(pres, 3, {
  title: "SGA vs. PGA",
  kicker: "Comparison",
  diagram: {
    type: "table",
    header: ["SGA (shared)", "PGA (private)"],
    rows: [
      ["Shared across the instance", "Private to one server process"],
      ["Instance-wide scope", "Per-process scope"],
      ["Allocated once at instance startup", "Allocated per connection"],
      ["Visible to all sessions", "Visible only to that one process"],
      ["Buffer cache, shared pool, redo buffer, large/Java/streams pools", "Sort/hash work areas, cursor state, PL/SQL variables"],
    ],
    colW: [6.05, 6.05],
  },
  keyTakeaway: "Confusing these two causes real misdiagnosis later in this course — keep the boundary exact.",
  notes: "Walk down the rows left-to-right, pairing each SGA row with its PGA counterpart.",
  slideLabel: "8",
});

addContentSlide(pres, 3, {
  title: "Background vs. Foreground Processes",
  kicker: "Instance-Scoped vs. Session-Scoped",
  diagram: {
    type: "twobox",
    leftTitle: "BACKGROUND",
    leftLines: [
      "Start when the instance starts",
      "Few, fixed — one per functional role",
      "PMON, SMON, DBWn, LGWR, CKPT, ARCn",
      "Belong to the instance, not any session",
    ],
    rightTitle: "FOREGROUND (SERVER)",
    rightLines: [
      "One started per client connection",
      "Scale with connection count, not fixed",
      "Execute that session's SQL against the SGA",
      "Belong to sessions, not the instance",
    ],
    leftColor: COLOR.deepBlue,
    rightColor: COLOR.teal,
  },
  keyTakeaway: "Background processes: instance starts → few and fixed. Foreground processes: client connects → scales with connections.",
  notes: "PMON cleans up failed sessions, SMON handles instance recovery, DBWn writes dirty buffers, LGWR writes redo, CKPT updates checkpoint info, ARCn archives redo logs.",
  slideLabel: "9",
});

addContentSlide(pres, 3, {
  title: "CDB / PDB Architecture",
  kicker: "One Instance, One Physical Database, Many Containers",
  bullets: [
    "One instance mounts one physical database — the CDB (container database).",
    "The CDB contains CDB$ROOT, the PDB$SEED template, and one or more application PDBs.",
    "PDB$SEED is read-only and never meant for application work.",
    "The instance's SGA and background processes are shared by every container — not duplicated per PDB.",
  ],
  diagram: {
    type: "chain",
    small: true,
    items: [
      { label: "CDB$ROOT", caption: "Root container" },
      { label: "PDB$SEED", caption: "Read-only template, never for app work" },
      { label: "PERFPDB", caption: "Application PDB — READ WRITE" },
    ],
    boxH: 1.0,
  },
  keyTakeaway: "Two rows in V$PDBS doesn't mean two application databases — one is very likely PDB$SEED.",
  notes: "One instance box, one shared SGA/background-process set, all three containers hanging off it — draw this relationship verbally if not on the slide.",
  slideLabel: "10",
});

addContentSlide(pres, 3, {
  title: "Live Demo Recap — View-to-Concept Map",
  kicker: "Live Demo",
  tag: "demo",
  diagram: {
    type: "table",
    header: ["If you want to know...", "Query..."],
    rows: [
      ["Is the instance itself healthy?", "V$INSTANCE"],
      ["What database is mounted, and is this a CDB?", "V$DATABASE"],
      ["What containers (PDBs) exist and are they open?", "V$PDBS / V$CONTAINERS"],
      ["What's in shared memory right now?", "V$SGA / V$SGAINFO"],
      ["What's in this session's private memory?", "V$PGASTAT, V$PROCESS.PGA_*"],
      ["What is the instance itself doing?", "V$BGPROCESS"],
      ["What is my session's own server process doing?", "V$PROCESS joined to V$SESSION, BACKGROUND IS NULL"],
    ],
    colW: [7.1, 5.0],
  },
  keyTakeaway: "Screenshot-worthy: this table is exactly the orientation habit from today's Real-World Scenario.",
  notes: "This is the Student Notes cheat-sheet table shown as a clean reference — students should photograph or screenshot this slide.",
  slideLabel: "11",
});

addRecapSlide(pres, 3, {
  title: "Recap & Homework",
  bullets: [
    "An instance and a database are NOT the same thing — NOMOUNT proves it.",
    "SGA is shared and instance-wide; PGA is private and per-process.",
    "Background processes belong to the instance; foreground (server) processes belong to sessions.",
  ],
  homework: "Run the full nine-query Hands-on Lab sequence independently and write a half-page architecture summary; explain in your own words why an instance can exist without a mounted database; draw the instance-vs-database two-box diagram from memory (4+ background processes, 4+ SGA components); preview Day 4 by querying DBA_DATA_FILES and DBA_TABLESPACES against PERF_LAB.",
  nextUp: "Tomorrow: Day 4 picks up exactly where “database = files on disk” left off — tablespaces, segments, extents, and blocks.",
});

pres.writeFile({ fileName: "/home/claude/oracle-performance-course/day03/day03-slides.pptx" }).then(() => console.log("day03 done"));
