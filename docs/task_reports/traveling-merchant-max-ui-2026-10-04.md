# Merchant Max and compact validation — 2026-10-04

Added the approved themed Max button beside quantity. It selects the largest valid quantity within the existing 999-unit UI limit, using authoritative quotes to respect stock, both wallets, carry capacity including exchanged coins, and balance limits. It never submits a trade. The entered quantity is retained when stock or affordability changes.

Invalid trades keep their requested total visible and disable Buy/Sell. The existing message area displays one concise reason (merchant affordability, stock, coins, or bag space). Valid selections clear the warning; Max is disabled when no quantity is valid. Existing transaction-result feedback remains in the same area. No balance or backend transaction rules changed.

Godot 4.5.2 validation:
- Graphical TravelingMerchantAccessTest: PASS. Screenshot scenario with 20 bricks and 54 merchant coins shows `Merchant can afford only 18.` and total 60; Max selects 18, total 54, blank warning, enabled Sell. Asserted identical Sell rectangle before and after, and no inventory mutation from Max. Purchase tests cover stock, coin limits, capacity, and zero affordable quantity.
- TravelingMerchantTest: PASS.
- TravelingMerchantProductionTest: PASS, including three real production cycles and resale spread.
- `git diff --check`: PASS.

Captured runtime viewport images: `/tmp/merchant-max-captures/merchant-sell-invalid.png` and `/tmp/merchant-max-captures/merchant-sell-valid.png`. Both inspected: panel fits 400x225, Max fits the quantity row, warning is a single line, and the existing hover-only catalog is preserved.

Initial graphical launch found no running virtual display; restarted Xorg and captured successfully. An initial capacity-test expectation omitted two clay already carried by the fixture; corrected expected maximum to seven and verified eight is rejected. Final runs passed. Virtual-display VSync warning is driver-specific; no script/runtime errors in final runs. Windows visual validation remains manual.
