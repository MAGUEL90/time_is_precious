# Content scene: worksite integration

Date: 2026-09-13
Branch: `codex/content-worksites`
Base: `1a2e41ab6707e5816cf8472d4e39d194c596678d` (merged worker/worksite MVP, PR #103)
Status: PASSED — NEEDS HUMAN REVIEW (scene-local content playtest scope)
Scope: content branch and limited integration of existing approved worksite behavior.

## Implementation

- `content_scene.tscn` instances `worksites/content_worksites.tscn` under `YSortWorld/Worksites`. Ground tiles, object atlas, player, home entrance, authored pickups, workshop, HUD and human UI edits remain in place.
- The content adapter extends the existing worksite controller and instances the existing inspector/Worker Hub scenes. It uses the map's Player and InventoryUI; no second player, HUD or prototype grid is added.
- The base controller now exposes Player/InventoryUI NodePaths and converts output world positions into GroundOutput-local coordinates. Default paths keep standalone fixtures compatible.
- Clay Site A/B and Storage A/B occupy the open area east of the current workshop. Site markers, footprint polygons, labels, departure markers and stockpiles are authored scene nodes. No TileSet or atlas is edited.
- Existing manual gathering, Daily assignment, Worker Progress, equipment locks, cart requirement, commute/cart animations, repeated hauling trips, one destination per Hauler, accepted-item daily target, and XP/productive-days calculation are reused without balance changes.
- Worksite E yields to an existing map interactable. Worker Hub/time shortcuts are blocked during inventory, other modal pauses, manual work, sleep, collapse, or scene transition.
- Direct component F6 initially exposed missing external Player/InventoryUI paths. The adapter now opens the real content map as its standalone preview, with processing disabled until valid dependencies exist. Embedded components with incorrect paths stop with one configuration error instead of repeated null-access errors. The base controller also removes its unused local and uses explicit hour conversion for the reported integer-division warnings.

## Content editing and playtest

1. Run `scenes/content_scene/content_scene.tscn` with F6 (also the current F5 main scene). F6 directly on the reusable `content_worksites.tscn` component automatically opens this map as its preview; it does not try to create a second Player. Walk east from the current player spawn; E near a clay site opens its inspector. K opens Worker Hub.
2. In Worker Hub / Tools, select Belum, open Tool, and equip Cart from City Storage. Naram is the existing Laborer. Equipment supply is a clearly scoped content playtest seed, not a new purchase/deposit economy.
3. At a site, choose Worker, assign Naram and Belum, select Storage A **or** Storage B and daily item target, press Next, then Start Work. Assignments begin the next day. Worker Progress appears for a committed assignment.
4. Optional time controls in debug builds: F7 adds 30 minutes; F advances to tomorrow 06:45. These retain real player condition costs in content. For accelerated worker-only testing, the existing Player `debug_disable_player_needs` Inspector setting can be enabled temporarily; it is not enabled by this integration.
5. Edit placement at `content_scene/YSortWorld/Worksites`; open `content_worksites.tscn` for individual site/storage/spawn positions. Keep node names stable while wiring assignments. Each stockpile instance uses the reusable `StorageDestination` endpoint and a small capacity backend (96 clay by default). A future real warehouse can replace the backend via `storage_path`.
6. Inspector options on Worksites: `seed_playtest_equipment`, `seed_playtest_hauler`, and `enable_time_shortcuts` can be disabled when authoring normal content. Firing Belum does not immediately respawn him on scene reentry.

## Current boundary

This is a scene-local content playtest. Worksite assignments, partial progress, ground output, equipment allocation, and stockpile quantities reset when the content scene is unloaded or the game stops. It does **not** load/write the isolated prototype's `user://worksite_mvp/save_v1.json`. That codec replaces shared clock/worker/inventory state and does not cover workshop/game state; enabling it on content without a wider save contract would be incorrect. The user was asked whether to expand save scope; until that choice is made, playtest mode is the stated assumption.

Worker travel remains the MVP's straight-line motion. The authored placement provides open paths; obstacle navigation is not added here. Stockpile visuals remain simple placeholders. The helper backend is separate from Worker Hub equipment supply, preserving the distinction between a delivery destination and City Storage equipment management.

## Validation

Godot 4.5.1 import and main-scene launch passed without new script/parse errors. Root visually inspected the map, Status, Tools, site inspector, active 3-item cart trip, accepted 20-item target, and direct-component F6 preview using Godot viewport captures.

Passed checks:

- Existing regression scenes: `HaulerDeliverySetupTest`, `WorkerControlTest`, `ClayWorksiteDailyTest`, `WorksiteCommuteTest`, `StorageDestinationTest`, `MudbrickProductionChainIntegrationTest`, `WorkshopUIRegressionTest`, `ClayWorksiteGatheringTest`, and `ClayWorksiteInspectionTest`.
- `ContentWorksitesIntegrationTest`: one shared Player/HUD/InventoryUI, moved-site and moved-output-parent world coordinates, focused map interactable priority, modal/time-key guards, cart requirement, next-day work, deliveries `[3, 3, 3, 3, 3, 3, 2]`, exact accepted quantity/XP/productive days, Worker Progress, and Go To without Player/camera movement.
- `ContentDirectF6PreviewTest`: loading the component directly resolves to the actual content map with one Player and valid Player/InventoryUI bindings. Both direct-component and main-scene launches passed.
- Diff and snapshot comparison: original TileMap data is byte-for-byte unchanged, existing apple pickup and unrelated local edits/deletions are preserved. Atlas audit independently confirmed 82 object tiles, 30 colliders and 75 y-sort origins. `git diff --check` passed.

QA evidence: `C:/Users/Hendro/AppData/Local/Temp/tip-content-worksites-20260913-154003/` contains baseline snapshots, viewport PNGs, test logs/results, and preservation checks. Save persistence across content/home transitions is not implemented or claimed by these tests.

Known environment/baseline diagnostics: certificate-store read error and ObjectDB/resource warnings at shutdown. These also occur on the unchanged starting content scene and remain unresolved; logs are retained in the task's temporary QA folder.

## Ownership

Astra Medium: branch/base verification, runtime/scene integration, world-coordinate fix, save-scope decision, visual review, final tests and diff review.
Luna XHigh: static TileSet audit/guide and initial bounded content integration test. Astra reviewed and corrected the test's identifiers, time horizon, active-worker Go To case, and coordinate/input assertions before executing it.
