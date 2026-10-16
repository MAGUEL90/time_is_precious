# City Storage hauling policy regression

- Date: 2026-10-16 (Asia/Jakarta)
- Branch: `test/inventory/city-storage-hauling-policy`
- Baseline: `d901018f0fca495d4ca70e671cfde0e4defb01e2`, also the fetched
  `fix/gameplay-hud/ui-consistency` head.
- Starting tree: clean. Risk: LEVEL 1, tests only.
- Status: PASSED — NEEDS HUMAN REVIEW.

## Scope and evidence

Reproduced the five obsolete Wood Log rejection assertions on the baseline using
Godot 4.5.1. The existing provider already accepts Wood Log and Stone as wall
materials. Updated the hauling fixture and the provider acceptance catalog to
reflect those two exceptions. The resource-worksites regression exposed one more
obsolete Wood rejection; it now explicitly permits Wood while retaining the
Reed/Straw/Water rejection checks.

The hauling fixture now runs the existing full/partial delivery, closed-endpoint
return/retry, committed receipt conservation, target/XP and repeated-tick checks
for bread, Wood Log and Stone. Added wall-material personal deposit accounting,
direct cargo delivery and empty-cargo replay checks, no-withdrawal checks, and
atomic mixed wall-material/Clay rejection including stock, units, portions,
sequence and notifications. Existing forbidden-item pre-pickup rejection, stale
Clay cargo return, UI rejection and Storage A/B coverage remain active.

Changed scripts:
- `scenes/test_scenes/clay_worksite_test/test_scene_city_storage_hauling.gd`
- `scenes/test_scenes/clay_worksite_test/test_scene_city_tool_supply.gd`
- `scenes/test_scenes/resource_worksites_test.gd`

No gameplay, capacity, economy, balance, save schema, warehouse, portrait/content,
project settings or wall asset changes. Editor-generated translation/import edits
were reverted to the clean baseline; the unpublished laptop edits were not used.

## Validation

Cloud Linux, official Godot `4.5.1.stable.official.f62fdbde1`, headless. Each suite
below reached its named PASS/PASSED result and exited 0 with no error, warning,
ObjectDB leak or retained-resource diagnostics in its final run:

- CityStorageHaulingTest
- CityToolSupplyTest
- StorageDestinationTest
- CityStorageOverflowTest
- CityStorageMaterialConsumptionTest
- CityStorageSupplyFlowTest
- ClayWorksiteHaulerTest (`TIP_TEST_HAULER=1`)
- HaulerDeliverySetupTest (`TIP_TEST_HAULER_TARGET=1`)
- ResourceWorksitesTest
- CityStorageRankedRaidLootTest

Invocation: `Godot_v4.5.1-stable_linux.x86_64 --headless --path . res://scenes/test_scenes/<scene>.tscn`.
Editor import/parse with `--headless --editor --import --quit` and a bounded default
startup check with `--headless --quit-after 60` also completed cleanly. The startup
check is not a completed gameplay playthrough. `git diff --check` passed.

Initial sandbox runs could not bind the existing MCP loopback listener. Final
checks used cloud network permission and completed without those errors; no addon
or project setting was changed. XDG data/config/cache directories were isolated
under `/tmp/tip-qa`.

Visual/manual playtests, laptop/Windows/Android behavior and disk-save round trips
were not tested. These tests use the preserved worksite fixture and do not assert
that warehouse visuals or a city-to-workshop supply route exist. No PR or merge is
part of this change; any later PR should target the verified gameplay lineage.
