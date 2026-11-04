# Direct worksite output to City Storage

> Follow-up: [City transport and player-funded construction](city-transport-and-player-construction-2026-11-04.md)
> supersedes this report's implementation-status statements about inter-storage
> hauling, defense payments, and the city checkpoint schema. The baseline
> investigation and worksite migration evidence below remain historical.

Status: branch implementation; requires integration and human review. Baseline
`13a6c0725a08c91bfcbc2606646e8ebf0f668968`, clean isolated cloud checkout.
Branch: `feature/inventory/direct-worksite-city-supply-20261104`. Risk: system
and persistence change, explicitly requested by the Game Director on 2026-11-04.

## Direction and implementation

The Game Director directed that worksite output go straight to City Storage, the
city store be large for now, construction materials come from the player, and
Haulers be used only between storage locations. This branch interprets worksite
output as the Daily **worker** output. Player manual gathering keeps its existing
personal-bag and overflow pickup behavior, so the player can still obtain material
for the initial workshop and house. That interpretation should be reviewed during
integration. The existing workshop and house construction states already consume
personal Inventory; this branch does not change their costs or durations.

The current City Storage has no weight or slot cap, only integer-overflow checks;
that already supplies a large temporary store without changing, capping, or deleting
any old stock. A dedicated atomic receipt accepts the authored Daily worksite item,
including raw materials, without expanding the player-deposit or cargo filters.
The real City Storage UI displays the resulting items through its normal stock view.
The scheduler keeps a refused receipt under the worksite job and retries every game
minute, even after the shift. If its last worker leaves, the existing pending-output
ledger retains it. Synchronous receipt observers cannot withdraw/start a job during
settlement and duplicate already-credited goods.

New Hauler assignments at worksites remain disabled, including to City Storage.
Pre-existing in-flight trips retain the migration's final-delivery/recovery behavior.
This branch does **not** implement a storage-to-storage job or a Hauler hiring UI:
the current map has one city-owned storage, while workshop stock is personally
withdrawable and lacks city-owned lots. A route requires an actual second endpoint,
ownership-aware withdrawal/production, a player-facing assignment flow, and saved
cargo state. Enabling transfers now would permit city-owned goods to become player
property. The existing wall/Watchtower uses City Storage materials; the house and
workshop plots use personal Inventory. The broader phrase “building materials from
the player” needs a decision for those city defenses before claiming it applies to
all construction systems.

## Save compatibility

New city checkpoints are v15 with worksite snapshot v4. Earlier versions remain
readable when their authored locations still match. Existing ground piles, equipment,
city stock and in-flight legacy cargo remain at their previous owners. In a v14-or-
earlier worksite snapshot, already completed but undelivered units were formerly
player-pickable; staged migration places those units as separate player-pickable
world piles instead of converting them to city property. Reed uses the retained city
navigation geometry to find a reachable location, including during a home visit.
Continue does not rewrite the old file; the next successful explicit save keeps the
previous bytes as the existing `.bak`. New v15 rejected receipts remain pending at
the worksite and survive a fresh-process Continue.

The earlier map's displaced worker approach targets are still rejected safely,
without modifying the original file or live game. Migration regressions exercise
Hauler behavior using a separate synthetic checkpoint copy that clears only that
unrelated old-map approach; they independently assert rejection of the unmodified
fixture. This preserves the existing no-guessed-relocation rule.

## Baseline failures and fixture updates

The three requested suites were reproduced failing at the original baseline with
Godot 4.5.2. Their affected assertions were outdated:

- Warehouse and supply tests used the former Hauler delivery point for player E
  access; the current access area is the front board. The warehouse still checks
  collision, repeated E/open/close, no rear access, and unmodified stock.
- The supply UI has intentionally retained its quantity dialog after deposit since
  the prepaid-storage UI change. The test now asserts one transfer, empty selection,
  disabled repeat confirmation, retained pause, and explicit return to the menu.
- City Storage hauling and resource-worksite fixtures assumed that new worksite
  Hauler assignments were enabled. Tests first verify the current rejection, then
  opt only the isolated old-map fixture into the historical behavior to retain
  destination filters, target, source/cargo/stock conservation, and recovery checks.
- `ContentActualArrival` also failed on baseline because its direct clock jumps
  left the otherwise idle workshop/process time cursors stale. Its test setup now
  synchronizes those cursors, and the physical-arrival checks pass unchanged.

The new direct-output flow is tested using real New Game, paid hiring, the worksite
assignment UI, physical worker arrival, City Storage, a full-stack failure, Save,
Continue, retry, separate-process Continue, home handoff, and player construction
ownership. Synthetic resource receipts also exercise all five authored worksite
items. The baseline failed receipt and player deposit do not grant duplicate items,
XP or signal notifications.

## Validation and limits

Cloud Linux, official Godot 4.5.2, headless, fixed 60 fps, with isolated XDG data,
config and cache roots. A fresh editor import and bounded default startup both exited
successfully without script errors. Targeted suites cover CityStorageSupplyFlowTest,
WarehouseTest, CityStorageHaulingTest, CityStorageOverflowTest,
CityStorageMaterialConsumptionTest, CityToolSupplyTest, CityFoodStockTest,
CityFoodDailyTest, CityClothingNeedsTest, StorageDestinationTest,
ClayWorksiteGatheringTest, ClayWorksiteHaulerTest, ResourceWorksitesTest,
WorkshopConstructionTest, worksite resignation, transaction guards, CitySave,
CitySaveFile, CitySaveValues, CitySaveEconomy, sleep save, house save/migration,
legacy pickup, and the three-process `test_scene_no_stockpile_flow.tscn`.
Ten stockpile migration cases cover idle/outbound/returning cargo, resignation,
City Storage rejection, repeated save/load and legacy pickup. Historical fixture
adaptations use verified synthetic copies. The four-process no-Hauler Job Board,
three-process multi-day needs journey, six multi-house migration cases, worksite
midnight Continue, raid/raid recovery/composition and ranked loot also passed.

`InitialWorkshopStartTest` still fails two assertions about completion under one
paid contract and the resulting roster; the identical two assertions fail on the
unmodified `13a6c07` baseline. Its older fixture predates the current shift and
contract behavior. It was not counted as passed or changed to mask the failure.
The separately scoped workshop construction, shift/resignation and multi-day needs
tests passed.

This is an automated development checkpoint, not a complete unassisted playthrough.
No graphical or human Windows/Android playtest was performed. The unimplemented
storage-to-storage route and the city-defense material-source question above remain
open and must not be represented as complete. This session could not independently
verify or change its reasoning tier; the parent remains responsible for the
cross-system and save-migration review before integration.
