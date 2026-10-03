# Audit follow-up — technical completion

Date: `2026-10-04` (Asia/Jakarta; `2026-10-03` UTC).
Status: `PASSED — NEEDS HUMAN REVIEW` for the tested technical scope.
Risk: `LEVEL 2 — LIMITED INTEGRATION`.
Branch: `fix/time-world/audit-runtime-regressions`.
Main baseline: `70420caacfb082ab0797b392e91f9e5cbfae409f`.
Starting tree: the approved part-1 cleanup and parts 2–8 fixes were uncommitted.
They are now preserved as `c6d5d47` and `af20275`, respectively.

The Game Director requested completion of the remaining work and explicitly chose
“Pertahankan map; tuntaskan sisa audit teknis dulu”. This follow-up closes the
remaining technical findings and graphical test gaps. It supersedes the earlier
repair report's outstanding technical items and Git status; that report remains
the historical record of the seven original fixes.

## Resolved findings and evidence

| Priority | Finding and resulting behavior | Evidence |
| --- | --- | --- |
| P2 | `emit_time_signal()` previously emitted elapsed-minute/day events even when time had not advanced. It now emits only the current `time_changed` snapshot. Actual minute advancement retains its normal signals. | `ClockStateBroadcastTest`: repeated refresh updates the real time label without needs/Focus drain or extra work; a real minute completes work once; midnight updates correctly. |
| P2 | Both outgoing and replacement Players could move during door fades. `can_move` now includes the existing global transition flag alongside independent movement restrictions. | `SceneTransitionTimingTest`: actual Home ExitDoor, held movement input, both Players remain at their intended positions, movement resumes, and failed fades preserve external restrictions. |
| P2 | Nightmare elapsed time included the unplayable entry fade. Its timer now waits while the global transition is active. Duration, conversion and penalty values are unchanged. | The same transition test verifies a frozen entry timer, playable progression, escape/result/return and restored movement/time. Existing collapse and worksite Nightmare suites also pass. |
| P3 | Runtime/import shutdown retained 15/16 Dialogue Manager script resources. Moving its existing autoload registration to the end removes the reproducible retention. | Isolation matrix, complete 40-suite regression run, editor import and bounded main launches; a new dialogue suite verifies singleton identity, compilation, mutation/conditional choices, and two real Player/NPC/balloon cycles. |
| P3 | A door awaited a global fade after its own scene was freed, leaving a function state at shutdown. The autoload now owns that continuation; doors still reject overlapping transitions and reset their trigger on load failure. | Verbose transition logs identify the former leaked function state; the revised real-door suite exits without diagnostics. Independent diff review found no retry/timing regression. |
| P3 | Pickup collection awaited an interval tweener that could outlive its freed item. The same node-bound tween now queues deletion with a callback at the unchanged final time. | The daily worksite suite's leaked `IntervalTweener` disappears; pickup, Inventory, gathering and resource suites pass. |
| P3 | The depth test sampled animated completion overlays, producing 224 false mismatch pixels. It now waits with a timeout for the splash nodes to leave before applying its original pixel assertions. The gathering test also finishes its triggered collapse entry before deleting the fixture. | Diagnostic frames compare the active overlays with settled built art. All three previously pending graphical suites and the gathering suite now pass. No depth assertion was removed. |

The addon diagnosis is an observed autoload-order dependency on this engine build,
not a claim to have proven Godot's internal cause. Tests of static unloading,
singleton unregistering and preload changes did not resolve it; those experiments
were confined to disposable copies and are not in the branch.

## Scope and changed files

Runtime modifications:

- `scripts/autoload/time_component_manager/time_component_manager.gd`
- `scenes/player/player.gd`
- `scenes/nightmare_world/nightmare_world.gd`
- `scenes/components/scene_door/scene_door.gd`
- `pickup_item.gd`
- `project.godot`: only move the existing `DialogueManager` line after the other
  existing autoloads, under the authorized remaining-shutdown repair. All 20 names
  and paths, engine feature level, main scene and display settings are preserved.

