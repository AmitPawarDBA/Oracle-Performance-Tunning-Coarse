const { newDeck, addTitleSlide, addContentSlide, addRecapSlide, COLOR } = require("./theme");

const pres = newDeck("Day 6: Architecture Bootcamp IV — How Oracle Executes a Statement");

addTitleSlide(pres, {
  dayNum: 6,
  title: "Architecture Bootcamp IV: How Oracle Executes a Statement",
  subtitle: "The bridge day — closing Days 3–6.",
});

addContentSlide(pres, 6, {
  title: "Where We've Been",
  kicker: "Architecture Bootcamp Recap",
  bullets: [
    "Day 3 — the instance: SGA memory structures (shared pool, buffer cache, redo log buffer) vs. the PGA.",
    "Day 4 — storage, redo & undo: tablespaces, segments, extents, blocks, and how a transaction is protected.",
    "Day 5 — processes: the listener handing off to a server process, and the fixed cast of background processes.",
    "Four puzzle pieces, mapped in isolation — about to become one picture.",
  ],
  keyTakeaway: "Today adds no new machinery — it runs everything you've already mapped, in order, against one statement.",
  notes: "Have students recall one unprompted fact each from Day 3, Day 4, and Day 5 before moving on — this primes the callback structure the rest of the hour depends on.",
  slideLabel: "2",
});

addContentSlide(pres, 6, {
  title: "Today's Question",
  kicker: "Bridging Theory to Practice",
  diagram: { type: "quote", text: "You've mapped every piece of the machine. What happens when you actually turn it on?" },
  keyTakeaway: "By the end of this hour you'll be able to name the architecture component behind any number you see.",
  slideLabel: "3",
});

addContentSlide(pres, 6, {
  title: "The Five-Stage Lifecycle",
  kicker: "Every Statement, Every Time",
  diagram: { type: "chain", items: [
    { label: "PARSE" }, { label: "OPTIMIZE" }, { label: "ROW SOURCE GEN" }, { label: "EXECUTE" }, { label: "FETCH" },
  ], boxH: 1.0 },
  keyTakeaway: "Five stages, fixed order — the shape we'll wire to Days 3–5 on the next slide.",
  notes: "No detail yet — this slide is deliberately bare. The comprehensive wiring comes next.",
  slideLabel: "4",
});

addContentSlide(pres, 6, {
  title: "Statement Lifecycle, Fully Wired to the Bootcamp",
  kicker: "The Bootcamp's Payoff Slide",
  diagram: { type: "chain", small: true, boxH: 1.05, items: [
    { label: "PARSE", caption: "Library Cache / Shared Pool (Day 3) — hard parse only: Data Dictionary semantic check (Day 4)" },
    { label: "OPTIMIZE", caption: "Data Dictionary / Object Stats (Day 4) — CBO cost-based evaluation" },
    { label: "ROW SOURCE GEN", caption: "Library Cache (Day 3) — plan becomes an executable row-source tree" },
    { label: "EXECUTE", caption: "Buffer Cache (Day 3) + PGA Work Area (Day 3) — driven by the Server Process (Day 5)" },
    { label: "FETCH", caption: "Server Process → Client (Day 5)" },
  ] },
  keyTakeaway: "Every stage is Days 3–5 architecture, running in a fixed order, driven by one server process (Day 5) start to finish.",
  notes: "This is the slide students will screenshot. Say 'Day 3,' 'Day 4,' and 'Day 5' out loud as you walk each box left to right.",
  slideLabel: "5",
});

addContentSlide(pres, 6, {
  title: "Hard Parse vs. Soft Parse",
  kicker: "The Parse Stage, In Detail",
  diagram: { type: "twobox",
    leftTitle: "Hard Parse — Cache Miss",
    leftLines: [
      "Text hashed, library cache lookup misses",
      "Syntax check + semantic check against the Data Dictionary (Day 4)",
      "Full cost-based optimization runs (Optimize stage engaged)",
      "New cursor and plan built, then cached",
    ],
    rightTitle: "Soft Parse — Cache Hit",
    rightLines: [
      "Text hashed, library cache lookup hits",
      "Existing cursor reused — dictionary lookup skipped",
      "Optimizer not invoked — plan is already resident",
      "Straight through to Row Source Gen with the cached plan",
    ],
    leftColor: COLOR.amber, rightColor: COLOR.teal,
  },
  keyTakeaway: "A soft parse skips semantic checking and the entire Optimize stage — that's the whole point of reuse.",
  notes: "This is exactly why literal SQL vs. bind variables matters later — every distinct literal forces its own hard parse (Day 19).",
  slideLabel: "6",
});

