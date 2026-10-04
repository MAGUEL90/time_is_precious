# Player energy-based gathering output — 2026-10-04

User continuation authorizes implementing the discussed live-energy approach for manual player worksite gathering. Baseline a52fe15. No new energy meter: normalize existing fatigue as energy = (max_fatigue - fatigue) / (max_fatigue - min_fatigue), clamped to 0..1. Provisional linear productivity: each completed minute contributes current energy productive-minutes; full items require the site's existing minutes_per_unit. Fractional progress accumulates within the session and only whole completed items are awarded. Unfinished fractions do not carry between sessions.

Energy is sampled after existing minute signals, never charged a second time. Execution uses live conditions and does not cap output to its initial forecast. A condition recovery during work can improve the yield. Selected session duration remains 3/6/9 hours unless stock runs out or an existing interruption occurs. NPC daily production, resource rates/prices, hunger/fatigue drain rates, collapse thresholds, energy drain differences between sites, and merchant quotas are unchanged.

Preview estimates fatigue over each minute without mutating state/time, stops its depletion estimate once predicted units consume stock, and exposes an estimated yield in the existing confirmation worker label (`Player | Output ~8`). Energy/satiety costs respect the debug suppression flags. Forecast is an estimate: focus-driven collapse or external condition/stock changes can alter actual results; live execution remains authoritative. No long-range hunger/focus simulator or additional condition system was introduced.

Measured clay output with normal needs enabled, starting hunger 0/focus 1:

| Starting energy | Ending energy | Minutes | Preview | Actual output |
| --- | --- | ---: | ---: | ---: |
| 100% | 91% | 180 | 17 | 17 |
| 50% | 41% | 180 | 8 | 8 |
| 25% | 16% | 180 | 3 | 3 |

Nine hours from full energy yields 46 clay, rather than 54 from locking the initial energy. Existing collapse case still stops after 25 minutes near critical fatigue; it completes zero whole items at that low productivity.

Godot 4.5.2 checks passed:
- PlayerEnergyOutputTest: three measured conditions, pure preview, exact inventory/stock conservation, no duplicate fatigue drain, fixed session duration, live mid-session recovery and depletion.
- ClayWorksiteGatheringTest: overflow, pickup, 3/9-hour sessions, UI start/reentrancy lock, early depletion, collapse.
- ClayWorksiteTeardownTest: safe cancellation/refund and no duplicate settlement.
- ClayWorksiteInspectionTest, graphical: output estimate, costs, panel layout, menu navigation and close behavior. Screenshot inspected at 400x225 logical viewport (`/tmp/tip-clay-feedback-20260907/panel.png`). Initial screenshot run lacked the required directory; final run saved successfully. Only virtual-display VSync warning remains.
- ResourceWorksitesTest and ClayWorksiteDailyTest: NPC rates, hauling, shared-site accounting unchanged.
- TravelingMerchantProductionTest: production and finite requests still pass.
- git diff --check passed.

The main ContentScene still disables player needs/fatigue and still lacks gathering markers; use the existing worksite test scenes with needs enabled to observe this mechanic. No main-map flags or layout were silently changed. Windows/manual gameplay balancing remains unverified. This is a provisional curve, not final difficulty tuning.
