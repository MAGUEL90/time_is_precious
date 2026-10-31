# Worker Hub Fire feedback position — 2026-10-31

Baseline: `bcf42945f8eb0bef9f991d14b86e7484b1f67f01` on `fix/ui/fire-worker-feedback-20261031`. The starting working tree was clean. This revision does not include a PR or merge.

The disabled Fire hover reason is centered in a reserved footer inside the bottom of Worker Hub. The footer leaves space for the scrolling worker list; it is present while a disabled Fire action can show its reason. The reason disappears on hover exit, roster/state refresh, worker or tab changes, Manage close, and Hub close. Font, warning color, and hover-only behavior remain unchanged. The Manage buttons, Contract, prices, save data, and gameplay rules are unchanged.

## Screenshots

- [Worker Hub with “Working now”](evidence/worker-hub-fire-feedback-2026-10-31/working.png).
- [Long roster scrolled to its last worker](evidence/worker-hub-fire-feedback-2026-10-31/dense-roster-bottom.png).

These are controlled UI fixtures rendered in Godot 4.5.1 at 400 × 225 logical pixels with a 1200 × 675 window. The dense roster intentionally repeats a valid game name to exercise scrolling.

## Verification

- **PASS:** Rendered `test_scene_worker_fire_hover.tscn`: actual mouse hover, all five existing reasons and fallback, UI font size/color, no text outline, popup close, state refresh, worker/tab/Hub changes, long roster and viewport edges. The enabled Fire action and cancellation remain available.
- **PASS:** Headless `test_scene_worker_control.tscn`, including bottom-of-Hub feedback bounds and existing Worker Hub behavior.
- **PASS:** Rendered `test_scene_worker_renew_currency.tscn` for the nearby Contract and renewal flow.
- **NOT RUN:** Windows and Android. Linux software rendering reported that changing V-Sync mode is unsupported.
