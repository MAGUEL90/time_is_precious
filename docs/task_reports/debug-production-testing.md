# Production testing debug controls — 2026-10-03

Branch: feature/process-workshop/main-map-access. Baseline c7d0a4e plus the preceding
uncommitted production audit tests/report. User authorized the debug supplies and retest.
Scope: scene-local debug controls and tests; no economy, recipe, fee, map, or autoload edits.

## Use

Run ContentScene again to load the updated script. Click Debug at the upper left or
press backtick. F9 is not used. Controls remain separate from gameplay menus.

- x1 / x10 / x60 and +30m / +3h / +1d retain normal clock signals and pause guards.
- Build kit tops personal Inventory up to Wood 6, Clay 12, Reed 8.
- Production tops up two shaping recipes plus raw materials for Drying Yard levels 1
  and 2: Clay 10, Straw 6, Water 6, Wood 6, Reed 10. Finished bricks are never granted.
- 100 Shekel tops personal Inventory up to 100; repeated clicks do not keep adding 100.
- Inventory 500 raises personal carrying capacity from 100 to 500 without changing item
  weights or workshop storage. Switching it off restores the original limit only after
  carried weight fits; it never removes items. The override follows Inventory across
  scene changes and resets when the game restarts.
- Worker guard holds hired workers and their linked citizens at satisfaction 0.5 and
  reliability 0.9 while time changes. It starts OFF and resets OFF on map reload.
  It does not hire workers, fill food/clothing stock, erase obligations, or guarantee a
  successful random reliability roll. Disabling it stops further overrides; prior values
  are not restored.
- Player guard controls the existing player needs/fatigue debug flags. Its initial state
  reflects the authored protection already enabled on this map.

Recommended sequence: recruit through Job Board; enable Worker guard; obtain Build kit
and Shekel; clear/build normally using the time controls; then obtain Production kit and
deposit it through Manage Storage. Build kit and Production kit are meant for successive
stages. Full bags reject an entire top-up without partial grants; deposit/make room first.
Supplies also work while a gameplay menu is paused; time jumps remain blocked by pause.

## Verification

Godot 4.5.1 GL Compatibility, 1200x675 window / 400x225 logical viewport.

- DebugProductionFlowTest PASS: actual current map, actual Job Board Laborer, actual debug
  supply buttons; atomic capacity rejection, repeated top-ups, supplies while paused,
  worker guard across clearing and three-day construction, no completed-output grants,
  two shaping/drying/payment cycles, yard upgrades, output withdrawal and guard disable.
- Produced 40 sun-dried mudbricks: 10 consumed by the level-2 upgrade, 1 in Inventory,
  29 in workshop Free Stock. Paid 14 Shekel, leaving 86 from the debug top-up.
- Expanded-inventory follow-up PASS: 498 weight accepted, 501 rejected, overweight
  shrinking refused without item loss, recreated overlay reflects the override, unloading
  permits restoration to 100. Two production cycles still pass after restoration.
- ContentDepthTimeDebugTest PASS: previous time-rate/pause controls, material grants,
  real plot completion and rendered depth-order regression checks.
- NormalStartProductionAudit rerun PASS as a diagnostic: without pressing the new
  controls, no debug supplies appear; 17 wet bricks remain held and zero Shekel still
  blocks payment. Debug additions do not silently fund or stabilize normal gameplay.
- Debug panel screenshot inspected: controls fit the logical viewport; scroll area handles
  feedback. No gameplay-panel layout changed.
- Diff whitespace check passed. Existing ObjectDB shutdown warning and 15 retained
  resources persist; the final passing tests have no new script errors.

The production test fixes its random seed for reproducibility. The debug panel itself
does not alter RNG. Tests teleport to interactions and use existing UI signals; keyboard
navigation/pathfinding, release export and mobile were not tested. Release guard paths
were source-reviewed, not validated with a release export.

This validates the DEBUG-ASSISTED loop. Normal Shekel income and long-term worker needs
remain separate design/integration gates. No commit/push performed.

Evidence: C:/Users/Hendro/.codex/visualizations/2026/09/26/01a0dc60-e89d-7533-abe7-945885d9db59/debug-production-controls.png
