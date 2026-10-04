# Zero-capital worksite income — 2026-10-04

Gameplay baseline: `4f71154`. Godot 4.5.2 headless. No gameplay/balance changes.

## Important integration finding

The actual current ContentScene starts with empty Inventory and zero gathering sites: WorkerRuntime uses workshop_worker_runtime.tscn with an empty WorksiteMarkers node. Both player-needs debug flags are enabled. Runtime audit confirmed these facts. The worksite system exists in the separate content_worksites_map fixture, but the complete zero-capital worksite-to-merchant route is not currently available in the main map. The audit passing means this finding was verified, not that the main-map economy is complete.

## Method

Nine independent fresh-process scenarios, using test_scene_worksite_income.tscn and TIP_INCOME_SCENARIO: main, ClaySiteA, WoodSite, StrawSite, WaterSite, ReedSite, WaterRepeat, WaterNeeds, MixedNeeds. Starts with empty personal inventory. No money, materials, workers, or equipment added by this harness. Disable the fixture's optional seeded hauler. Manual gathering needs no hired worker. The existing fixture includes initial applicants/cart through its normal startup, neither used here.

Worksite scenarios start on day 1 at 08:00, explicitly positioned at the merchant arrival window. This does not measure waiting from a new game's clock. Invoke real session preview/execute and merchant ledger trade; MixedNeeds uses real pickup handling for overflow. Automatic clock ticking is stopped, while gathering advances actual minute signals. No walking/menu-reading time or physical merchant approach is measured. This is a service-level economic integration test, not an uninterrupted human playthrough. Merchant ledger is added to the worksite fixture for the measurement only; the fixture itself does not contain the merchant actor. There is no resource reset between batches in a scenario.

## Three-hour solo gathering, from zero Shekel

| Resource | Produced | First bag sale | Total sale value after retrieving overflow | Value/game hour |
| --- | ---: | ---: | ---: | ---: |
| Clay | 18 | 18 | 18 | 6 |
| Straw | 18 | 18 | 18 | 6 |
| Wood | 9 | 18 | 18 | 6 |
| Water | 36 | 33 | 36 | 12 |
| Reed | 24 | Rejected | 0 through this merchant | 0 |

Water weighs 3 each; capacity 100 holds 33. Three remain on the ground. MixedNeeds verified retrieving and selling those three after the first sale. Shekel has zero weight. Reed is absent from the merchant catalog, so it cannot be sold there; this is not a gathering failure.

## Repetition with active needs

WaterNeeds: two 180-minute sessions produce 72 water total; selling only bag contents earns 66 and leaves six jars on the ground. Site stock reaches zero after six hours. A third attempt is rejected as depleted and consumes no time. Needs after six hours: hunger 36%, fatigue 18%, focus 91%. No collapse or interrupted work.

MixedNeeds: same two water sessions, retrieving and selling each overflow, then 180 minutes of clay. No eating, sleep, purchased supplies, or extra money.

| Clock | Completed work | Player Shekel | Merchant Shekel |
| --- | --- | ---: | ---: |
| 08:00 | Start | 0 | 120 |
| 11:00 | Water + recovered overflow | 36 | 84 |
| 14:00 | Water + recovered overflow | 72 | 48 |
| 17:00 | Clay | 90 | 30 |

Final hunger 54%, fatigue 27%, focus approximately 86.44%; no collapse. Walking, pickups and merchant interactions have no additional clock cost in this harness, so real play takes longer and has only one nominal game hour left before departure. Gathering consumes natural stock; water cannot be repeated indefinitely that day. Raw-sales-only income is bounded by the merchant's 120 initial coins per visit; buying from him returns money to that budget. Visits are three days apart, not daily.

## Interpretation, not new balance rules

Starting money is relatively easy to obtain mechanically once sites and merchant are accessible together. Water produces twice the sale value per work hour of the other accepted raw resources. The tested route yields 90 without cash investment and without a needs interruption. Time still matters (nine game hours), and stock, carrying trips, needs, and merchant schedule constrain it. These results do not prove long-term economy difficulty or unlimited income.

One water session's first sale (33) exceeds the previously measured 25 operating cost of a successful 20-brick batch. Prior merchant-production tests measured +35 after buying inputs and paying two fees, with 40 production minutes. That comparison assumes existing infrastructure and a worker: it does not mean a new player can build and produce in 40 minutes. Workshop code requires 6 wood, 12 clay, 8 reed, 180 clearing minutes and 3 days construction for a solo builder; level-one drying yard additionally requires 2 wood, 4 reed and 4 clay. Full construction/hiring/survival from zero was not completed in this task because the actual main-map gathering route is absent. No lifetime-profit comparison or amortized construction cost is claimed.

Recommended discussion order: confirm main-map worksite placement/integration; review water's relative earning rate; decide the desired time to first meaningful purchase. Avoid reducing all raw-resource prices solely from these fixture results. No balance changes made.

## Validation and reproduction

All nine scenarios passed their assertions with exit 0; no ERROR/WARNING/FAIL in final measurement logs. Measurements retained in worksite-zero-capital-income-2026-10-04.json. Run each in a separate process:

```sh
TIP_INCOME_SCENARIO=MixedNeeds godot --headless --audio-driver Dummy --path <repo> res://scenes/test_scenes/test_scene_worksite_income.tscn
```

Limitations: no worker automation, overnight survival, travel timing, main-map worksite integration, or fresh-save construction-to-production playthrough. Main-map needs are currently disabled; active-needs runs explicitly enabled them only in the test instance.
