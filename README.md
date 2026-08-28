# Oracle Database Performance Tuning & Troubleshooting — 34-Day Course

A practical, scenario-driven Oracle performance tuning and troubleshooting course for working Oracle DBAs, built around one repeatable loop:

**Measure → Observe → Hypothesize → Prove → Change → Validate**

## Status

Phase 1 complete: research, design philosophy, 34-day roadmap, performance-engineering toolkit map, and lab environment design.
See `docs/phase1-course-foundation.md`.

Phase 2 (in progress): day-by-day curriculum, lab scripts, instructor notes, and slide content, built and committed in weekly batches.

## Structure

- `docs/` — course design documents (this is where Phase 1's foundation doc lives)
- `setup/` — one-time PERF_LAB schema creation, data generation (Small/Standard/Large tiers), and environment verification
- `dayNN/` — one folder per course day: `setup.sql`, `demo.sql`, `diagnose.sql`, `fix.sql`, `validate.sql`, `cleanup.sql`, `reset.sql`
- `tools/` — course-written notes and links for every third-party tool referenced in the course (OraPub BloodHound/ASH Visualization Tool, Carlos Sierra's cscripts/eDB360/SQLHC/SQLT, Tanel Poder's tpt-oracle, Fred Denis's rac-status.sh). No third-party code is copied into this repo — each tool is credited and linked to its own public source; see `docs/phase1-course-foundation.md` → "Deliverable 1B — Performance Engineering Toolkit Map" for exactly what each one does and why.
- `common/` — shared queries and utilities used across multiple days

## License / attribution

Original course content (schema, data generators, problem-injection scripts, instructor notes, scenarios) is written for this course. Where a day references a public third-party tool or script, that tool's own license and source repository govern its use — see `tools/README.md`.
