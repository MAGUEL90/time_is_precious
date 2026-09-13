# Daily duration feedback and worker status audit

Date: 2026-09-09
Scope: Level 1 sandbox UI; read-only mechanics/design audit.
Branch: feature/process-workshop/clay-worksites. Existing local edits retained.

## Implemented

- Main confirmation shows `Duration: 8 h / day` and `07:00 - 15:00` below worker names, including when reopening a running Daily assignment.
- Text derives from the Daily scheduler constants via its preview provider. It describes the full shift, not remaining hours when assigned late.
- Player duration and empty-state visibility remain unchanged.
- Modified: `test_scene_clay_worksite.gd` and sandbox `clay_worksite_inspector.gd`.

## Verified

- Graphical ClayWorksiteDailyTest at 1200x675: PASSED; captured and visually inspected daily-ready.png.
- Headless ClayWorksiteInspectionTest: PASSED.
- Main project launch smoke: exit 0. git diff --check: clean.
- Existing root certificate store / ObjectDB / 15 resources at exit messages remain; no new blocking errors observed.
- User reports the Nightmare loop passed manual testing.

## Current status ownership

- CitizenData: population and employment states, shared needs, satisfaction and reliability.
- WorkerData: profession, XP/star fields, efficiency, and IDLE/WORKING execution lifecycle. Linked citizen owns resolved shared needs/satisfaction/reliability.
- CitizenNeedsManager processes daily needs and satisfaction/reliability; WorkManager uses satisfaction and reliability in workshop output.
- Scene-local Daily scheduler enforces 07:00-15:00, a 480-minute per-worker ledger and finite shared stock. All roles currently gather at 6 clay/hour; role-based rates are not implemented.
- Depletion stops gathering, settles output to the site pile and retains the standing assignment for tomorrow. WorkerData stays WORKING to reserve the worker, even while resting or depleted. Activity and reservation are not yet separated in the global state.

## Discussion only, not implemented

- Proposed normal gathering rates: Laborer 2 clay/hour (16/full day), other gathering roles 1/hour (8/full day). Transport and crafting specialization remain separate future activities.
- Proposed Small stock 28-36: two Laborers have 32/day capacity; at 28 stock and a 07:00 start they exhaust the site at 14:00. Partial-day work and Player extraction can reduce available output further.
- Proposed Large stock 66-78 needs a slot-capacity decision: four baseline Laborers produce only 64/day, so this range would never constrain that team.
- Recommended activity states: Working, Resting, Waiting for resources, Idle; keep workplace assignment independent so exhaustion does not silently cancel a Daily job or allow double assignment.
- Latest worksite direction uses satisfaction for willingness to accept work; game-concept section 13 and existing workshop code also use output multipliers. Resolve this scope difference before applying satisfaction to worksite yields.

No rate, random-stock range, satisfaction rule, global worker state or production source changed in this task.
