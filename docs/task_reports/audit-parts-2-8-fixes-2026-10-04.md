# Audit parts 2–8 — approved fixes

Date: `2026-10-04` (Asia/Jakarta; `2026-10-03` UTC).
Status: `PASSED — NEEDS HUMAN REVIEW` for the tested headless scope.
Risk: `LEVEL 2 — LIMITED INTEGRATION`.
Branch: `fix/time-world/audit-runtime-regressions`.
Baseline: `70420caacfb082ab0797b392e91f9e5cbfae409f`.
Starting working tree: dirty with the approved, uncommitted part-1 cleanup.

The Game Director explicitly authorized “oke lanjut perbaikan kode bagian 2-8”.
This task fixes the seven findings from the completed audit, including necessary
integration with existing worksite and plot movement controls. Acceptance requires
reproduced boundaries to pass, nearby suites to remain valid, and part-1 work to
survive unchanged except for appended test documentation.

The authorization covers the affected Player lifecycle and citizen application
logic, including code in the CitizenManager autoload. Autoload registration,
project settings, addons, dependencies, save schemas, economy values and the
control pack were not changed. No new design rule was introduced; negotiation
was reconciled with the existing design. No commit, push or merge was performed.

## Findings resolved

| Finding | Resulting behavior | Regression evidence |
| --- | --- | --- |
| AUD-01 · P1 · Pickup/collapse movement lock | Player actions release only their own movement restriction. Pickup, dialogue, sleep, collapse and Nightmare return preserve independent restrictions. A stale pickup timer cannot replace the faint animation. | PlayerActionLocksTest; PlotCollapseHandoffTest; existing ClayWorksiteNightmareTest |
| AUD-02 · P2 · Inventory releases Workshop pause | The Inventory shortcut is blocked over a paused modal. Open/close and exit cleanup restore the captured pause state once. | InventoryModalPauseTest |
| AUD-03 · P2 · Hauler becomes Laborer on rehire | Eligible daily reapplication retains an established profession. A first-time applicant with no profession still defaults to Laborer. | WorkerRehireRegressionTest, including real midnight, identity and XP retention |
| AUD-04 · P2 · Worksite teardown refunds and pays | Cancellation stops progression and refunds once. Settlement retains its busy state so synchronous callbacks cannot restart or cancel a payout. Owner removal and freed Player references are checked before further work. | ClayWorksiteTeardownTest, including minute-11 removal, conservation and payout reentry |
| AUD-05 · P2 · Direct negotiation needs charges | Negotiation advances its configured time without the extra flat hunger/fatigue charges. Normal time-driven needs and Focus changes remain. | NegotiationNeedsTest, comparing actual NPC negotiation with equal elapsed time |
| AUD-06 · P2 · Three obsolete integration assertions | Supply/content suites expect exactly the approved unallocated startup Cart. Hauling verifies all seven authored destinations and checks City Storage rejection separately. | CityStorageSupplyFlowTest; ContentWorksitesIntegrationTest; CityStorageHaulingTest |
| AUD-07 · P3 · City Storage integer overflow | Deposit and cargo paths reject unrepresentable sums atomically. The exact integer maximum remains valid. | CityStorageOverflowTest, including batch atomicity and unchanged rejected state |

The movement fix also required the shared worksite controller and WorkshopPlot to
own named movement restrictions. Their previous raw boolean restoration depended
on collapse restoring a captured value. Panels now release their own restriction
on close, collapse handoff and teardown. This preserves playable Nightmare entry
and return after either gathering or manual plot clearing.

## Changed files

Runtime files modified:

- `scenes/player/player.gd`
- `scenes/player_visual/player_visual.gd`
- `scenes/nightmare_world/nightmare_world.gd`
- `scenes/ui/inventory_ui/inventory_ui.gd`
- `scripts/autoload/citizen_manager/citizen_manager.gd`
- `scenes/test_scenes/clay_worksite_test/clay_worksite_session.gd`
- `scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.gd` — shared production controller despite its directory.
- `scenes/workshop_plot/workshop_plot.gd`
- `scenes/npc_base/npc_base.gd`
- `scenes/storage_destination/city_tool_storage.gd`

Existing tests modified under `scenes/test_scenes/clay_worksite_test/`:

