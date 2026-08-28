const { newDeck, addTitleSlide, addContentSlide, addRecapSlide, COLOR } = require("./theme");

const pres = newDeck("Day 2: Systematic Investigation — From Symptom to SQL");

addTitleSlide(pres, {
  dayNum: 2,
  title: "Systematic Investigation — From Symptom to SQL",
  subtitle: "Yesterday you watched it happen. Today you drive.",
});

addContentSlide(pres, 2, {
  title: "Today's Objective",
  kicker: "One Goal, Start to Finish",
  diagram: { type: "chain", small: true, boxH: 1.0, items: [
    { label: "ACTIVE SESSIONS" }, { label: "RULE OUT FALSE LEADS" }, { label: "EXPENSIVE SQL" },
    { label: "WAIT EVENT" }, { label: "EXECUTION PLAN" }, { label: "HYPOTHESIS" },
    { label: "PROVE" }, { label: "FIX" }, { label: "VALIDATE" },
  ] },
  keyTakeaway: "Today's single goal: run this exact chain yourself, end to end, on an incident you haven't seen before.",
  notes: "This diagram reappears at the top of every remaining diagnostic day in the course — get students used to it now.",
  slideLabel: "2",
});

addContentSlide(pres, 2, {
  title: "Day 1 Recap (5 Minutes)",
  kicker: "Vocabulary You'll Need Today",
  bullets: [
    "DB Time — total time sessions spent on CPU or actively waiting, summed across all sessions; the single number for \"how much work is the database doing.\"",
    "Active session — consuming CPU or waiting on a non-idle resource right now; connected-but-idle does not count.",
    "CPU vs. wait — every unit of DB Time is CPU time or wait time. Today's incident is wait-bound, specifically I/O-wait-bound — you'll prove that, not assume it.",
  ],
  keyTakeaway: "If the room is shaky here, that's a signal to slow down today's pacing — not to re-teach Day 1.",
  notes: "Keep to five minutes flat, watch the clock.",
  slideLabel: "3",
});

addContentSlide(pres, 2, {
  title: "Today's Incident, in Business Terms",
  kicker: "Production Scenario",
  tag: "scenario",
  bullets: [
    "A recall notice just went out on one product.",
    "Customer service is telling every caller \"let me check if your order had that item\" — all at the same time.",
    "The order-lookup screen that normally takes a few seconds now takes many, many seconds, and the support queue is backing up.",
  ],
  diagram: { type: "twobox",
    leftTitle: "One CSR, Occasional Use", leftLines: [
      "Full scan of ORDER_ITEMS (20M rows)",
      "Expensive, but tolerable — a few seconds, rarely run",
    ],
    rightTitle: "25 CSRs, Same Minute", rightLines: [
      "Same full scan, run 25× concurrently",
      "Shared I/O path can't absorb it — the queue backs up",
    ],
    leftColor: COLOR.greenGood, rightColor: COLOR.redFalse,
  },
  keyTakeaway: "Nothing was broken — a concurrency spike turned an always-expensive access path into a production incident.",
  notes: "Let the business framing land before showing any SQL.",
  slideLabel: "4",
});

addContentSlide(pres, 2, {
  title: "Baseline & Break It",
  kicker: "Live Demo",
  tag: "demo",
  bullets: [
    "Baseline: run sp_csr_order_lookup_by_product once, alone — capture executions, buffer gets, disk reads, elapsed time.",
    "Break it: launch the simulated recall-notice spike — 25 concurrent CSR sessions, same lookup, about 90 seconds.",
    "EXEC perf_lab.sp_generate_csr_load_product(p_sessions => 25, p_duration_seconds => 90, p_product_id => 4471);",
  ],
  keyTakeaway: "Document the \"before\" now — you'll need real numbers to prove the fix worked later.",
  notes: "Narrate what you expect to see before running it, so the class has a prediction to check against.",
  slideLabel: "5",
});

addContentSlide(pres, 2, {
  title: "Observe",
  kicker: "Live Demo",
  tag: "demo",
  bullets: [
    "Before touching anything else: is anything actually active right now, and on what?",
    "COUNT(*) FROM v$session WHERE status='ACTIVE' AND type='USER'",
    "GROUP BY wait_class — the room sees dozens of active sessions, dominated by one wait class.",
  ],
  diagram: { type: "table",
    header: ["Wait Class", "Active Sessions"],
    rows: [
      ["User I/O", "Dominant — real DB work"],
      ["CPU", "Small minority"],
      ["SQL*Net (idle)", "Negligible"],
    ],
  },
  keyTakeaway: "Dozens of active sessions, one dominant wait class — confirmation something's different, not yet a diagnosis.",
  notes: "Pause here — ask the room \"what's your first hypothesis?\" before continuing.",
  slideLabel: "6",
});

addContentSlide(pres, 2, {
  title: "False Lead #1 — Locking",
  kicker: "Live Demo",
  tag: "demo",
  bullets: [
    "The instinct in the incident channel: \"25 sessions stuck on the same screen — something must be locked.\"",
    "Check V$SESSION.BLOCKING_SESSION across every active session — every one comes back NULL.",
    "Check V$LOCK for TX/TM contention — no blocking rows found.",
    "Ruled out with evidence: each session is doing its own independent, expensive work — not queued behind another session.",
  ],
  keyTakeaway: "This is the natural first guess, and it's wrong — here's how we know.",
  notes: "Explicitly say: \"this is the natural first guess, and it's wrong — here's how we know.\"",
  slideLabel: "7",
});

