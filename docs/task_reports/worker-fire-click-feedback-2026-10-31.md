# Worker Fire click feedback — 2026-10-31

Baseline: `0194dd42b389c99c31ae9335b9a137658ff5a8c8` on `fix/ui/fire-worker-feedback-20261031`. The starting working tree was clean.

Fire retains its disabled appearance when unavailable. A left click on it shows the current reason in the existing red, size-6 footer inside Worker Hub; hover alone does not show it. The message stays visible when the pointer leaves, and clears when Manage or Worker Hub closes, the selected worker or tab changes, or the roster is refreshed. Repeated blocked clicks reuse the same label. An allowed Fire click still opens the existing confirmation, and current worker eligibility is rechecked at the time of the click.

## Test setup

These are controlled UI fixtures, not a normal playthrough. Tests were rendered in Godot 4.5.1 at 400 × 225 logical pixels with a 1200 × 675 window. The mouse pointer is moved through the display server; click events are injected through the Godot viewport.

## Verification

- **PASS:** Rendered `test_scene_worker_fire_hover.tscn`, updated for click behavior: hover and right-click do not show the warning; left-click shows the correct reason for five blocked states and a fallback. Repeated clicks do not fire the worker or duplicate the label. Tests also cover state changes before a click, refresh, worker/tab/Hub changes, long rosters, frame boundaries, and allowed Fire confirmation/cancellation.
- **PASS:** Headless `test_scene_worker_control.tscn`, including the Worker Hub and Fire flows.
- **PASS:** Rendered `test_scene_worker_renew_currency.tscn` for the nearby Contract and renewal flow.
- **NOT RUN:** Windows and Android. Linux software rendering reported that changing V-Sync mode is unsupported.
