const { newDeck, addTitleSlide, addContentSlide, addRecapSlide, COLOR } = require("./theme");

const pres = newDeck("Day 1: Welcome & The Hook");

addTitleSlide(pres, {
  dayNum: 1,
  title: "Welcome & The Hook",
  subtitle: "This course proves itself in the first hour.",
});

addContentSlide(pres, 1, {
  title: "About Your Instructor",
  kicker: "Introduction",
  bullets: [
    "Name & years as a working Oracle DBA: _____________________",
    "One or two production incidents you solved (industry/scale, not confidential specifics): _____________________",
    "The kind of environment you've worked in most — OLTP / reporting / mixed / regulated industry: _____________________",
    "Why this course is evidence-first, not slide-first, in your own words: _____________________",
    "(Optional) One thing you still find genuinely hard or interesting about performance work: _____________________",
  ],
  keyTakeaway: "“I've solved real production incidents; this course is built the way I actually investigate — evidence-first.”",
  notes: "Keep this under 5 minutes — set a visible timer if needed. This is a template for Amit to fill in before teaching, not a script to read verbatim.",
  slideLabel: "2",
});

addContentSlide(pres, 1, {
  title: "The Course Philosophy — One Line",
  kicker: "Everything else builds on this",
  diagram: { type: "chain", items: [
    { label: "MEASURE" }, { label: "OBSERVE" }, { label: "HYPOTHESIZE" },
    { label: "PROVE" }, { label: "CHANGE" }, { label: "VALIDATE" },
  ], boxH: 1.0, small: true },
  keyTakeaway: "This loop repeats every single day of the course.",
  notes: "Say it, don't over-explain it yet — the Hook is about to demonstrate it in action.",
  slideLabel: "3",
});

addContentSlide(pres, 1, {
  title: "Where This Course Is Going",
  kicker: "Course roadmap, one screen",
  diagram: { type: "chain", small: true, boxH: 1.0, items: [
    { label: "1. HOOK", caption: "Prove the method works (Days 1–2)" },
    { label: "2. ARCHITECTURE", caption: "Know what you're looking at (Days 3–9)" },
    { label: "3. DIAGNOSTICS", caption: "V$ views, waits, OS metrics (10–11)" },
    { label: "4. EVIDENCE TOOLKIT", caption: "AWR/ASH, daily-use toolkit (12–18)" },
    { label: "5. SQL / PLANS / OPTIMIZER", caption: "Why that plan? (19–27)" },
    { label: "6. MEMORY/I-O/CONCURRENCY", caption: "Deep resource stages (28–33)" },
    { label: "CAPSTONE", caption: "Everything at once, no help (34)" },
  ] },
  keyTakeaway: "Here's the whole shape of where we're going, before we go anywhere.",
  notes: "Name roughly which day-range each stage covers, but don't read the full 34-row table — that's not this slide's job.",
  slideLabel: "4",
});

addContentSlide(pres, 1, {
  title: "The 45-Minute Mystery",
  kicker: "Production Scenario",
  tag: "scenario",
  bullets: [
    "A batch reconciliation job that finishes in 4 minutes took 45 minutes last night.",
    "Finance wants to know why the daily numbers were late.",
    "Nothing was “changed” on purpose — or so everyone believes.",
  ],
  diagram: { type: "stat", leftStat: "4 min", leftLabel: "Every prior run", rightStat: "45 min", rightLabel: "Last night's run" },
  keyTakeaway: "This is a real, business-visible incident shape — not an academic exercise.",
  notes: "Pause here — let the stakes land before opening any tool.",
  slideLabel: "5",
});

addContentSlide(pres, 1, {
  title: "Baseline, Then Reproduce It Live",
  kicker: "Live Demo",
  tag: "demo",
  bullets: [
    "Query RECON_RUN_LOG — every prior run's duration, laid out as history.",
    "Kick off today's run via DBMS_SCHEDULER — it's now running in the background.",
    "We investigate while it runs, exactly like a real incident.",
  ],
  keyTakeaway: "Every prior run looked like this — let's watch today's run happen in real time.",
  notes: "Narrate that the job is now running in the background while we investigate — don't wait for it to finish before starting.",
  slideLabel: "6",
});

