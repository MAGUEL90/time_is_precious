# Weightless Shekel — 2026-10-04

Explicit user direction: money must not have inventory weight.

Set the shared Shekel item weight from 0.01 to 0.0. Inventory weight and merchant capacity/Max calculations now use zero for currency. Updated Inventory.try_add_item to accept valid zero-weight items while rejecting negative item weights; a full bag can receive Shekel. Other item weights, capacity, prices, and transaction rules are unchanged.

Godot 4.5.2 headless checks all passed:
- TravelingMerchantTest: large currency balances weigh zero, purchasing clay fills a two-unit bag exactly, another clay is rejected, currency can be received in the full bag, and selling clay frees all weight.
- TravelingMerchantAccessTest: Max now permits eight clay when carrying twenty dry bricks and two clay; nine is rejected. Funds, stock, and UI states still pass.
- TravelingMerchantProductionTest: three production cycles and buyback/resale pass.
- git diff --check: passed.

Earlier reports describing coin weight record the previous behavior and are superseded by this change. No Windows-specific visual test was needed for this data/capacity change.