addContentSlide(pres, 2, {
  title: "False Lead #2 — Network",
  kicker: "Live Demo",
  tag: "demo",
  bullets: [
    "The quieter guess from the app team: \"is this a network blip? Users say the screen just spins.\"",
    "Check the wait class breakdown again — the dominant wait is User I/O, not idle SQL*Net message from client.",
    "The database is genuinely busy doing real work — it is not waiting on the network.",
  ],
  keyTakeaway: "Ruling something out with evidence is real investigative progress, not wasted time.",
  notes: "Document this finding too — it closes a second reflexive guess before the real cause is found.",
  slideLabel: "8",
});

addContentSlide(pres, 2, {
  title: "Finding the SQL, the Wait, and the Plan",
  kicker: "Live Demo — Chain Steps D–H",
  tag: "demo",
  bullets: [
    "Step D: join active sessions to V$SQL — one SQL_ID explains nearly all of the active-session count.",
    "Step E: V$SQLAREA shows tens of thousands of buffer gets per execution — the full-scan signature.",
    "Steps F–G: V$SESSION_WAIT and V$ACTIVE_SESSION_HISTORY agree — db file scattered read / direct path read.",
    "Step H: DBMS_XPLAN.DISPLAY_CURSOR (BASIC) confirms TABLE ACCESS FULL on ORDER_ITEMS.",
  ],
  diagram: { type: "chain", items: [
    { label: "SQL_ID", caption: "One statement explains nearly all active sessions" },
    { label: "WAIT EVENT", caption: "db file scattered read / direct path read" },
    { label: "PLAN OPERATION", caption: "TABLE ACCESS FULL on ORDER_ITEMS" },
  ] },
  keyTakeaway: "This is the heart of the chain — one SQL_ID, one wait event, one plan operation, each proven in turn.",
  notes: "This is the heart of the day; take it slowly, one query at a time, and name what each result proves.",
  slideLabel: "9",
});

addContentSlide(pres, 2, {
  title: "Prove, Fix, Validate",
  kicker: "Live Demo",
  tag: "demo",
  bullets: [
    "Prove: EXPLAIN PLAN with an INDEX hint — Oracle still shows a full scan. No index exists to use; that is the proof.",
    "Fix: CREATE INDEX ix_order_items_product_id ON order_items(product_id) ONLINE, then GATHER_INDEX_STATS.",
    "Validate: re-run the baseline and the 25-session spike, and compare against the Step 1/3 numbers.",
  ],
  diagram: { type: "twobox",
    leftTitle: "Before", leftLines: [
      "TABLE ACCESS FULL on ORDER_ITEMS",
      "Tens of thousands of buffer gets/exec",
      "Sustained User I/O wait under load",
    ],
    rightTitle: "After", rightLines: [
      "INDEX RANGE SCAN on the new index",
      "Buffer gets drop ~2–3 orders of magnitude",
      "No sustained User I/O population",
    ],
    leftColor: COLOR.redFalse, rightColor: COLOR.greenGood,
  },
  keyTakeaway: "\"Prove before you change\" is not optional ceremony.",
  notes: "Verify the plan actually changed before declaring victory — that's the validate step, not a formality.",
  slideLabel: "10",
});

addContentSlide(pres, 2, {
  title: "Hands-On Lab Handoff",
  kicker: "Production Scenario",
  tag: "scenario",
  bullets: [
    "New incident: the Payment Reconciliation screen — a \"search by payment method\" filter on PAYMENTS.PAYMENT_METHOD.",
    "Shipped as \"just an internal report, nobody will run it much\" — now run concurrently every morning at month-end close.",
    "Run the entire chain yourself: baseline, break it, observe, investigate, prove, fix, validate, reset.",
    "EXEC perf_lab.sp_generate_csr_load_payment(p_sessions => 20, p_duration_seconds => 90, p_payment_method => 'CREDIT_CARD');",
  ],
  keyTakeaway: "\"I'm not driving anymore — you are.\"",
  notes: "This is the actual handoff moment — say clearly \"I'm not driving anymore, you are\" and stop presenting.",
  slideLabel: "11",
});

addRecapSlide(pres, 2, {
  title: "Wrap-Up & Bridge to Day 3",
  bullets: [
    "The chain: active sessions → rule out false leads → expensive SQL → wait event → execution plan → hypothesis → prove → fix → validate.",
    "A false lead ruled out with evidence is real progress, not wasted time — locking and network were today's two.",
    "An access path that was fine can become an incident purely from a concurrency change — no code deploy, no corruption needed.",
  ],
  homework: "Write a one-page incident report for today's demo in the Real-World Scenario format, and complete the Payment Reconciliation lab fully — including your own before/after validation numbers.",
  nextUp: "Days 3–6 build the architecture knowledge underneath everything you used today — same chain, deeper tools each time.",
});

pres.writeFile({ fileName: "/home/claude/oracle-performance-course/day02/day02-slides.pptx" }).then(() => console.log("day02 done"));
