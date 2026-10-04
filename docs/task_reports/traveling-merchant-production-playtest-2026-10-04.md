# Traveling merchant production playtest — 2026-10-04

Tested gameplay baseline: `bf19f859453154e086555a290e3e9037cf5f8b80`.
Engine: Godot 4.5.2, headless. All three executed scenes passed, exit 0; logs contained no ERROR, WARNING, or FAIL entries.

## Scope and conditions

New reproducible scene: `res://scenes/test_scenes/test_scene_traveling_merchant_production.tscn`.
Run using Godot `--headless --audio-driver Dummy --path <repo> <scene>`.

This tests the operating loop using the actual merchant UI/controller, workshop menus, inventory transfers, WorkManager, ProcessManager, fee payment, and stock withdrawal. It is an isolated integration fixture, not a fresh-save or human mouse playthrough. Existing workshop UI helpers drive buttons; the player is teleported between interaction areas. Infrastructure (workshop, level-one drying yard, Laborer) and 100 starting Shekel are supplied. All initial raw supplies from the shared fixture are cleared before measurement; workshop storage starts empty. Every production input is bought from the merchant; no output is seeded.

Clock starts day 1 at 08:00. Automatic ticking is disabled and actual production is advanced by 30 minutes for shaping and 10 for drying. Weather is clear; worker satisfaction 0.5/reliability 0.9 and fixed RNG seed 42 make success reproducible. Player needs are disabled. Measured time excludes travel and menu browsing. Infrastructure, daily wages, survival costs, variable weather, and production failure are not included in the operating margin.

## First batch: observed balances

| Stage | Player Shekel | Merchant Shekel | Goods |
| --- | ---: | ---: | --- |
| Start | 100 | 120 | No player materials |
| Buy inputs | 82 | 138 | 3 clay + 3 straw + 3 water |
| Shape and pay fee | 77 | 138 | 20 wet bricks released in workshop |
| Dry, pay fee, withdraw | 75 | 138 | 20 dry bricks in personal inventory |
| Sell all output | 135 | 78 | 20 dry bricks in merchant stock |

Inputs cost 18; shaping fee 5; drying fee 2. Total operating cost 25, sale proceeds 60, operating surplus 35 Shekel per fully sold successful batch. Game clock reaches 08:40.

## Repeated production and finite merchant budget

| After selling | Time | Player Shekel | Merchant Shekel | Player dry bricks | Merchant dry bricks |
| --- | --- | ---: | ---: | ---: | ---: |
| Batch 1 | 08:40 | 135 | 78 | 0 | 20 |
| Batch 2 | 09:20 | 170 | 36 | 0 | 40 |
| Batch 3, partial sale | 10:00 | 199 | 0 | 2 | 58 |

Third-batch inputs raise merchant funds from 36 to 54. Selling 20 bricks for 60 is rejected with inventory, stock, and balances unchanged. Selling 18 for 54 succeeds. The remaining two bricks stay with the player. The merchant still holds three each of clay, straw, and water: buying power is the bottleneck before raw stock runs out in this scenario.

Buyback also passed through the UI: one sold brick costs the player 6, then reselling it pays 3. After that round trip player balance is 196, merchant balance 3, and item counts return to two and 58. No profit from simple buy/resell at these prices.

## Additional executed regression scenes

- `test_scene_traveling_merchant.tscn`: PASS. Schedule boundaries, missed visits, rewind/repeat snapshots, finite stock and funds, atomic exchanges, reentrant rejection, capacity including coin weight, invalid quantities, and integer-overflow rejection.
- `test_scene_traveling_merchant_access.tscn`: PASS. Real ContentScene access, UI buy/sell, movement locks, map reload ledger retention, repeated open/close, scheduled departure, stale requests, next-visit reset, and transition/range closure.
- `test_scene_traveling_merchant_production.tscn`: PASS. Three full production batches, fees and cancellation checks, withdrawals, sales, insufficient-budget rejection, partial sale, and buyback spread.

No gameplay or balance values were changed. This run does not assess visual pixel quality or Windows-specific behavior. It also does not establish that a new player can bootstrap the economy without test supplies: the starting-capital/resource route remains a separate design gap. The measured +35 is an operating surplus under controlled success conditions, not a final balance recommendation or lifetime profit after construction costs.
