# Merchant main-map loop and greeting — 2026-10-04

Status: PASSED — NEEDS HUMAN REVIEW for the implemented interactions and first-income route. Full zero-capital workshop progression and final economy balance remain PARTIAL. Baseline: 7b169c6. User approved proceeding with the recommended main-map integration, active-needs playtest, brief greeting and branch review. No merge performed.

## Changes

- ContentScene reuses the existing five-site component (Clay, Wood, Reed, Straw, Water) under the existing WorkerRuntime path, retaining Worker Hub and city equipment ownership. No personal goods, money or hired workers are seeded.
- Main-map and home Player now use normal needs. The existing home interior, SleepSpot, door transition and Nightmare are connected so recovery/collapse have their existing destinations. Main-map placements fit the authored land without changing tiles.
- Opt-in main-map resource stock continuity lives on the existing runtime host for this running session: depleted natural stocks on the same day, stockpiles and uncollected ground output survive trips home. New-day natural replenishment retains the existing rule. This is not disk saving. Daily work/hauling schedules still have their pre-existing scene-local lifetime and stop on unload; active NPC route continuity is not implemented here.
- Merchant greeting uses the existing dialogue resource/balloon flow with Trade and Leave. It names the requested goods and evening departure, appears once per actual visit, survives view reload and resets on the next visit. Trade opens only after dialogue ends; Leave/access loss clean up movement and clock restrictions. The merchant instance adjusts the reused artwork and response positions to fit 400x225; the shared balloon scene is unchanged.
- No resource rates, hunger/fatigue drain rates, prices, production costs, quotas, tiers or food supply were changed.

## Measured first income, no grants

Godot 4.5.2 main-map harness, actual starting conditions (day 0 at 10:00, 50% energy, empty Inventory). The harness invokes the real work inspector/session, real door scene transitions and SleepSpot. Travel is teleported; time advances deterministically. The sale uses the authoritative merchant state API; separate access tests exercise actual E and trade UI. These results measure resource/time accounting, not human movement difficulty or an optimal route.

| Stage | Game time | Energy | Hunger | Inventory |
| --- | --- | ---: | ---: | --- |
| Start | Day 0, 10:00 | 50% | 0% | Empty |
| Wood work, first 3h | Day 0, 13:00 | 41% | 18% | 4 wood |
| Wood work, another 3h | Day 0, 16:00 | 32% | 36% | 7 wood |
| Existing 7h sleep | Day 0, 23:00 | 79.45% | 78% | 7 wood |
| Wait for first arrival | Day 1, 08:00 | 52.45% | 100% | 7 wood |
| Sell the six-log quota | Day 1, 08:00 | 52.45% | 100% | 12 Shekel, 1 wood |

The remaining log cannot be sold once the request is filled. Returning home does not reset the wallet/quota. First capital is reachable without grants; raw wood alone yields at most 12 Shekel per visit under current configuration. This does not establish full-game difficulty. Hunger reaches its cap before the first sale and reduces later recovery/focus. Food sourcing and multi-day progression need a separate design decision; this task does not invent food grants or alter drain rates. The previous funded production fixture still passes (100 starting Shekel, prebuilt facilities; one brick batch earns net 35). It is explicitly not evidence that a fresh player can build and operate that chain comfortably.

## Validation

Eleven headless regression scenes passed with no script/runtime errors: MerchantMainMapLoop, TravelingMerchantGreeting, TravelingMerchantAccess, TravelingMerchantProduction, PlayerEnergyOutput, PlotCollapseHandoff, WorkshopPlotAccess, MainMapWorkerHub, MainMapHaulerStart, WorksiteIncome (main audit), TravelingMerchant.

The new main-map loop also verifies same-day natural depletion after sleeping, normal needs across home transitions, stockpile and uncollected-output conservation across another round trip, and retained merchant quota/wallet. It gathers its persistence-check water normally; the test transfers earned inventory to stockpile/ground through fixture calls solely to exercise storage continuity.

Final graphical checks at the normal 1200x675 window / 400x225 logical viewport passed for main-map loop, greeting, trade access, hiring/equipment, plot access and collapse handoff after the map placement correction. Greeting was rerun after the local layout fix, with assertions that artwork and both responses fit the viewport. Screenshots inspected: main map, full greeting text, response choices. Only the expected virtual-display VSync warning appeared. Windows hands-on and Android not tested. No disk-save compatibility claim.

Earlier report statements that main-map worksites are absent and needs are disabled describe the previous checkpoint and are superseded by this report.

## UI follow-up — 2026-10-04

Per the Game Director's screenshot feedback, the merchant greeting now uses the balloon artwork at its native 176x60 logical size instead of 352x120 (scale 1 instead of 2); its text and Trade/Leave choices are correspondingly smaller. Quantity's internal LineEdit explicitly uses font size 6. SpinBox's native up/down texture is composed from the existing left/right arrow assets rotated clockwise, preserving native input and stepping behavior. No shared theme/balloon or economy rules changed. Greeting and merchant-access graphical regressions passed at the normal 1200x675 window / 400x225 viewport, and all three relevant screenshots were inspected. Only the expected VSync warning remains.

A second UI follow-up hides the quantity caret without removing keyboard editing, adds a four-logical-pixel gap between the native SpinBox arrows, and positions the greeting above the NPC. Speaker bounds now use MerchantVisual only, excluding the balloon's own animated progress icon, with no downward dialogue offset. Greeting and access graphical regressions passed again; screenshots confirm above-NPC placement and spaced arrows. No shared dialogue code changed.

The next screenshot-directed refinement removes merchant quantity tooltips and native arrow backgrounds in normal/hover/pressed/disabled states. Greeting copy is now a natural welcome without naming requested goods, with two logical pixels of additional line separation. Import and both graphical greeting/access regressions passed; greeting and quantity-arrow hover captures were inspected. The old copy-specific test assertion was removed; dialogue choice/lifecycle coverage remains intact.

Latest interaction revision: every merchant interaction now starts with the existing natural greeting and Trade/Leave choices, including after closing a trade, choosing Leave, or recreating the merchant view. Removed the obsolete per-visit greeting flag/API. Removed the entire departure-status row from the transaction panel, closing the layout gap; actual arrival/departure rules are unchanged. Graphical greeting, access and production regressions passed, with repeated-dialogue scenarios updated and trade fixtures selecting the real Trade response. The transaction screenshot was inspected. This supersedes the earlier once-per-visit greeting description.

Wallet direction follow-up: the transaction header now uses font size 12. A noninteractive 8x8 project arrow between player/trader balances points right in Buy and left in Sell, refreshing with the active mode. Merchant-access graphical regression passed; Buy and Sell screenshots were inspected at 400x225 logical resolution.

Footer revision supersedes the wallet-arrow addition: removed the money-flow arrow and animated top-right close icon. Added Back at bottom left and moved Buy/Sell to the same footer at bottom right, both 48x16 logical pixels. Back closes the transaction panel immediately through the existing close path. Quantity up/down controls are unchanged. Graphical access regression passed with Buy/Sell screenshots inspected; the updated repeated-open regression also passes using Back followed by Escape closures, verifying movement-lock release and node cleanup.