Test changes: `content_depth_time_debug_test.gd` and
`clay_worksite_test/test_scene_clay_worksite_gathering.gd`; three new `.gd`, `.gd.uid`
and `.tscn` entrypoints: `test_scene_clock_state_broadcast`,
`test_scene_transition_timing` and `test_scene_dialogue_runtime_regression`.

Documentation: `ARCHITECTURE.md`, `ROADMAP.md`, test `README.md`, and this report.
No additional deletion/rename accompanies this follow-up. The earlier 13 part-1
deletions were authorized cleanup. Addon code, authored dialogue, map composition,
design values, save schemas and the control pack are unchanged. `DEVLOG.md` remains
merged history; this branch still requires human review.

## Validation

Engine: **Godot 4.5.2.stable.official.6ce3de25a**. The default system binary is a
different version; all reported runs use the explicit 4.5.2 binary path. Tests use
an isolated project and separate writable user/config/cache directories and run
serially because the existing MCP runtime binds a local port.

**41 unique suites pass:** the previous 35, three previously pending graphical
suites, and three new clock/transition/dialogue suites. The complete 40-suite run
validated the proposed autoload order; eight affected suites were rerun after the
door/pickup cleanup. Dialogue passed both headlessly and graphically. Retries,
imports, launches and diagnostic experiments do not inflate the suite count.

Every accepted suite reaches its success marker, exits 0 and has no script,
resource-loading or ObjectDB/retained-resource shutdown diagnostics. Final import
is also checked from an empty `.godot` cache, followed by main launch and dialogue.
Bounded 120-frame main launches are smoke checks, not complete gameplay suites.

Graphics used the already installed Xorg dummy driver and Mesa llvmpipe with GL
Compatibility, the normal `400 x 225` logical viewport and `1200 x 675` window.
Workshop worker presence, assignment discard and built-art depth assertions pass;
saved frames were inspected for the panels, construction feedback, occlusion and
dialogue balloon. No renderer, engine, addon or system dependency was installed.
The virtual driver reports that V-Sync mode changes are unsupported. This exact
driver warning is recorded separately; no resource warning is accepted as clean.

Initial test failures are retained in the evidence: the graphical runner initially
expected the wrong assignment-test marker; depth checks sampled completion
splashes; the new dialogue fixture needed valid GDScript lambda continuation,
tab-indented dialogue and a predicate that did not capture a freed balloon. These
were corrected and rerun. Plugin/game dialogue was not changed to accommodate them.

## Remaining limits and decisions

- **P3 diagnostic follow-up:** `--verbose` still lists 38 unclaimed `StringName`
  entries on full-project exit (39 after dialogue), without an ObjectDB warning or
  retained-resource error. Isolation reproduces the 38-entry trace with Dialogue
  Manager removed and with MCP removed; empty, MCP-only, time-only and
  DialogueManager-only probes have no such trace. Its internal cause and any
  long-session effect are unproven. The logs remain visible; this report claims
  resolution of the reproduced object/script leaks, not zero verbose shutdown
  output. A smaller engine-level reproducer remains useful before changing more
  game code or considering an engine/addon update.
- The minimal map stays at two plots and Worker Hub/Job Board by explicit user
  choice. Normal Shekel income, the full normal-game loop, Home/resource-site/
  Nightmare map integration and production disk saving remain unfinished features,
  outside this technical repair. Preserved fixtures do not certify their presence
  on the current map, and its existing needs/debug guards remain in place.
- The user's exact local patch, physical GPU/OS, Android and extended play sessions
  are unverified. Software-rendered desktop checks do not establish those results.
- Main remains at the recorded baseline when checked for handoff. Commits and a PR
  package the audit work; only the human Game Director may approve a merge. No
  merge, forced push or published-history rewrite is part of this task.

## Evidence

- [Accepted results and log paths](/workspace/audit-results/time-is-precious-followup-2026-10-04/summary.json)
- [All run records, including superseded failures](/workspace/audit-results/time-is-precious-followup-2026-10-04/validation.json)
- [Final source and scope integrity](/workspace/audit-results/time-is-precious-followup-2026-10-04/final-integrity.json)
- [Reproduction notes and screenshots](/workspace/audit-results/time-is-precious-followup-2026-10-04/README.md)
- [Earlier seven-fix report](audit-parts-2-8-fixes-2026-10-04.md)
