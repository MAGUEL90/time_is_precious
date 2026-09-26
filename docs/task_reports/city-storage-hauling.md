# City Storage Hauler delivery checkpoint

> Historical checkpoint: on 2026-09-21 the Game Director restricted City Storage intake
> to ready food, finished clothing, Shekel and supported worker equipment for both players
> and Haulers. Clay-to-city delivery described below is superseded. Current policy and
> verification are recorded in `city-storage-item-filter.md`.

Date: 2026-09-20
Branch: `feature/workers/city-storage-supply`
Baseline: `4de7d05`
Starting tree: dirty, including the previously validated physical-access and city-ownership changes.
Status: PASSED - NEEDS HUMAN REVIEW

## Authority and scope

The Game Director authorized the next checkpoint: connect Hauler deliveries to the same
City Storage used by player deposits and worker equipment. This is bounded Level 2 integration
of the approved storage direction. Root owns architecture, integration tests and final review;
two narrow implementation tasks cover the stock receiver and scene endpoint respectively.

Implement the existing `StorageDestination` receiver contract on `CityToolStorage` and expose
one delivery endpoint at the existing City Storage Area2D. Keep Storage A/B, their capacity
and art, the existing Hauler schedule/target/three-item cargo behavior, and the one-way city
ownership rule. City Storage currently has no capacity limit; its numeric capacity remains TBD.

Out of scope: citizen consumption, outbound City -> Workshop routing, per-location workshop
stock, inventory weight/balance, persistence/schema changes, autoloads/settings/dependencies,
governance files, commit/push/merge. Rejected cargo follows the existing return-to-worksite
behavior. Worksite jobs/cargo are still scene-local; this checkpoint does not promise saving
an in-flight route across a scene change or restart.

## Acceptance and verification

- The real content scene lists City Storage once beside the existing Storage A/B choices.
- The delivery endpoint, player area and Worker Hub use one shared runtime stock provider.
- Only cargo that reaches an accepting endpoint transfers into city stock, once; personal
  Inventory is not used as an intermediate destination and does not emit a change signal.
- Registered stack items remain physical stacks; supported equipment keeps unique unit IDs.
- Invalid/reentrant receipt fails atomically. Existing deposit, no-return and equip/release
  behavior remains intact.
- In-flight rejection counts no target/XP, retains cargo until return, and conserves goods.
- The actual Daily assignment UI can send a Hauler to City Storage with a target of 20,
  including a final two-item trip, and reports only accepted deliveries.
- Completed city stock survives a content scene reload and binds to the new endpoint.

Root will run Godot import/parse, target backend/integration tests, nearby A/B/Hauler/worker
regressions and main-scene launch with isolated TEMP user data. A rendered integration run
will verify the existing destination/progress/physical storage UI. Review incremental diffs
against pre-edit copies and preserve unrelated dirty files.

Root pre-edit documentation copies and QA logs: `%TEMP%/tip-city-hauling-20260920/`.

## Implementation and review

- `city_tool_storage.gd` now implements the existing receiver contract. It validates before
  preparing the next city state, retains equipment allocations, skips unit-ID collisions,
  and uses the existing transfer guard through the city notification. Personal Inventory
  is neither a staging area nor a notified participant in a Hauler receipt.
- `city_storage_area.gd/.tscn` adds one scene-authored `DeliveryPoint` at `(0, 12)` and binds
  its storage path during area configuration. The existing access shape, art and player
  modal behavior are retained. No changes to generic destination, Hauler or Daily logic.
- Root reviewed both delegated changes against pre-edit snapshots. The backend snapshots
  are in `%TEMP%/time_is_precious_city_haul_backend_20260920/`; endpoint snapshots are in
  `%TEMP%/tip-city-storage-endpoint-20260920/`.
- Added `test_scene_city_storage_hauling.gd/.tscn` plus its Godot-generated script UID for the
  real content-scene integration. Extended `test_scene_city_tool_supply.gd` for receipt
  validation, equipment identity, reentrancy and Inventory isolation.