addContentSlide(pres, 6, {
  title: "Evidence, Not Guesswork",
  kicker: "Live Demo — V$SQLAREA",
  tag: "demo",
  bullets: [
    "Cold run: a uniquely tagged statement guarantees the library cache has never seen this text.",
    "Warm run: identical text, same session, run again immediately after.",
    "LOADS stays flat at 1 — no second hard parse ever occurred.",
    "PARSE_CALLS and EXECUTIONS both climb — direct, numeric proof of reuse.",
  ],
  diagram: { type: "table",
    header: ["Run", "LOADS", "PARSE_CALLS", "EXECUTIONS"],
    rows: [
      ["Cold (hard parse)", "1", "1", "1"],
      ["Warm (soft parse)", "1", "2", "2"],
      ["Third execution", "1", "3", "3"],
    ],
  },
  keyTakeaway: "LOADS unchanged + PARSE_CALLS/EXECUTIONS incrementing is the signature of a soft parse.",
  notes: "Exact millisecond timings and physical-read counts are environment dependent — the structure of the evidence is what's guaranteed.",
  slideLabel: "7",
});

addContentSlide(pres, 6, {
  title: "Execute Is Where Memory Gets Real",
  kicker: "Buffer Cache & PGA, Live",
  diagram: { type: "twobox",
    leftTitle: "Buffer Cache (SGA — Day 3)",
    leftLines: [
      "Every block request checks the buffer cache first",
      "Resident block = logical read (cache hit)",
      "Missing block = physical read from the datafiles (Day 4)",
    ],
    rightTitle: "PGA Work Area (Day 3)",
    rightLines: [
      "Private, per-process memory — not shared like the SGA",
      "Sort/hash space for GROUP BY, ORDER BY, hash joins",
      "Sized automatically under PGA_AGGREGATE_TARGET",
      "Spills to TEMP if it doesn't fit (preview: Day 29)",
    ],
    leftColor: COLOR.deepBlue, rightColor: COLOR.midnight,
  },
  keyTakeaway: "Execute is the one stage where Day 3's memory diagrams stop being pictures and start being touched.",
  slideLabel: "8",
});

addContentSlide(pres, 6, {
  title: "Real-World Scenario Recap",
  kicker: "PERF_LAB — Worked Example",
  tag: "scenario",
  bullets: [
    "Query: three-way join — CUSTOMERS ⋈ ORDERS ⋈ ORDER_ITEMS, filtered on order_date and region, GROUP BY/ORDER BY on order_total.",
    "Parse: first time this exact text runs → hard parse; semantic check resolves all three tables against the Data Dictionary (Day 4).",
    "Optimize: the CBO reads ORDERS's partition metadata and CUSTOMERS's region stats, then fixes access paths, join method, and join order.",
    "Execute: blocks come from the buffer cache (Day 3) or a physical read (Day 4); the GROUP BY/ORDER BY use a PGA work area (Day 3).",
    "Fetch: rows stream back over the session's server process (Day 5).",
    "A second analyst running the identical text later collapses parse/optimize/row-source-gen into one soft parse — only execute/fetch do real work again.",
  ],
  keyTakeaway: "Every clause in the answer names a Day 3, Day 4, or Day 5 concept explicitly — no gaps, no hand-waving.",
  slideLabel: "9",
});

addContentSlide(pres, 6, {
  title: "Parse, Plan, or Execute?",
  kicker: "Troubleshooting Challenge Preview",
  bullets: [
    "Parse-time issue — the library cache lookup, or the hard-parse work itself, is the problem.",
    "Optimizer/plan issue — the CBO chose the wrong plan, or keeps choosing a different one.",
    "Execution/fetch issue — parsing and the plan were fine; the cost is in touching blocks or work areas.",
    "Example: LOADS = 4,712 against EXECUTIONS = 4,750 — which column does that belong in?",
    "Example: physical reads spike, but PLAN_HASH_VALUE hasn't changed — which column does that belong in?",
  ],
  keyTakeaway: "Same triage instinct Day 7 onward builds on — locate the phase before you locate the fix.",
  notes: "This is a teaser into the Q&A, not the full answer key — let the room guess before revealing the classification drill.",
  slideLabel: "10",
});

addRecapSlide(pres, 6, {
  bullets: [
    "Every stage of statement execution is architecture you already know: parse → library cache, optimize → dictionary, execute → buffer cache + PGA + server process, fetch → server process.",
    "Hard parse vs. soft parse is the difference between doing that work and reusing it — LOADS vs. PARSE_CALLS vs. EXECUTIONS is your proof.",
    "This closes the Architecture Bootcamp (Days 3–6) — everything from Day 7 forward assumes this fluency.",
  ],
  homework: "Re-run demo.sql on your own and explain each of the five lifecycle stages in your own words; look up (don't run) V$SYS_TIME_MODEL / V$SESS_TIME_MODEL's column list and bring one question; think about where you'd look to put a number on how much more a hard parse costs than a soft parse.",
  nextUp: "Day 7: You now know how a statement runs. Next: how do we measure how long each stage actually took? DB Time and the time model.",
});

pres.writeFile({ fileName: "/home/claude/oracle-performance-course/day06/day06-slides.pptx" }).then(() => console.log("day06 done"));
