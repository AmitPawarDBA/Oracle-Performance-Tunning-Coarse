const { newDeck, addTitleSlide, addContentSlide, addRecapSlide, COLOR } = require("./theme");

const pres = newDeck("Day 4: Architecture Bootcamp II, Storage");

addTitleSlide(pres, {
  dayNum: 4,
  title: "Architecture Bootcamp II: Storage",
  subtitle: "Datafiles, tablespaces, segments, redo & undo — how a row actually lives on disk.",
});

addContentSlide(pres, 4, {
  title: "Where We Are",
  kicker: "Course Bridge",
  bullets: [
    "Day 3 gave you the instance and memory architecture — SGA, PGA, background processes.",
    "Today (Day 4): the physical and logical storage stack underneath every table you've ever queried.",
    "Zero performance-tuning framing today — this is core architecture every DBA needs, tuning or not.",
    "Tomorrow (Day 5): which process actually performs the writes described today — LGWR, DBWn, and friends.",
  ],
  keyTakeaway: "Instance & memory (Day 3) → storage (Day 4) → processes (Day 5) — one continuous chain.",
  notes: "Keep this brief — a one-line bridge each, not a re-teach of Day 3.",
  slideLabel: "2",
});

addContentSlide(pres, 4, {
  title: "The Storage Hierarchy — Bottom Up",
  kicker: "Block → Extent → Segment → Tablespace → Datafile",
  diagram: {
    type: "chain",
    boxH: 1.05,
    items: [
      { label: "BLOCK", caption: "~8KB; smallest unit of I/O; rows live here" },
      { label: "EXTENT", caption: "contiguous blocks, allocated together" },
      { label: "SEGMENT", caption: "all extents for one object (DBA_SEGMENTS)" },
      { label: "TABLESPACE", caption: "logical umbrella; unit of quota & backup" },
      { label: "DATAFILE", caption: "the actual OS file — where the bytes live" },
    ],
  },
  keyTakeaway: "Grouped into, grouped into, grouped into, grouped into — smallest to largest.",
  notes: "Blocks group into extents, extents group into segments, segments live in a tablespace, a tablespace maps to datafiles. Read the arrows aloud as 'grouped into'.",
  slideLabel: "3",
});

addContentSlide(pres, 4, {
  title: "The Storage Hierarchy — Top Down",
  kicker: "Same Hierarchy, Other Direction",
  bullets: [
    "Start from a datafile — it belongs to exactly one tablespace.",
    "A tablespace maps to ONE OR MORE datafiles.",
    "A segment's extents CAN span multiple datafiles in that tablespace.",
    "Bottom-up and top-down meet in the middle — same hierarchy, both directions.",
  ],
  diagram: {
    type: "chain",
    small: true,
    boxH: 1.05,
    items: [
      { label: "DATAFILE", caption: "the OS file" },
      { label: "TABLESPACE", caption: "one or more datafiles" },
      { label: "SEGMENT", caption: "spread across the files" },
      { label: "EXTENT", caption: "one datafile each" },
      { label: "BLOCK", caption: "where rows live" },
    ],
  },
  keyTakeaway: "Made of, made of, made of, made of — largest to smallest, same hierarchy.",
  notes: "Students who only learn bottom-up can trace a row but not reason about capacity; students who only learn top-down understand allocation but can't find a row. Teach both.",
  slideLabel: "4",
});

addContentSlide(pres, 4, {
  title: "ROWID Anatomy",
  kicker: "A Physical Address, Not an Opaque ID",
  bullets: [
    "A ROWID is literally an address — not a generated surrogate value.",
    "DBMS_ROWID is how you read that address, piece by piece.",
    "Same ROWID, four functions, four physical facts about one row.",
  ],
  diagram: {
    type: "chain",
    items: [
      { label: "OBJECT", caption: "ROWID_OBJECT" },
      { label: "FILE", caption: "ROWID_RELATIVE_FNO / ROWID_TO_ABSOLUTE_FNO" },
      { label: "BLOCK", caption: "ROWID_BLOCK_NUMBER" },
      { label: "ROW", caption: "ROWID_ROW_NUMBER" },
    ],
  },
  keyTakeaway: "A ROWID is not an opaque ID — it's an address, and DBMS_ROWID reads it.",
  notes: "Warn about the ROWID-vs-primary-key trap: TRUNCATE changes the data object id and can invalidate ROWIDs written down earlier; a plain DELETE does not.",
  slideLabel: "5",
});

