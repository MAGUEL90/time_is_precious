# Physical City Storage food and daily needs

Date: 2026-09-20; final review: 2026-09-21
Branch: `feature/workers/city-storage-supply`
Baseline: `4de7d0521648712b277851b9b6ec90ea07772fab`
Starting tree: dirty, including the preceding deposit-only and inbound-hauling checkpoints.
Status: PASSED — NEEDS HUMAN REVIEW

## Authority and scope

The Game Director authorized connecting food-point availability, unique recipient counts,
daily-need totals and days-of-food display to physical City Storage. The follow-up decision
explicitly selected ready-to-eat food only, low-point food first, with unused points retained
as portions for later days. Raw ingredients stay available for production. This authorizes
the affected food-system integration (Level 3) and that bounded design decision (Level 4).
Current per-item values and one point per person per day remain unchanged.

Root retains architecture and final review. Narrow delegated units cover city food accounting,
read-only presentation and regression fixtures. Required project controls were read. Runtime
reasoning-tier changes are not available to this session; no escalation is claimed.

Source scope: `city_tool_storage.gd`, `citizen_needs_manager.gd`, food readiness in
`immigration_manager.gd`, `city_storage_access_ui.gd/.tscn`, and the existing legacy
`gameplay_hud.gd` food display. Relevant test fixtures and `ARCHITECTURE.md`, `ROADMAP.md`,
`docs/game-concept.md` document and validate the approved behavior.

No new autoload, project setting, resource balance, player hunger change, clothing rule,
shelter rule, migration/save schema, workshop ownership route, asset deletion/rename,
governance change, commit, push or merge. Existing abstract food counters are not silently
converted into city items; they cease being the source for daily food/status/immigration.

## Implementation contract

- Ready food uses the existing CONSUMABLE category and positive `food_supply_value`.
- City availability equals usable whole-item points plus previously prepared portions.
  Depositing food preserves whole items; only consumption opens items into portions.
- Consume retained portions first, then whole foods by increasing point value (item ID
  breaks ties). Deduct only required points, preserve surplus by source item ID, and commit
  atomically under the existing transfer guard. Personal Inventory and city equipment are
  untouched; no return to personal ownership is introduced.
- Daily recipients are residents plus legacy workers with no linked citizen. Linked workers
  consume through their citizen record, and duplicate identities are counted once. Preserve
  existing resident-first shortage priority, one point/day, and midnight scheduling.
- Daily processing and food processing reject duplicate/reentrant calls on the same day.
- Summary and display use the same recipients and physical stock. No recipients means no
  daily requirement, not division by zero or unlimited goods.
- City physical stock/portions retain the existing runtime lifetime across home/city visits.
  Disk saving and cross-location workshop food ownership remain outside this checkpoint.

## Changed files in this checkpoint

Modified production code:
- `scenes/storage_destination/city_tool_storage.gd`: physical food totals, deterministic
  whole-item consumption, retained portions, atomic/reentrant and integer-overflow guards.
- `scripts/autoload/citizen_needs_manager/citizen_needs_manager.gd`: shared recipient totals,
  one daily food transaction, fulfilled/unfulfilled counts and per-day guards.
- `scripts/autoload/immigration_manager/immigration_manager.gd`: read food readiness from
  physical stock and the same daily requirement; existing chance constants are unchanged.
- `scenes/storage_destination/city_storage_access_ui.gd/.tscn`: separate food summary card,
  refresh/disconnect wiring, prepared-food empty state and wrapping for long values.
- `scenes/ui/gameplay_hud/gameplay_hud.gd`: legacy food status reads the same summary.

Modified fixtures: `scenes/test_scenes/test_scene_worker.gd` seeds physical bread;
`scenes/test_scenes/population_employment_integration_test.gd` verifies physical consumption
without double-feeding linked workers or changing the obsolete food counter.

Created three test scenes/scripts under `scenes/test_scenes/clay_worksite_test/`:
`test_scene_city_food_stock`, `test_scene_city_food_daily`, `test_scene_city_food_ui`
(each has `.gd`, `.gd.uid`, `.tscn`). Updated `ARCHITECTURE.md`, `ROADMAP.md` and
`docs/game-concept.md`; created this report. No file deletion or rename.
The access UI files were already untracked from the preceding checkpoint; they were
extended rather than recreated. Other pre-existing dirty files remain outside this step.

## Verification results

Root used Godot 4.5.1 with isolated TEMP `APPDATA`/`LOCALAPPDATA`. All eleven regression
suites below passed. Logs are under `%TEMP%/tip-city-food-20260920/qa/`:

| Gate | Evidence directory | Result |
| --- | --- | --- |
| CityFoodStockTest: ready-food filter, conservation, small-value ordering, retained portions, rejected requests, overflow and reentrancy | `stock-final/run.log` | PASSED |
| CityFoodDailyTest: unique recipients, linked/dismissed/legacy/alias cases, resident-first shortages, no-provider read-only summary, duplicate-day guards and actual multi-day time advance | `daily-final/run.log` | PASSED |
| CityFoodUITest: actual Area2D + E, deposit/receipt refresh, open/close listeners, midnight, home/city retention, no demand, shortage, long values and no-return | `render/run-final-long.log` and `.stderr.log` | PASSED, GL Compatibility |
| PopulationEmploymentIntegrationTest | `population-final/run.log` | PASSED |
| CityStorageSupplyFlowTest | `city-access/run.log` | PASSED |
| CityStorageHaulingTest | `hauling/run.log` | PASSED |
| CityToolSupplyTest | `backend-regression/run.log` | PASSED |
| ContentWorksitesIntegrationTest | `content-regression/run.log` | PASSED |
| WorkerControlTest | `worker-regression/run.log` | PASSED |
| ConditionHUDRegressionTest | `condition/run.log` | PASSED |
| MudbrickProductionChainIntegrationTest | `production-chain/run.log` | PASSED |
| Project editor/parse, `--headless --editor --quit-after 120` | `parse-final-retry/run.log` | Exit 0, no script/parse errors |
| Main launch, `--headless --quit-after 90` | `main-final/run.log` | Exit 0 |
| Worker fixture launch, `--headless ...test_scene_worker.tscn --quit-after 60` | `worker-fixture/run.log` | Exit 0; launch only |

The UI was rendered at 400 x 225 logical / 1200 x 675 window and visually inspected.
Evidence is under `C:/Users/Hendro/.codex/visualizations/2026/09/13/01a09d21-3741-7360-9bd0-e04ff7988583/city-storage-food/`:
`city-food-available.png`, `city-food-portions.png`, `city-food-no-demand.png`,
`city-food-shortage.png`, `city-food-long-value.png`. Food status preserves the existing
fifteen-slot grid; zero demand and long numbers remain readable. No Android/export claim.

Root reviewed the delegated production changes against pre-edit snapshots and the actual
new tests. The initial duplicated test provider was rejected and replaced by the real
CityToolStorage. Root simplified arithmetic to checked native integer operations, corrected
compact-menu clipping, and validated the final implementations. `git diff --check` passed.

### Failed attempts and diagnostic limits

- Initial daily/population tests failed due incorrect test fixtures: whole bread had been
  represented as retained portions and expected totals did not match item quantities.
  Corrected tests use real physical stock and pass; original logs remain under `daily/`
  and `population/`.
- One delegated SupplyFlow attempt crashed with native signal 11 before any test output.
  Its output was captured by the tool, without a separate log file. Root's isolated
  SupplyFlow run passed.
- Root's `--headless --editor --quit` attempt also crashed with signal 11 after editor
  layout initialization (`parse-final/run.log`, exit -1073741819). A bounded editor run
  with `--quit-after 120` passed, as did the final game/UI runs. The native crash cause is
  not established; these results do not claim an engine-crash fix.
- The interactive `work_state_smoke_test.tscn` was initially launched as though automated;
  it waits for input and was cancelled. It is not counted as passed. The automated
  MudbrickProductionChainIntegrationTest supplies the relevant production regression.
- Runs still report the existing root-certificate warning and ObjectDB shutdown leaks
  (15 resources for runtime, 16 for editor). No new blocking script errors were observed.

## Human manual review - 2026-09-21

The Game Director confirmed that all points in the manual City Storage checklist worked:
physical access and deposit, one bread increasing available food by one point, cancellation
without stock changes, no player Withdraw or Inventory Send-to-City option, and reopening
with correct stock and readable food status. This confirms that UI/deposit checklist only;
manual midnight/retained-portion behavior and final merge approval are not implied.

Follow-up design question: the Game Director expected food, clothing, gold/money and tools,
and asked why raw materials were also accepted. The Game Director then approved limiting both
player and Hauler intake to ready food, finished clothing, Shekel and supported worker
equipment. See `city-storage-item-filter.md` for that subsequent implementation and QA;
the earlier food tests above describe the pre-filter checkpoint.

## Remaining work and human review

The existing F6 `test_scene_city_storage_supply_playtest.tscn` gives the player two bread
items for trying deposit and the food summary in the actual content scene. Whole food
stays an item until consumed. One roasted drumstick is two points: with one recipient,
midnight removes that item and keeps one point as a prepared portion; the following day
uses the portion. Automated tests cover this two-day path and leaving/returning to the city.

This is runtime state only. Full-game save/load must eventually serialize city items,
portions, recipient/world time and processed-day markers consistently. Save compatibility,
restarting the game with preserved stock, Android, and a long manual play session are untested.
Physical clothing supply, cross-location workshop ownership/routing, mixed-owner production,
city capacity and initial workshop construction remain the separate pending roadmap work.
Root reviewed the new immigration food query; a separate random immigration balance test
was not added and existing probability constants were not changed.

No commit, push, PR or merge was performed. Final merge authority stays with the Game Director.
Root snapshots/logs: `%TEMP%/tip-city-food-20260920/`; delegated snapshots additionally use
`%TEMP%/tip-city-food-stock-backup-20260920/`,
`%TEMP%/tip-city-food-ui-pre-edit-20260920-01/`, and
`%TEMP%/tip-city-food-20260920/qa/daily-agent/snapshot-before-edit/`.
