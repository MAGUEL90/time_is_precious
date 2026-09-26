# City Storage supply item filter

Date: 2026-09-21
Branch: feature/workers/city-storage-supply
Baseline: 4de7d0521648712b277851b9b6ec90ea07772fab
Starting tree: dirty; previous City Storage work preserved in place.
Status: PASSED — NEEDS HUMAN REVIEW
Risk: Level 3 integration; the item-scope design change is explicitly approved (Level 4).

## Objective and authority

The Game Director approved limiting City Storage to ready food, clothing, Shekel and worker
equipment, consistently for player deposits and Hauler deliveries. Gold Nugget is raw material,
not currency. Keep this task on the existing branch. The separate workshop worktree is parked.

Root owns policy, integration, documentation and review. Narrow Luna XHigh agents update the
existing player/backend and Hauler regressions. New receipt checks must reject atomically,
preserve cargo and source stock, leave target/XP unchanged on failure, and prevent selecting
City Storage for unsupported worksite output. Storage A/B still accept their existing cargo.

## Scope and acceptance

- One provider predicate for registered ready Consumables with positive food value, existing
  finished clothing IDs, Shekel, and the three currently supported worker equipment IDs.
- Player quantity choices omit unsupported items; direct or mixed invalid requests reject
  before any quantity, unit ID or change signal is committed.
- Hauler preflight and receipt use the same policy. Clay destination selection, assignment
  and Start revalidate it. An old in-flight rejected load remains recoverable at its source.
- Old registered raw stacks already in city stock remain visible and intact. No automatic
  deletion, conversion, withdrawal, migration or disk-persistence change.
- Preserve food/portion arithmetic, clothing and treasury integration status, equip rules,
  fees, weights, capacities, output rates, schedules, targets and XP values.
- Verify accepted and rejected item classes, mixed atomicity, real transfer UI, actual
  delivery endpoint/transport, nearby food/worker/worksite regressions, parse and GL launch.

Expected production files: city_tool_storage.gd, city_storage_access_ui.gd, the shared
test_scene_clay_worksite.gd worksite adapter, and hauler_delivery_setup.gd. Existing test
fixtures and game-concept/architecture/roadmap docs are updated to the approved scope.
No new branch, production content placement, recipe, global manager, settings, addon,
save schema, control-pack edit, commit, push or merge.

Pre-edit snapshots: %TEMP%/tip-city-supply-filter-20260921-a4fab89e/before/.
The manifest records all 53 pre-existing dirty/untracked files; the initially clean Hauler
setup script was additionally snapshotted before its edit.

## Final implementation and review

- `scenes/storage_destination/city_tool_storage.gd`: `accepts_item()` is the shared intake
  rule for player listing/validation and Hauler capacity/receipt. Finished clothes use an
  explicit existing-ID list because their current resource categories are not uniform.
  Shekel is accepted explicitly; Gold Nugget is rejected. Direct tool-unit insertion also
  requires supported equipment. Existing registered raw stacks remain visible and intact.
- `scenes/storage_destination/city_storage_access_ui.gd`: short acceptance caption and
  Deposit tooltip. Existing compact layout, no-return rule and food summary are retained.
- `scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.gd`: the shared content
  adapter disables City Storage for clay, returns its reason on stale assignment, and
  revalidates at Start. Storage A/B remain valid clay destinations.
- `scenes/test_scenes/ui_sandbox/clay_worksite_inspector/hauler_delivery_setup.gd`: preserves
  destination reasons as option tooltips and displays the reason for a forced invalid choice.
- Existing regressions updated: `test_scene_city_tool_supply.gd`,
  `test_scene_city_storage_supply_flow.gd`, `test_scene_city_storage_hauling.gd`,
  `test_scene_city_food_ui.gd` (all under `scenes/test_scenes/clay_worksite_test/`).
  The F6 `test_scene_city_storage_supply_playtest.gd` additionally seeds Shekel, Gold Nugget
  and grain so a human can compare accepted and rejected stock in personal Inventory.
- `docs/game-concept.md`, `ARCHITECTURE.md`, `ROADMAP.md` record the approved policy.
  Historical ownership, hauling and food reports point to the superseding filter checkpoint.

Root inspected the actual delegated test changes and revised them before acceptance:
Hauler source quantities/counters now use shared mutable fixture state, receipt conservation
and rejection/return/retry are checked, actual assignment callbacks are exercised, and rendered
captures were restored. The personal-food check navigates the real Inventory food filter,
because the expanded raw-item fixture spans multiple inventory pages. Every engine run below
was executed by root, not inferred from a delegated completion claim.