addContentSlide(pres, 4, {
  title: "Live Demo Checkpoint 1",
  kicker: "Live Demo — Row to Physical File",
  tag: "demo",
  bullets: [
    "Pull one row's ROWID from D4_DEMO_ORDERS with a plain SELECT.",
    "Decode it with DBMS_ROWID against the theory diagram, piece by piece.",
    "Join the decoded file + block against DBA_EXTENTS to find the owning extent.",
    "Confirm the physical OS file name and tablespace via DBA_DATA_FILES.",
  ],
  diagram: {
    type: "chain",
    small: true,
    items: [
      { label: "ONE ROW", caption: "SELECT ROWID" },
      { label: "DECODED ROWID", caption: "DBMS_ROWID" },
      { label: "DBA_EXTENTS", caption: "owning extent + segment" },
      { label: "DBA_DATA_FILES", caption: "the OS file" },
    ],
  },
  keyTakeaway: "Bottom-up and top-down meet in the middle — this trace proves it live.",
  notes: "Full SQL for every step is in demo.sql. This is the same chain the lab has each student repeat independently on a different row.",
  slideLabel: "6",
});

addContentSlide(pres, 4, {
  title: "Why Redo Exists",
  kicker: "Durability",
  bullets: [
    "Oracle buffers changed blocks in memory — it does NOT write them to disk on every change.",
    "Every change generates a redo change vector: a compact record of 'what changed'.",
    "At COMMIT, LGWR flushes the log buffer to the online redo log — synchronously.",
    "The changed data block itself reaches its datafile LATER, asynchronously, via DBWn.",
  ],
  diagram: {
    type: "chain",
    small: true,
    boxH: 1.05,
    items: [
      { label: "SESSION CHANGE", caption: "change vector generated" },
      { label: "LOG BUFFER", caption: "held in memory" },
      { label: "LGWR (at COMMIT)", caption: "synchronous flush" },
      { label: "ONLINE REDO LOG", caption: "durably on disk" },
    ],
  },
  keyTakeaway: "Durability — nothing committed is ever lost.",
  notes: "If the instance crashes a second after commit, the data block may still only be in memory — but the redo is already on disk, and recovery replays it.",
  slideLabel: "7",
});

addContentSlide(pres, 4, {
  title: "Redo Log Lifecycle",
  kicker: "CURRENT → ACTIVE → INACTIVE",
  bullets: [
    "Redo logs are organized into numbered groups.",
    "Each group has one or more mirrored MEMBERS for safety.",
    "LGWR writes only to whichever group is currently CURRENT.",
    "A full CURRENT group triggers a log switch to the next group.",
  ],
  diagram: {
    type: "chain",
    small: true,
    boxH: 1.05,
    items: [
      { label: "CURRENT", caption: "LGWR writing here now" },
      { label: "ACTIVE", caption: "log switch just happened; checkpoint pending" },
      { label: "INACTIVE", caption: "checkpoint complete — safe to reuse" },
    ],
  },
  keyTakeaway: "In ARCHIVELOG mode, a group is also archived before it's reused.",
  notes: "V$LOG shows STATUS for every group; V$LOGFILE shows the physical member files behind each one.",
  slideLabel: "8",
});

