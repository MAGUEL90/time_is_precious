# Contract renewal range — 2026-10-31

Baseline: `faee87071db245550e2e0159389c0c0452485a0c` on `fix/ui/fire-worker-feedback-20261031`.

The Contract panel replaces the two-line expiry note with a single `Day …` range and the existing right-arrow icon. The existing checklist asset marks the selected 3D, 6D, or 9D button, with a reserved icon slot so the buttons do not resize. The panel minimum is 104 × 84 logical pixels, down from 104 × 96. The range slots reserve the widest date across the available durations; the price label similarly reserves the widest existing quote so a change in price digits cannot shift the panel or arrow.

The left day is the existing contract's exclusive expiry day. The right day mirrors `WorkerDatabase.renew_contract`: an active contract extends its current paid-through day, while an expired or unpaid contract starts a new term on the current game day. New contracts expire on the day after their inclusive paid-through day. For example, an active contract expiring on Day 4 previews Day 7, 10, or 13 for 3D, 6D, or 9D. If that contract already expired and is renewed on Day 9, the respective new expiry days are 13, 16, and 19. A missing historical expiry or a renewal beyond the supported maximum displays `Day -` for the unavailable side. Legacy contracts retain their existing 08:00 boundary before renewal; a renewed contract uses the existing 07:00 boundary.

Only presentation and fixture tests changed. Contract durations, pricing, payment, expiry rules, and save data are unchanged. The original user screenshot was reviewed by the parent session; the existing assets and actual local game renders were inspected here.

## Verification

All tests used Godot 4.5.1 and isolated profiles. Rendered checks used 400 × 225 logical pixels and a 1200 × 675 window.

- **PASS:** Rendered `test_scene_worker_renew_currency.tscn`, including mouse and keyboard selection, one visible selector, close/reopen without charge, insufficient funds, repeated selection, and a single confirmed renewal. Controlled cases compare each 3D/6D/9D preview to the resulting expiry after an actual renewal for active, expired, unpaid, and legacy contracts. They cover the 07:00/08:00 boundaries, Day 9 → 12, Day 99 → 108, the maximum supported day, large prices, and stable label/arrow/button geometry.
- **PASS:** `test_scene_prepaid_contracts.tscn` headless, including existing payroll and supported-day boundaries.
- **PASS:** `test_scene_worker_control.tscn` headless.
- **PASS:** Rendered `test_scene_worker_fire_hover.tscn`, which checks Fire click feedback and confirmation.
- **PASS:** Rendered `test_scene_content_prepaid_ui.tscn` for the Job Board flow.
- **PASS:** `git diff --check`.

The first range-geometry run exposed a panel shift for very long valid prices; price width is now reserved and the final run passed. A separate early assertion also compared the layout before and after an existing error message disappeared; it was corrected to compare duration choices under the same feedback state.

These are controlled fixtures, not a complete human playthrough. Windows and Android were not tested. Linux software rendering reported that changing V-Sync mode is unsupported. Render captures were inspected locally and are not included in the commit.
