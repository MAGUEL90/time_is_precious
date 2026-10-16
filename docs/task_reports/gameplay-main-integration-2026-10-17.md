# Gameplay/main integration — 2026-10-17

Status: PASSED — NEEDS HUMAN REVIEW. No merge into main or force-push.

## Baselines and authority

- Working branch: `fix/gameplay-hud/ui-consistency`, started clean at `8a183d6`.
- Main: `01fde83` (Food MVP PR #111).
- Common ancestor: `83a67f3`.
- Warehouse PR #113 is already merged into gameplay.
- Hauling test commit `fc25e09` was still separate on GitHub; it is now included
  through a normal merge, preserving its history.
- Risk: LEVEL 2 integration. User requested conflict resolution and testing before
  a human merge, then explicitly chose the latest city layout plus six date palms.

The final PR is the complete accumulated gameplay branch, not just this conflict
repair. It brings the existing raid/wall, progression, checkpoint/startup, UI and
warehouse work to main. Portrait-capture development is not a dependency.

## Resolution

Four files conflicted when bringing main into gameplay:

- `ROADMAP.md`: retain both feature histories and qualify old-map evidence.
- `content_scene.tscn`: retain gameplay terrain, walls, buildings, warehouse and
  startup wiring. Restore all six authored palm identities and relocate their
  views/pickups onto the newer land. Palm 4 was moved away from the merchant's E
  approach after regression testing caught pickup priority interference.
- `time_debug_overlay.gd`: retain both raid and date controls, without restoring
  tooltips removed by the later gameplay UI decision.
- `inventory_ui.gd`: preserve the newer no-tooltip UI and wallet while retaining
  main's node-bound feedback tween fix. Removed hover callbacks must not return
  with references to the removed item-info panel.

Main's committed merchant translation entry is retained. This is inherited Git
content, not reconstruction of the unpublished laptop edits. Editor-generated
translation/import changes were reverted. The laptop-only wall TileSet metadata,
portrait files, balance values and checkpoint schema were not changed.

## Integration defect found and fixed

Palm spawners and personal inventory drops both place PickUpItem views directly
under YSortWorld. The old save scanner therefore captured palm views as personal
drops and recreated them during home/city handoff. Save and sleep regressions
caught this immediately after adding the palms.

Palm views now carry the `date_palm_pickups` group. City-drop capture and restore
exclude those views, leaving their existing session ledger in charge. No save
fields, version numbers, file paths, item values or refill rates changed. Save and
sleep tests now assert exactly eighteen palm views in addition to the independently
saved Clay drop. The date-access test checks all eighteen pickups for authored
land, collision-free approach, actual E collection and movement restoration.

## Validation

Official Godot 4.5.1, cloud Linux. 29 unique suites reached PASS/PASSED and exit 0:

- WarehouseTest
- CitySaveValuesTest, CitySaveFileTest, CitySaveTest, CitySaveEconomyTest,
  CitySleepSaveTest, StartMenuTest
- InventoryFeedbackLifecycleTest, StatusTabTest, InventoryModalPauseTest
- DatePickupTest, DateRespawnTest, DateTreeDuplicateTest, DatePickupAccessTest
- RaidRegressionTest, RaidCompositionRegressionTest, RaidRecoveryRegressionTest,
  CityProgressionTest
- CityStorageHaulingTest, CityToolSupplyTest, StorageDestinationTest,
  CityStorageOverflowTest, CityStorageMaterialConsumptionTest,
  CityStorageSupplyFlowTest, ClayWorksiteHaulerTest, HaulerDeliverySetupTest,
  ResourceWorksitesTest, CityStorageRankedRaidLootTest
- TravelingMerchantAccessTest

Additional modes passed: city checkpoint write/read in separate processes; home
checkpoint write/read in separate processes; startup Continue for city/home;
empty and corrupt-checkpoint startup. Invalid/checkpoint-change warnings are
intentional negative cases. An initial home-menu runner used a checkpoint already
cleaned up by the preceding read test and timed out; writing a fresh fixture before
Continue corrected the test ordering. This was not counted as a pass.

Editor import/parse and bounded default startup completed. WarehouseTest also
passed under Xorg/Mesa llvmpipe at the unchanged 400x225 viewport/1200x675 window.
The virtual driver emits its unsupported V-Sync warning. Final runtime checks
have no unexpected errors or ObjectDB/retained-resource diagnostics. An initial
capture overlapped the MCP port used by another test; final graphical runs were
serialized. Diff/whitespace and ancestry checks passed.

Headless command: `Godot_v4.5.1-stable_linux.x86_64 --headless --path . res://scenes/test_scenes/<scene>.tscn`.
Hauler demos use `TIP_TEST_HAULER=1` and `TIP_TEST_HAULER_TARGET=1`.
Save modes use `-- --city-save-phase=write/read`, `-- --sleep-save-phase=write/read`,
and `-- --menu-mode=empty/city/home/corrupt` as appropriate. XDG data/config/cache
are isolated under `/tmp/tip-integration`.

## Limits

- Palm stock, missing pickup slots, refill timers and RNG remain session-only,
  as in main's Food MVP. Disk saves retain collected Inventory dates but do not
  restore palm depletion after a process restart. Full food/save persistence needs
  a separately specified compatibility extension; this merge does not claim it.
- Old 72-hour walking balance evidence belongs to the old layout. New checks cover
  access and ownership, not a new full survival/balance playthrough.
- Windows, Android, physical GPU, human pacing and visual acceptance are unverified.
- This PR includes the accumulated gameplay changes relative to main; review the
  whole PR before merging. No content/portrait branch is merged.

## Visual evidence

[City overview](evidence/gameplay-main-2026-10-17/city-overview.png) uses a test-only
zoomed-out camera with HUD hidden to show all six trees; production camera settings
are untouched. [Warehouse access](evidence/gameplay-main-2026-10-17/warehouse-world.png),
[storage menu](evidence/gameplay-main-2026-10-17/warehouse-storage.png), and
[rear occlusion](evidence/gameplay-main-2026-10-17/warehouse-behind.png) use the normal view.