addContentSlide(pres, 4, {
  title: "Why Undo Exists — Job 1: Rollback",
  kicker: "The One Everyone Learns First",
  bullets: [
    "Before Oracle changes a block, it first writes the block's pre-change image to undo.",
    "That pre-change image is what makes ROLLBACK possible.",
    "Every failed statement becomes automatically and completely reversible — no application code needed.",
    "This is job one — and it's exactly where the misconception starts.",
  ],
  diagram: {
    type: "chain",
    boxH: 1.05,
    items: [
      { label: "BEFORE IMAGE", caption: "written first, into undo" },
      { label: "BLOCK CHANGED", caption: "new value, in the buffer cache" },
      { label: "ROLLBACK REAPPLIES UNDO", caption: "restores pre-transaction state" },
    ],
  },
  keyTakeaway: "\"Undo is just for rollback\" — the trap most beginners fall into next.",
  notes: "This is job one, and it's the one most beginners learn first — which is precisely why it becomes a trap.",
  slideLabel: "9",
});

addContentSlide(pres, 4, {
  title: "Why Undo Exists — Job 2: Read Consistency",
  kicker: "The Day's Single Most Important Slide",
  diagram: {
    type: "chain",
    small: true,
    boxH: 1.2,
    items: [
      { label: "SESSION A: QUERY STARTS", caption: "snapshot SCN noted — the query's fixed point in time" },
      { label: "SESSION B: COMMITS", caption: "changes + commits the same block, later on the timeline" },
      { label: "SESSION A: STILL READING", caption: "reaches that block after B's commit" },
      { label: "ORACLE DETECTS THE CHANGE", caption: "block's SCN is newer than the query's snapshot SCN" },
      { label: "UNDO RECONSTRUCTS OLD VALUE", caption: "Session A still sees its snapshot's original value" },
    ],
  },
  keyTakeaway: "Every query gets this guarantee automatically — whether or not anyone ever rolls back anything.",
  notes: "The single clearest disproof of 'undo is only for rollback'. This genuinely needs a second session to land — if running solo, narrate it step by step against demo.sql and do not skip it.",
  slideLabel: "10",
});

addContentSlide(pres, 4, {
  title: "Two Misconceptions, Killed",
  kicker: "Slow Down Here",
  diagram: {
    type: "twobox",
    leftTitle: "❌ \"Undo is just for rollback\"",
    leftLines: [
      "FALSE.",
      "Job 2 is read consistency — every query gets a stable snapshot.",
      "Applies even when nobody ever rolls back anything.",
    ],
    rightTitle: "❌ \"Redo and undo are the same thing\"",
    rightLines: [
      "FALSE.",
      "Redo is forward-looking: replay on crash.",
      "Undo is backward-looking: reverse or reconstruct.",
      "Writing undo itself generates redo, on top of the redo protecting the data change.",
    ],
    leftColor: COLOR.redFalse,
    rightColor: COLOR.redFalse,
  },
  keyTakeaway: "The highest-value five minutes of the whole session — don't let this rush by.",
  notes: "Redo protects durability. Undo protects reversibility and consistency. Related — undo writes generate redo too — but they solve different problems.",
  slideLabel: "11",
});

addRecapSlide(pres, 4, {
  title: "Recap & Bridge to Day 5",
  bullets: [
    "Storage hierarchy, both directions: block ↔ extent ↔ segment ↔ tablespace ↔ datafile.",
    "A ROWID is a physical address — DBMS_ROWID decodes it into object, file, block, row.",
    "Redo protects durability: nothing committed is ever lost, even on a crash.",
    "Undo protects reversibility (rollback) AND read consistency — every query's stable snapshot.",
    "COMMIT forces redo to disk synchronously, not the data block — that asymmetry is why commits are fast.",
  ],
  homework: "Trace a PERF_LAB.CUSTOMERS row to its physical block/file/extent; explain in your own words why a crash can lose an uncommitted transaction but never a committed one; and check V$LOG/V$LOGFILE on your lab instance for group and member counts.",
  nextUp: "Today you saw what changes and where. Tomorrow: which process actually does the writing — Day 5, process architecture (LGWR, DBWn, and the rest).",
});

pres.writeFile({ fileName: "/home/claude/oracle-performance-course/day04/day04-slides.pptx" }).then(() => console.log("day04 done"));