- `test_scene_city_storage_supply_flow.gd`
- `test_scene_content_worksites.gd`
- `test_scene_city_storage_hauling.gd`

Seven new test entrypoints, each with `.gd`, `.gd.uid` and `.tscn`, under
`scenes/test_scenes/`:

- `test_scene_player_action_locks`
- `test_scene_plot_collapse_handoff`
- `test_scene_inventory_modal_pause`
- `test_scene_worker_rehire_regression`
- `test_scene_negotiation_needs`
- `test_scene_city_storage_overflow`
- `clay_worksite_test/test_scene_clay_worksite_teardown`

Documentation: `ARCHITECTURE.md` now describes the actual ContentScene startup,
needs guards and movement ownership; `scenes/test_scenes/README.md` documents new
entrypoints and test prerequisites; this report is new. No files were deleted or
renamed by the parts 2–8 repair. The 13 prior part-1 deletions remain intentional.

## Verification

Engine: **Godot 4.5.2.stable.official.6ce3de25a**, headless. Tests ran serially in a
disposable project copy with isolated user/config/cache directories.

**35 unique suites passed: 7 new regressions and 28 existing suites.** Every final
suite reached its named success marker, exited 0 and had no unexpected script or
resource-loading errors. The existing suites cover player conditions/collapse,
daily citizen needs, hiring, storage/supplies, gathering/hauling, construction,
separate plots, production fees/output, and current-map Worker Hub/Hauler flows.
All eight suites previously used for part 1 were rerun successfully.

Three additional diagnostic probes completed. They verify minute/day boundaries,
sleep and repeat-sleep rules, Player state continuity through replacement and an
actual door transition, a single live Player clock connection, and consume/drop
conservation. Timing observations from those probes remain separate from suite
passes. Fresh editor import and a 120-frame bounded main-scene launch also passed;
the launch is not counted as a completed gameplay suite.

Initial runs exposed two test-fixture lifetime errors and the worksite movement
handoff regression described above. They were corrected and rerun; raw failed
records remain available as superseded evidence. Retries do not inflate the
35-suite count. No failed latest result is excluded from that count.

Root review covered delegated diffs, nearby integration and final source
integrity. All **680 runtime/resource files** compared with the tested copy match.
Part-1 changes remain byte-identical except the README extension, and its deleted
files remain absent. `git diff --check` passed. No hard-protected file changed.

## Remaining limits

- Visual/desktop/mobile behavior is unverified. WorkshopWorkerPresenceTest and
  WorkshopAssignmentDiscardTest were blocked by rendered-frame waits in the
  earlier audit and were not rerun headlessly. ContentDepthTimeDebugTest also
  requires graphical execution. Other OS/renderers and the user's exact local
  4.5.x patch were not tested.
- Existing ObjectDB/resource shutdown diagnostics remain: 15 retained resources
  for runtime exits and 16 for editor import. Earlier evidence locates retained
  Dialogue Manager scripts; root cause and long-session impact remain unproven.
  These exact diagnostics are reported separately, not hidden as a clean exit.
- The current authoring map still lacks its earlier Home Door/resource-site/
  Nightmare composition and uses needs guards. Enabling ordinary needs without
  restoring recovery can repeatedly trigger missing-Nightmare collapse. Normal
  Shekel income and the complete normal-game loop remain unfinished integration
  work. Tests using preserved fixtures do not certify those features on this map.
- Lower-priority audit observations remain: Nightmare time elapses during entry,
  door fades allow movement, and clock state rebroadcast can drain needs without
  elapsed time (no current active-play caller was found). These were outside the
  seven approved defect repairs. Scene-local worksite state and shared workshop
  production storage retain their existing contracts; disk save/load is untested.

## Evidence

- [Original read-only audit](/workspace/audit-results/time-is-precious-2026-10-03/audit-parts-2-8.md)
- [Final results and log paths](/workspace/audit-results/time-is-precious-fixes-2026-10-04/summary.json)
- [All run records, including superseded failures](/workspace/audit-results/time-is-precious-fixes-2026-10-04/validation.json)
- [Source integrity](/workspace/audit-results/time-is-precious-fixes-2026-10-04/final-integrity.json)
- [Reproduction notes](/workspace/audit-results/time-is-precious-fixes-2026-10-04/README.md)

Human code/visual review and any later merge decision remain pending. This report
records completion of the authorized repair and headless checks.
