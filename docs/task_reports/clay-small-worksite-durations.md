# Small worksite duration checkpoint

2026-09-07 — PASSED — NEEDS HUMAN REVIEW.
Latest user decisions: 72 test stock remains; Player may also work nine hours.

Duration choices and backend validation now accept 3/6/9 hours, replacing 1/3/6/12.
One Player nominal output: 18/36/54 clay. Existing needs, collapse, stock limits,
overflow handling and Nightmare return are retained. Default selection is three hours.
Small-site capacity is recorded as two total participants including Player; the panel
shows Workers: 1 / 2 beneath Tool effect. Only Player execution currently exists.
This checkpoint does not implement Add Worker, mixed-team throughput, NPC storage,
wages or daily scheduling. Those remain a separate integration step.

The UI is 240x150 normally, with extra room for blocked-state feedback.
Existing almost-full inventory preset remains active. Fresh F6 + three hours produces
18 clay: two enter inventory and sixteen fall to ground.

Changed session configuration, inspector script/scene and existing inspection/gathering
test assertions. Tests passed: inspection (headless/graphical), gathering (including
Player completing nine hours), and full Nightmare escape/timeout round trips.
Graphical screenshot reviewed at 1200x675. Existing engine certificate/shutdown warnings
remain. No production systems/settings or unrelated local work changed; no commit/merge.
