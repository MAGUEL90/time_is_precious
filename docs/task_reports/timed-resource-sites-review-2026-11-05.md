# Timed resource-site review — 2026-11-05

This review branch builds on `257dde18d1aa57212c2a82d786719dfe3d1d1168`. It is for an isolated laptop playtest after review; the shared branch and the laptop have not been updated. The authored map file `scenes/map_authoring/new_map_authoring.tscn` is unchanged. This report supersedes the **240-unit** and immediate-respawn prototype described in the previous finite-sites report.

## Review settings

| Resource | New-game sites | Units per fresh deposit |
| --- | ---: | ---: |
| Clay | 2 | 36 |
| Water | 1 | 48 |
| Reed | 2 | 40 |
| Wood | 3 | 24 |

These capacities are temporary testing values. Hourly work by the player still produces player-owned items; Daily worker output is received by City Storage. A deposit counts down from the end of a committed depletion, for a randomly sampled **2,880–4,320 game minutes** (two to three days). A cancelled manual transaction cannot start a timer for returned stock. The site's art and solid base disappear while depleted; its assignment remains, and assigned workers must reach the replacement before producing again. The inspector shows the reserve and waiting time.

Four additional initial markers and ten replacement candidates are explicit **temporary test positions south of the wall**, not final randomized map placement. The runtime checks land-layer coverage, collision clearance, authored property plots, player and worker clearance, and routes before a replacement appears. If all candidate points are obstructed, the empty site waits and retries after 60 game minutes; a two-to-three-day timer is not a guarantee that an obstructed site can immediately respawn. The map's water tile layer is a broad underlay, so those checks do not establish a final dry-land/water classification. The existing wall artwork has no physics layer: workers use provisional waypoints through its south opening, but the artwork itself does not block a player. Position, discoverability, wall collision and environmental suitability require Hendro's map review.

`StrawSite` is the existing compatibility source, with its existing 72-unit marker default and existing IDs. No new straw gathering site or farming system was added. It remains accessible in New Game and old saves because removing the only current straw source would break the existing production path; it is not a decision against the intended future field/planting/harvesting system.

## Isolated spawn testing

Open `scenes/test_scenes/resource_respawn_lab.tscn` and run that scene in a Godot debug build (F6). Select Clay, Wood, Reed or Water; **Add Test Worker** hires a fixture worker with fixture-only money; **Deplete** empties only that lab's six-unit test deposit; **Finish Timer (Debug)** completes only that timer without advancing the game calendar. The panel shows the remaining game time. **Save Debug** and **Continue Debug** use `user://debug_resource_respawn_lab/`; the ordinary authored-city checkpoint is not the lab's save slot. The six units and fixture money are test data and do not define gameplay balance. Returning to the normal game requires exiting the test scene.

## Save compatibility

The worksite sub-schema is now version 6. A checkpoint made while a deposit is waiting stores the selected deadline; repeated Continue does not reroll it. Existing stock, including old amounts above the new test capacities, legacy straw, worker assignments, City Storage and already-earned pending output are preserved. Since an older empty deposit does not record when it was exhausted, migration conservatively schedules it for three game days after its saved clock. New site identities missing from an older checkpoint start at their specified temporary origins. Validation is staged before applying any data, and loading does not rewrite the old file. For checkpoints close to the 8 MiB limit, the writer can use equivalent compact JSON while preserving the size and safe-write checks.

A version-6 worksite checkpoint is not expected to load in the older build. Keep a separate copy of any real save when reviewing a new build; the isolated tests use disposable profiles and a player-save sentinel.

## Evidence and limitations

- Rendered review captures: [debug timer](evidence/timed-resource-sites-2026-11-05/lab-pending.png), [depleted-site inspector](evidence/timed-resource-sites-2026-11-05/inspector-waiting.png), [temporary southern sites](evidence/timed-resource-sites-2026-11-05/temporary-sites-south.png), and [gate route survey](evidence/timed-resource-sites-2026-11-05/south-gate-route-probe.png). The debug capture uses fixture stock and a manually completed timer.
- `FiniteResourceSitesTest` covers manual and worker output ownership, a contested last unit, delay and pause, save/load, legacy pending output, a full City Storage receipt, subsequent exactly-once delivery and replacement sites.
- `TimedSiteMigrationTest` covers legacy empty stock, old 240-unit stock, old straw, new marker defaults, a corrupted timer and repeated migration. `HaulerSaveMigrationTest` exercises a near-limit old document and compact writing.
- The lab is exercised in four separate processes: write, repeated Continue, worker arrival after another Continue, and all four selector types. A sentinel verifies the ordinary player-save path stays untouched.
- `ReviewResourcePathsTest` walks to all nine temporary markers and their fixture pickups through the south opening and checks both worker entries. The walk is an automated, map-aware route; it does not establish human discoverability or that the visual wall blocks physics.
- `CitySaveTest`, the three `ReviewDefaultSaveTest` phases, `NoStockpileFlow` write/read/verify, storage transport write/read and home write/read, transport interruption/contract expiry and extension, multi-worker navigation and city-supply write/read, transition and modal pause, `WorldLifeAnimationTest`, `WorkerWorkAnimationTest` and `WorkerCartAnimationTest` passed. The palm animation remains one right and one left excursion over five seconds followed by a five-second pause; the lower trunk remains fixed. The second world-life effect is the resident/worker footstep puff.
- The accelerated needs/material journey recovered all three residents, bought/deposited their clothing using earned trade income, gathered the available worksite materials, purchased 20 stone by day 25 and continued its checkpoint in a separate process. This driver moves the player to interaction range; it is not a no-teleport walking playthrough or a human usability test.
- A separate automated `WalkedCityJourney` used movement input, earned supplies and no teleport or material grants. In this single sample all three residents recovered, a worker was hired and renewed once, and the workshop was built on day 22 after approximately 87,321 pixels of walking. Idle time was accelerated one normal game-minute signal at a time. A new process continued the sleep checkpoint and put a Clay/legacy Straw/Water batch into the workshop through the UI. This is an existence test, not a claim about minimum completion time, discoverability or satisfactory balance; the run harvested 882 dates by its last checkpoint and merits playtest review.
- Automated and graphics tests used Godot **4.6.3** with software OpenGL; the project targets Godot 4.5.x. A laptop test on the intended version and human visual acceptance remain necessary. Test fixtures for near-full saves, transport, timing and workers are explicitly isolated and do not constitute a no-grants playthrough.
