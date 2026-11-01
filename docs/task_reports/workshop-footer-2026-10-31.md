# BUILD WORKSHOP footer spacing — 2026-10-31

Baseline: `b2aed1b3583277fddba7f12bd02c98a80c5ad011` on `feature/ui/worker-contract-polish-20261030`.

The content now fits within the existing 220 × 208 logical window. The visible title starts at the same vertical position as in the previous no-worker screen. Both Cancel and Build now end 16 logical pixels above the window's outer bottom in the tested states. The rendered frame begins 10 pixels above that outer bottom, leaving **6 logical pixels** of visible interior between the buttons and the frame, or 18 screen pixels at 3× scale. Previously, the no-worker buttons ended 9 logical pixels above the window's outer bottom and touched the inner edge of the frame.

Godot `4.5.1.stable.official.f62fdbde1`, X11/llvmpipe, 400 × 225 logical viewport and 1200 × 675 window, isolated XDG data:

- `workshop_label_presentation_test.tscn`: **PASS**. Checks title position, both footer buttons, no workers, eight workers, missing materials, the longest construction error, CLEAR SITE and progress layouts, scrolling, keyboard focus and keyboard Cancel without construction or inventory changes.
- `workshop_keeper_integration_test.tscn`: **PASS**, including keeper dialogue and opening/closing the actual construction menu; inherited schema-8 arrival checks also passed.
- `workshop_ui_regression_test.tscn`: **PASS**.
- Headless project launch for 180 frames: **PASS**, exit 0. This is a bounded launch check, not a full playthrough.

[Before](evidence/workshop-footer-2026-10-31/before-1200.png) · [After](evidence/workshop-footer-2026-10-31/after-1200.png) · [After, 400 × 225](evidence/workshop-footer-2026-10-31/after-400.png) · [Missing materials](evidence/workshop-footer-2026-10-31/after-missing-material-1200.png) · [Construction error](evidence/workshop-footer-2026-10-31/after-error-1200.png)

The X11 driver warned that it cannot change V-Sync mode. Windows, Android and physical GPUs were not tested.
