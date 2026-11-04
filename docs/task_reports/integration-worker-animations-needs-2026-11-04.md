# Worker, world animation, and resident-needs integration — 2026-11-04

Status: **PARTIAL — NEEDS HUMAN REVIEW**. Logistics is not integrated. This is
an isolated cloud integration, not approval to update the shared target branch.

## Branch and merge review

- Branch: `feature/gameplay/integration-worker-animations-20261104`.
- Baseline: `13a6c0725a08c91bfcbc2606646e8ebf0f668968` from
  `feature/gameplay/character-needs-20261101`.
- Included final commits: worker `7b78214144d1f9a65c1c5de41c5ee452dd032404`,
  animation `9c196b92d1962a1f0858a46887d676508c47f3cc`, and needs
  `dc24efb48def073e1be4a5d7891c6f18c2fc5e73`.
- Runtime-tested merge commit: `fa626b209e373fa667b11e9960b9671bc129f21c`.
  This report adds documentation only after those tests.
- No manual merge conflict. Git combined changes in
  `clay_worksite_worker_visuals.gd` and `date_palm_spawner.gd`; review confirmed
  the route revision and footstep listener, and palm sway and grouped gathering,
  respectively, remain together. `player.gd` and `pickup_item.gd` match the
  needs commit; the worker worksite code matches the worker commit.
- The original checkout was already dirty and was not modified. All work used a
  separate clone; no branch was pushed and no laptop was accessed. Godot's
  editor generated untracked import/UID metadata in the clone; generated
  changes to tracked project and import settings were restored before testing.

## Integration checks

Godot 4.5.2 stable on Linux, isolated disposable XDG profiles, tests run
sequentially to avoid the debug plugin's shared port. The graphical animation
run used GL Compatibility and Mesa llvmpipe on a virtual X display. Import and
start-menu launch completed, with no script or parse errors in the final run.

| Check | Result |
| --- | --- |
| Multi-worker navigation: write, read, hire | PASS: 347, 340, and 435 assertions. Includes distinct destinations, replacement, blocked-route recovery, shift boundaries, shared stock and in-flight save/load. |
| World-life animation | PASS headless and graphically. Covers palm movement, resident footsteps, pause, transition and cleanup. A graphical capture produced 130 frames. |
| Resource routes | PASS; fixture walked routes at all five resource sites. |
| Scene transition and inventory pause | PASS: `SceneTransitionTimingTest`, `InventoryModalPauseTest`. |
| Worker/resident lifetime and palms | PASS: `CityResidentTest`, `WorkerVisualLifecycleTest`, `DateTreeDuplicateTest`. |
| Palm and other pickup regressions | PASS: `PalmGatherTest`, `PickupSourcesTest`, including grouped gathering, ordinary pickup, partial capacity and save guards. Two expected warnings report rejected checkpoint attempts during an active interaction. |
| Merchant | PASS: `MerchantRandomRequestsTest` and `TravelingMerchantTest`. |
| Resident needs | PASS: `CityFoodDailyTest`, `CityClothingNeedsTest`, `PopulationEmploymentIntegrationTest`. |
| Authored-map save | PASS: `ReviewDefaultSaveTest` write, read and restart in separate processes. |
| Old merchant checkpoint | PASS: fixture wrote a partially traded visit using baseline `13a6c07`, then loaded it in the integrated build, repeated the load, checked the next visit and saved/loaded again. |
| Resident recovery journey | PASS write/read **with `--allow-legacy-player-worksite`**, seed 2 / food seed 1. This pre-logistics fixture reached recovery on day 6. It teleports the player to interactions and is not a human walking playthrough. |

For the old-merchant writer only, the test scene and script from the needs
branch were copied into a disposable checkout of `13a6c07`; production code
there remained the baseline. The read phase ran on the integrated merge.

The graphical driver's unsupported V-Sync switch produced a warning. An initial
capture also fell back to dummy audio because the virtual machine has no audio
device; a second graphical run explicitly using the dummy audio driver passed
without that error. Original animation review clips remain in
`docs/task_reports/evidence/world-life-animations-2026-11-04/`.

## Remaining work and limits

- Await the **final** logistics hash. Integrate only when instructed, then rerun
  the standard resident-needs journey **without** the legacy option and test
  City Storage output, player-supplied building materials, storage-to-storage
  haulers, two workers, navigation and save/load together.
- The source reports record existing failures in FoodWalkingPlaytest,
  ContractJourney, ContentActualArrival, the clay worksite team test,
  WorksiteMidnightContinue, ResourceWorksites and WorksitePresentation. Those
  failures were reported against their earlier baselines and were **not rerun**
  for this integration; they are not silently counted as passing here.
- The test fixtures and virtual display do not replace a human playthrough,
  aesthetic approval, Windows testing or Android testing. The requested
  logistics behavior and the game as a whole are not claimed complete.

Logs and the disposable test profiles are under
`/tmp/tip-integration-20261104-kOvYQm/` in this cloud session.
