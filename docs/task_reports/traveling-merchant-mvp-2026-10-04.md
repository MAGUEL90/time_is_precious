# Traveling merchant MVP — 2026-10-04

Status: PASSED — NEEDS HUMAN REVIEW (unmerged feature branch).

## Scope contract and authorization

- Objective: implement the Game Director's requested common traveling merchant as
  the first personal Shekel trading route; defer quest NPCs and Rare visitors.
- Branch: `feature/economy/traveling-merchant-mvp`.
- Baseline: `cc05bcf33ebede11747c7c1a58a77a1935d0ef51` (PR #109).
- Starting checkout: clean; already tracking its matching remote branch.
- Risk: LEVEL 2 — LIMITED INTEGRATION of explicitly approved economy behavior.
- Explicit choices in this task: first arrival day 1, every three game days,
  08:00–18:00; provisional stock, budget and prices allowed for playtest. Future
  arrival rules must consider city statistics, which are not implemented yet.
- Protected integration: one merchant instance in ContentScene and a two-line
  Player E-routing branch. Existing autoload registrations, production recipes,
  world clock rules, player conditions, economy data, canon, dialogue and project
  settings are unchanged. The new runtime is a child of existing WorkStateRuntime.
- No new external dependencies, no deleted/renamed files, no main merge.

## Implemented behavior

A common merchant appears at the authored stop east of the starting player. The
existing worker/cart visual is reused as MVP presentation. An always-visible notice
shows the next arrival (including Tomorrow) or today's departure time. The actor
appears/disappears at the stop; route-walking animation is not part of this MVP.

Approach and press E to open BUY/SELL. The panel shows both wallets, stock or owned
quantity, unit prices, quantity and total. Transactions use only personal Inventory:
workshop goods must first be legitimately paid for and withdrawn. City-owned stock
and held workshop output cannot be sold through this menu. World time continues
while browsing; the menu closes on departure, range loss, collapse or transition.
Only the merchant's movement lock is released when it closes.

Both parties' money and goods change atomically after stock, funds, overflow and
final carry-weight checks, including the weight of Shekel. A rejected trade changes
nothing. Player purchases fund the merchant; sales consume that same finite wallet.
Purchased goods become merchant stock and can be bought back at the posted spread.
No fee, commission or additional economic rule is hidden in the transaction.

Visit state survives UI reopen and map reload in this run. It resets once on the
next scheduled arrival. Clock snapshots, missed windows and rewinds cannot refill a
visit. This is runtime continuity, not disk saving.

## Provisional playtest configuration

`resources/traveling_merchant/common_merchant.tres` owns all values below; existing
ItemData base prices are not changed. Prices are from the player's perspective.
The starting merchant wallet is 120 Shekel per visit.

| Item | Arrival stock | Player buys for | Player sells for |
| --- | ---: | ---: | ---: |
| Clay Lump | 12 | 2 | 1 |
| Straw Bundle | 12 | 2 | 1 |
| Water Jar | 12 | 2 | 1 |
| Wood Log | 8 | 4 | 2 |
| Stone Hammer | 2 | 15 | 5 |
| Sun Dried Mudbrick | 0 | 6 | 3 |

These are test values, not final balance. Buying three each of clay/straw/water
costs 18; twenty finished bricks sell for 60 before existing production fees and
worker costs. This is a transaction example, not proof of whole-loop profitability.

## Validation

Godot `4.5.2.stable.official.6ce3de25a`, existing GL Compatibility settings.

- Editor import/parse succeeds.
- `test_scene_traveling_merchant`: PASS — time boundaries, skipped visits, single
  refill, rewind resistance, buy/sell conservation, missing stock/funds/items,
  invalid item/quantity, integer overflow, net exchange weight, catalog copy
  isolation and signals observing committed balances; reentrant inventory-signal
  trades are rejected.
- `test_scene_traveling_merchant_access`: PASS headless and graphical — real E,
  Buy/Sell controls, map reload, repeated open/close with no leftover menu nodes,
  selection stability on time snapshots, shortcut blocking, departure, stale UI
  request, other movement locks, range loss, scene transition and scene unloading.
  Window bounds include long balances. Actual sale of personally held workshop
  output raises Shekel.
- Existing nearby suites PASS: WorkshopPlotAccessTest, DebugProductionFlowTest,
  CityStorageOverflowTest, PlayerActionLocksTest, ClockStateBroadcastTest.
- Main scene bounded launch succeeds; branch whitespace/diff checked.
- Graphical access suite ran at the project 1200x675 window / 400x225 logical
  viewport on Xorg/Mesa llvmpipe. Arrival, buying, selling, sold-out and long-wallet
  captures were inspected. Contrast and SpinBox font were repaired after review.
- Accepted graphical run uses Dummy audio. The virtual driver's unsupported V-Sync
  warning remains; no script errors or ObjectDB/retained-resource warnings occurred
  in accepted tests. A first graphical attempt fell back from unavailable ALSA.

## Playtest steps

1. Run the normal project on this branch. The current clock starts on day 0 at
   10:00; the notice announces the first merchant for tomorrow. Existing Debug
   `+1d` reaches day 1 at 10:00, inside the first visit, without changing the schedule.
2. Go east of the starting player to the merchant/cart and press E.
3. For a funded purchase check, use the existing explicit Debug Shekel top-up;
   buy materials, close/reopen, and confirm both stock and wallets persist.
4. Produce/dry bricks using the existing workshop flow, pay/withdraw them to
   personal Inventory, and sell them. Confirm player Shekel rises and merchant
   funds fall. The dedicated tests supply their own inventory fixtures.
5. Advance to 18:00: the merchant and open menu leave. The next arrival is day 4.

## Remaining limits

Normal startup income/material acquisition, full-city economy, city statistics,
Rare tiers, customer quests, disk save/load, physical route navigation, new merchant
art, Android and long-session/hardware playtesting remain outside this checkpoint.
No starting grant was added: a new game's empty inventory still needs the separate
startup-economy design or explicit debug setup for production playtests. Final
prices, presentation and merge require the Game Director's review.

## File inventory

- New: `resources/traveling_merchant/common_merchant.tres`.
- New: `scenes/traveling_merchant/` config, ledger and world adapter/scene.
- New: `scenes/ui/traveling_merchant_ui/` menu script/scene.
- New: two `test_scene_traveling_merchant*` test script/scene pairs (with script UIDs).
- Modified: `scenes/content_scene/content_scene.tscn`, `scenes/player/player.gd`.
- Documentation: this report, ROADMAP, ARCHITECTURE, root branch map.
- DEVLOG remains merged-history only; no unmerged milestone was added there.