addContentSlide(pres, 1, {
  title: "Reading the Picture",
  kicker: "Live Demo — ASH Visualization Tool",
  tag: "demo",
  diagram: { type: "twobox", leftTitle: "Every Prior Run (baseline)", leftLines: ["Clean green CPU band", "~4 minutes, done"], rightTitle: "Today, Live", rightLines: ["Growing red wait-event band", "Still running past 40 minutes"], leftColor: COLOR.greenGood, rightColor: COLOR.redFalse },
  keyTakeaway: "We know something changed, and roughly when, before reading a single line of SQL.",
  notes: "Stop talking for a few seconds; let the room look at the picture.",
  slideLabel: "7",
});

addContentSlide(pres, 1, {
  title: "Ruling Out False Leads",
  kicker: "Live Demo",
  tag: "demo",
  diagram: { type: "twobox", leftTitle: "❌ More Data?", leftLines: ["Checked row counts vs. baseline", "Volume is normal — ruled out"], rightTitle: "❌ Blocking?", rightLines: ["Checked BLOCKING_SESSION / V$LOCK", "No blockers found — ruled out"], leftColor: COLOR.midnight, rightColor: COLOR.midnight },
  keyTakeaway: "Real investigations check plausible guesses instead of arguing about them.",
  notes: "This is the moment to say: “this is the discipline the whole course is built around.”",
  slideLabel: "8",
});

addContentSlide(pres, 1, {
  title: "Picture to Proof, in Five Queries",
  kicker: "Live Demo — Narrowing Down",
  tag: "demo",
  diagram: { type: "chain", small: true, items: [
    { label: "ALL ACTIVITY" }, { label: "ONE SQL_ID" }, { label: "ONE WAIT EVENT" }, { label: "ONE PLAN LINE" },
  ] },
  keyTakeaway: "Picture to proof, in five queries — diagnose.sql Steps A, D–H.",
  notes: "Pause on the Estimated-vs-Actual rows output — that number IS the punchline of this whole demo.",
  slideLabel: "9",
});

addContentSlide(pres, 1, {
  title: "Fix and Validate",
  kicker: "Live Demo",
  tag: "demo",
  bullets: [
    "fix.sql — unlock stats, then GATHER_TABLE_STATS (not a hint, not a forced index).",
    "validate.sql — rerun the job, compare elapsed time, plan_hash_value, and wait profile.",
    "Same query, same data, correct plan — proven, not felt.",
  ],
  keyTakeaway: "Explain explicitly why a hint or forced index would have been the wrong fix here.",
  notes: "This is a key talking point, not a footnote — the fix targets the proven root cause (stale/locked stats), not the symptom.",
  slideLabel: "10",
});

addContentSlide(pres, 1, {
  title: "What Did You Notice?",
  kicker: "Q&A — Discussion",
  bullets: [
    "What was the very first piece of evidence that told us something had changed?",
    "Why did we check false leads before jumping to the SQL?",
    "What would have happened if we'd just added an index without proving the cause?",
    "Where in this chain could you have gotten stuck if you were doing this alone?",
  ],
  keyTakeaway: "This was real investigation — and you just watched the whole loop happen once.",
  notes: "Let silence sit; don't rush to fill it. This is discussion, not a graded check.",
  slideLabel: "11",
});

addRecapSlide(pres, 1, {
  bullets: [
    "Measure → Observe → Hypothesize → Prove → Change → Validate — the loop you'll use every day.",
    "Picture, then proof: a visual first look narrows the search before you write SQL.",
    "False leads are normal — ruling something out with evidence is real progress.",
  ],
  homework: "Review the RECON_RUN_LOG baseline query and diagnose.sql — be ready to run this exact chain yourself tomorrow.",
  nextUp: "Tomorrow: yesterday you watched this happen; today you'll drive the same chain yourself, start to finish.",
});

pres.writeFile({ fileName: "/home/claude/oracle-performance-course/day01/day01-slides.pptx" }).then(() => console.log("day01 done"));
