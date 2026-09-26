# City Storage physical access and shared stock

> Historical checkpoint: later on 2026-09-20 the Game Director replaced the withdrawable
> city-stock rule with permanent city ownership. See `city-storage-ownership.md` for the
> deposit-only follow-up. Withdrawal descriptions and checks below describe the earlier build.

Updated: 2026-09-20
Branch: `feature/workers/city-storage-supply`
Baseline: `4de7d05` (merged content PR #104)
Starting tree: dirty, containing the earlier local City Storage supply implementation.
Scope: Level 2, explicitly approved physical access, removal of remote transfers, and storage of all items as withdrawable goods.
Status: PASSED - NEEDS HUMAN REVIEW. Local changes only; no commit, push, PR, or merge.

## Resulting behavior

Player Inventory -> walk to City Storage Area2D -> E -> Deposit/Withdraw.

The new `YSortWorld/Worksites/CityStorageArea` is located at local `(0, -96)`, between
Storage A and Storage B. The reusable scene has an editable Sprite2D, RectangleShape2D,
label, and existing E interaction prompt. It uses the existing storage building art.
The two worksite delivery destinations retain their existing behavior.

- Opening the menu and confirming a transfer both require the player inside the access area.
- Live position is checked as well as physical overlap, including while the game is paused.
- Leaving the area, a scene transition, or removing the area closes its modal.
- Back/Close restore the previous movement and pause state. E/Escape step back through the flow.
- Deposit/Withdraw use the Workshop quantity dialog: left +1, right -1, Shift x10, Ctrl x50.
- Clear removes staged quantities. Back/Close cancel without changing either store.
- Changes to Inventory or city stock invalidate stale staged selection.
- An overweight or insufficient-stock batch is rejected without moving any items.

All registered Inventory items can be deposited as physical stock, including food,
clothing, resources, equipment, and shekels. Food/clothing are no longer converted into
CityStockManager supply points by this flow. The former Inventory Send option and its
right-click deposit hookup are removed; Use and Drop retain their existing behavior.

Worker Hub retains Status, Tools, and Level. Selecting a worker equipment slot opens
City Storage for Equip/Unequip only, with worker/slot context, categories, and owner details.
It has no Deposit/Withdraw controls or standalone City Storage tab. The physical access
menu and equipment picker reuse the same storage-panel scene and the same stock provider.
Equipped units are excluded from withdrawal until unequipped through the existing rules.

## Storage and integration contracts

CityToolStorage owns one set of stock: unique Cart, Basic Glove, and Stone Hammer units
with worker allocation, plus counted stacks for other registered items. Complete mixed
batches validate before committing Inventory, units, and stacks. Successful transactions
notify Inventory and City Storage observers once each, after the final state is installed.
Invalid, insufficient, reentrant, and overweight requests leave all stores unchanged.

Content uses the existing WorkStateRuntime host, retaining items, unit IDs, and allocation
through home/city scene changes in the same game session. This is not disk persistence.
Worksite assignments, hauling progress, worksite stock, and output remain scene-local.
No autoload, project settings, plugins, item weight, or worker rules were changed by this revision.
Cart and glove weights remain TBD; Stone Hammer retains its existing 3.0 weight.

Existing citizen supply-point consumption remains separate. Automatic feeding/clothing
of citizens from physical City Storage stacks is not implemented in this task. Depositing
physical goods does not replenish the old abstract food/clothing supply counters.

## Manual review

Run `res://scenes/test_scenes/clay_worksite_test/test_scene_city_storage_supply_playtest.tscn`
with F6. This isolated acquisition fixture adds two carts, a glove, a hammer, three clay,
two bread, and one clothing item to Inventory and places the player just south of the area.
Production content receives none of those item grants.

1. Walk north into the City Storage area and press E.
2. Deposit a mix of food, clothing, clay, and equipment; try Clear/Back before confirming.
3. Check that exact quantities appear in stock. Withdraw some goods back to Inventory.
4. Close the area menu. Press K, choose Belum under Tools, and select Tool.
5. Confirm there are no Deposit/Withdraw buttons, then equip a cart.
6. Return to the area. Withdraw lists only the spare cart, not the equipped one.
7. Unequip through Worker Hub, then withdraw that cart through the area.
8. Open an Inventory item menu and confirm only Use/Drop are displayed.

## Validation on September 20

Godot 4.5.1, 400 x 225 logical viewport / 1200 x 675 desktop window:

- Main scene launch: no new script errors after the final UI edits.
- WorkerControlTest: PASSED. Existing worker rules, slots, and actions remain intact.
- WorkshopUIRegressionTest: PASSED. Existing resource-only Workshop transfers remain intact.
- ContentWorksitesIntegrationTest: PASSED. Existing worksite assignment, hauling, and delivery remain intact.
- CityToolSupplyTest: PASSED. Expanded mixed-item atomicity, free equipment exclusion,
  food/clothing without point conversion, capacity failures, and reentrant requests.
- CityStorageAreaVisualCheck: PASSED. Real content scene, physical E interaction,
  all-item deposit, equipment allocation, free-stock withdrawal, repeated confirmation,
  movement/pause restoration, and inventory menu removal.
- CityStorageSupplyFlowTest: PASSED in the root session. Covers real viewport E/Escape input, distant access rejection, mixed transfers, stale selection invalidation, Clear/cancel, capacity rejection, repeated confirmation, live-position rejection, physical stack and equipment retention through home/city changes, equipment withdrawal exclusion, Inventory Send removal, transition-lock preservation, area deletion, and temporary signal cleanup.

Visual inspection confirmed the area location, category/grid layout, transfer controls,
worker equipment picker without transfer buttons, and Inventory Use/Drop menu.
Evidence: `C:/Users/Hendro/.codex/visualizations/2026/09/13/01a09d21-3741-7360-9bd0-e04ff7988583/city-storage-area/`.
Root-session logs: `C:/Users/Hendro/AppData/Local/Temp/tip-city-storage-area-20260920/`.

The first root parse run exposed an accidental over-removal while extracting the old
Worker Hub transfer controller. The affected file was rebuilt from the exact pre-edit
snapshot, then main launch, WorkerControl, and integration checks passed. No unrelated
local edits were reverted. Existing certificate-store, graphical shader-cache, and
shutdown resource diagnostics remain; they do not mark these tests as failures.

## Changed files for this revision

- `scenes/storage_destination/city_storage_area.gd`, `.tscn`: physical access and interaction lifecycle.
- `scenes/storage_destination/city_storage_access_ui.gd`, `.tscn`: area-owned stock browsing and quantity transfers.
- `scenes/storage_destination/city_tool_storage.gd`: mixed physical stacks and allocated equipment.
- `scenes/storage_destination/city_storage.tscn`: reusable panel with Back; area-only actions are added by its controller.
- `scenes/content_scene/worksites/content_worksites.gd`, `.tscn`: area placement and provider wiring.
- `scenes/player/player.gd`: route E interaction to the physical access point.
- `scenes/test_scenes/ui_sandbox/worker_control/worker_control.gd`: remove remote transfer controller.
- `scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.gd`: remove remote transfer wiring.
- `scenes/ui/inventory_ui/inventory_ui.gd`: remove Send and right-click city conversion.
- `scenes/ui/item_transfer_ui/item_transfer_ui.gd`: explicit all-category mode; Workshop default remains Resource.
- `scenes/test_scenes/clay_worksite_test/test_scene_city_tool_supply.gd`, `test_scene_city_storage_supply_flow.gd`, and `test_scene_city_storage_supply_playtest.gd`: regression and F6 coverage.
- `ARCHITECTURE.md` and this report: final responsibilities, behavior, evidence, and limits.

Earlier local equipment resources and worker integration changes remain in the same branch.
## Review and remaining limits

- Automated PC checks and screenshots do not replace human gameplay/Android touch review.
- Physical inventory, allocation, and scene-switch retention are tested; restart/save-load retention is not implemented.
- No citizen economy, consumption order, conversion rate, or warehouse capacity rule was invented.
- Changes stay on the existing feature branch. Human Game Director retains merge approval.
