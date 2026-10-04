# Merchant complete playtest — 2026-10-04

Scope: merchant-only verification requested by the Game Director. Gameplay baseline 14f7fb1. No gameplay or balance changes. Extended the existing main-map test from direct-state sale to E interaction, real greeting/Trade response, Sell Max, confirmation, Back, repeat dialogue, Buy, buyback and quota checks.

## Method and boundaries

Automated Godot 4.5.2 playtest, not a manual Windows session. Main-map route begins with empty inventory and normal conditions; no debug funds, materials or protection. Work uses the existing inspector/session, and clock progression includes existing sleep/wait. Walking is teleported and time ticks are deterministic, so this does not measure player navigation or real-world pacing. Merchant entry uses E; dialogue responses and panel buttons use their actual UI signals. Separate edge-case fixtures deliberately set balances/stock/capacity to test boundaries.

## Complete earned-money route — PASS

| Action | Player Shekel | Trader Shekel | Player goods |
| --- | ---: | ---: | --- |
| Gather wood for 6 game hours, reach day 1 at 08:00 | 0 | 120 | 7 wood |
| E → greeting → Trade → Sell → Max → Sell 6 wood | 12 | 108 | 1 wood |
| Back → E → greeting → Trade → buy 2 clay at 2 each | 8 | 112 | 1 wood, 2 clay |
| Buy back 1 wood at 4 | 4 | 116 | 2 wood, 2 clay |
| Switch to Sell after buyback | 4 | 116 | Unchanged; request fulfilled, Sell/Max disabled |

Trader wood stock: 8 → 14 → 13. Clay stock: 12 → 10. Wood demand: 6 → 0 and remains 0 after buyback. Total currency remains 120 throughout. No duplicate goods or negative balances. Subsequent map round trips retain trader budget, exhausted quota and player coins.

## Additional merchant checks — PASS

- Greeting: Trade and Leave, repeated interaction in the same visit, view recreation, later visits and access-loss cleanup.
- Access/UI: physical E range, inventory shortcut exclusion, Back/Escape cleanup, repeated open/close without extra nodes, moving out of range, scene transition closure.
- Departure: day 1 at 18:00 hides merchant and closes open trading; stale requests cannot transact. Next scheduled visit restores the configured budget.
- Transaction limits: finite stock, finite trader funds, requested-goods restriction, exhausted demand, player funds, inventory capacity and Max selection. Rejected trades preserve inventory/balance/stock.
- State: same-visit continuity, time rewind safeguards, no duplicate reentrant settlement, zero-weight currency.
- Production fixture: existing funded/prebuilt brick batch and buyback rejection still pass; this separate fixture is not the fresh-start route above.

Five suites passed: MerchantMainMapLoop, TravelingMerchantAccess, TravelingMerchantGreeting, TravelingMerchant, TravelingMerchantProduction. No script/runtime errors or warnings in headless runs. The extended complete route also passed graphically at 1200x675 / 400x225 logical resolution. Sale, purchase and exhausted-quota screenshots inspected; only the known virtual-display VSync warning appeared. No merchant defects found in these scenarios; this is not a claim that every possible input/platform was tested.