Final scope comparison: 14 of the 53 pre-existing dirty/untracked files changed for this task;
39 match their pre-edit hashes. The initially clean Hauler setup script and this new report
are the only additional changed paths. Branch and HEAD remain at the recorded baseline.
No changes to item resources, scene placement, settings, global managers, generic hauling,
StorageDestination, save format, control pack or the parked workshop worktree in this task.

## Verification

Engine: Godot 4.5.1 stable. APPDATA/LOCALAPPDATA were isolated under each QA case directory;
no player save slot was read, overwritten or deleted. All 10 final regression runs passed:

| Regression | Result / coverage |
| --- | --- |
| CityToolSupplyTest | PASS: registered catalog, accepted classes, all raw exclusions, mixed atomic rejection, signal/quantity/unit/portion conservation, legacy stock, equipment ownership and no return |
| CityStorageSupplyFlowTest | PASS, GL: real Area2D + E, accepted deposit choices, forbidden choices absent, mixed transfer/cancel/repeated confirmation, stale access, no Send/Withdraw, equip and scene retention |
| CityStorageHaulingTest | PASS, GL: real content endpoint/provider, raw direct/pre-pickup/stale-cargo rejection, disabled/stale clay selection and Start, Storage A/B, accepted full/partial food loads, reject/return/retry, accepted-only target and XP, no duplicate and runtime retention |
| CityFoodStockTest | PASS: food-point and portion accounting |
| CityFoodDailyTest | PASS: daily consumption, recipient counts and duplicate-day guards |
| CityFoodUITest | PASS, GL: food availability/need/days, portions, shortage, long values and visible acceptance caption |
| WorkerControlTest | PASS: worker equipment/control regression |
| PopulationEmploymentIntegrationTest | PASS: citizen/worker integration regression |
| ContentWorksitesIntegrationTest | PASS: authored worksite integration |
| HaulerDeliverySetupTest | PASS with TIP_TEST_HAULER_TARGET=1: existing delivery setup and targets |

The successful food hauling test uses the existing transport module and the real City
Storage endpoint with a bounded, test-owned bread source. It does not change clay production
or add a food-production worksite. The stale raw-route case deliberately changes a test
route's destination after pickup to verify safe return without target or XP credit.

Additional gates passed: headless editor parse, GL main-scene launch, GL F6 playtest-scene
launch and `git diff --check`. Render captures were inspected at the actual 400x225 logical
viewport: accepted deposit items, raw Hauler rejection reason, combined deposited/hauled food,
and the food summary. The final caption is fully visible without resizing the existing UI.

QA logs: `%TEMP%/tip-city-supply-filter-20260921-a4fab89e/qa/`.
Final cases: `tool-supply`, `supply-flow-final`, `hauling-gl`, `food-ui-compact`,
`test_scene_city_food_stock`, `test_scene_city_food_daily`, `test_scene_worker_control`,
`population`, `content`, `hauler-setup`; launch/parse: `parse`, `main-gl`, `playtest-gl`.
Captures: `C:/Users/Hendro/.codex/visualizations/2026/09/13/01a09d21-3741-7360-9bd0-e04ff7988583/city-storage-item-filter/`.

Earlier QA findings, fixed before the final results:

- The long acceptance caption was visibly clipped. A two-line attempt failed the new
  visibility assertion; a compact one-line caption passed and was inspected visually.
- The expanded Inventory fixture put retained bread beyond page one. The Send-removal test
  initially failed to find it; navigating the actual food filter fixed the test without
  changing Inventory behavior or consuming the retained bread.

Existing shutdown diagnostics remain: ObjectDB instances leaked and 15 resources still in
use (16 in the editor parse run). No parse errors, script errors, native crash or failing
assertions occurred in the final regression runs. These shutdown warnings were not expanded
into an unrelated cleanup task.

## Human review and limits

The preceding deposit/no-return/food-summary checklist was reported working by the Game
Director. This new filter still needs a brief human playtest on the same branch:

1. F6 `test_scene_city_storage_supply_playtest.tscn`, approach City Storage and press E.
   Deposit lists bread, clothing, Shekel and the supported tools; clay, grain and Gold Nugget
   remain in personal Inventory and cannot be selected for deposit.
2. Deposit an allowed item and cancel a second selection. Verify exact quantities, no
   withdrawal and worker equipment access. Old city raw stock, if present, is retained.
3. In clay Hauler setup, City Storage is unavailable; Storage A/B remain selectable.
   Daily midnight food/portion behavior has automated coverage but its human playtest has
   not yet been explicitly confirmed in the user's report.

After that review, prepare this branch for the Game Director's merge decision. No new domain
or branch transition is authorized. Physical clothing consumption, treasury spending,
city capacity and city-to-workshop supply remain separate decisions. City stock/portions
currently persist across scenes in the running game; full restart/save persistence is not
implemented or claimed here. No commit, push, PR or merge was performed.