- Updated `ARCHITECTURE.md` and `ROADMAP.md` to describe the actual inbound-delivery boundary
  and mark this checkpoint locally validated. Outbound ownership/save work remains pending.

## Root verification results

- Godot 4.5.1 editor import/parse: exit 0, no new blocking script errors.
- `CityToolSupplyTest`: PASSED. Registered stack/equipment receipt, existing allocation and
  unit-ID collision preservation, invalid/current-corrupt-state rejection, reentrant rejection,
  one city notification and no personal Inventory mutation. Existing deposits/no-return and
  equipment regression cases also passed.
- `CityStorageHaulingTest`: PASSED headless and in GL Compatibility at a 1200 x 675 window
  with the unchanged 400 x 225 logical viewport. Actual UI assignment selects City Storage
  beside A/B; stale destination confirmation rejects; the next-day standing plan delivers
  `[3, 3, 3, 3, 3, 3, 2]`. Rejected cargo stays on the return leg, then returns to worksite
  ground. Every gathered item is conserved. Only 20 accepted goods count toward target,
  progress and XP. A/B remain empty and personal Inventory emits no change.
- The integration test opens the physical City Storage with player E and verifies that its
  displayed stack combines two deposited clay with twenty hauled clay. Player withdrawal
  still rejects. Settled city stock/equipment survives content replacement and the new
  endpoint binds to the retained provider without duplicate destination choices.
- `CityStorageSupplyFlowTest`, `ContentWorksitesIntegrationTest`, `HaulerDeliverySetupTest`
  (`TIP_TEST_HAULER_TARGET=1`), `StorageDestinationTest` and `WorkerControlTest`: PASSED.
  The first Worker Hub invocation used a nonexistent test path; after correcting it to
  `clay_worksite_test/test_scene_worker_control.tscn`, the actual test passed. Both logs remain.
- Main-scene headless launch with `--quit-after 90`: exit 0.
- Visually inspected `city-hauler-setup.png`, `city-hauler-progress.png` and
  `city-hauler-stock.png`: the city destination/20-item target, accepted 20/20 progress,
  and combined 22-item stock fit their existing panels. No new UI layout was needed.
- Incremental source/test/documentation diffs reviewed; `git diff --check` passed. Existing
  unrelated dirty work was preserved. No asset deletion/rename, autoload, dependency,
  project-setting or save-format changes. No commit, push, PR or merge.

Known pre-existing Godot diagnostics remain: root certificate store, ObjectDB instances at
shutdown, and 15 runtime/16 editor-import resources at shutdown. No new script errors were
observed in the successful runs. Tests used isolated TEMP APPDATA/LOCALAPPDATA; real saves
were not opened. Android and human gameplay acceptance were not performed.

Visual evidence: `C:/Users/Hendro/.codex/visualizations/2026/09/13/01a09d21-3741-7360-9bd0-e04ff7988583/city-storage-hauling/`.

## Remaining boundary

City stock remains session-persistent, not disk-saved. Active worksite assignments, cargo
and ground output remain scene-local; the reload regression intentionally covers settled
city stock, not a mid-trip save/scene transition. City -> Workshop supply, workshop-local
ownership, automatic A/B onward routes and physical citizen consumption are later gates.

## Human playtest

1. Run `res://scenes/test_scenes/clay_worksite_test/test_scene_city_storage_supply_playtest.tscn`
   with F6. This existing fixture supplies personal items for testing; production content
   still grants no tools. Walk into the City Storage entrance, press E and deposit a cart.
2. Open Worker Hub, equip Belum with the deposited cart, then close the menu.
3. Open Clay Site A, choose Daily, add Naram and Belum, and choose `City Storage` with a
   target of 20 for Belum. Select Next and Start Work.
4. With menus closed, use the existing debug F shortcut for tomorrow at 06:45 and F7 to
   advance 30 minutes. Watch deliveries; Worker Progress should identify City Storage and
   stop counting at 20/20 for that day.
5. Return to the physical City Storage and press E. Hauled clay is in the same stock as
   deposited goods. The player menu offers Deposit and no Withdraw.
