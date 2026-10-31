# Workshop labels and hover tooltips — 2026-10-31

Baseline: `efab5f8d0574b284a2d894188e2b4ae9866a79ae`, branch `feature/ui/worker-contract-polish-20261030`.

The BUILD WORKSHOP title has additional space above it, with its footer and eight-worker scroll area still inside the frame. Building names are no longer drawn above workshop plots or City Storage; the home action retains “Sleep.” Contract-expiry feedback, panel titles and E prompts remain. Runtime hover-tooltip strings found in the Job Board, Workshop Storage and Worker Hub were removed, while the accessible names retain currency and full candidate identity. Long names are still shortened visually, as before, and no longer expand on hover.

The engine used was Godot `4.5.1.stable.official.f62fdbde1`, with isolated XDG data and X11/llvmpipe at a 400 × 225 logical viewport and a 1200 × 675 window. The driver warned that V-Sync mode cannot be changed in this environment.

- `workshop_label_presentation_test.tscn`: **PASS**, including title/footer bounds, eight worker portraits and scrolling, actual main-map workshop and City Storage labels, contract-expiry feedback, and built-workshop E.
- `test_scene_content_prepaid_ui.tscn`: **PASS**, including an actual mouse hover after the tooltip delay, no tooltip strings in the refreshed board or confirmation, accessible full names, keyboard focus, cancellation without payment, and one final transaction.
- `test_scene_worker_renew_currency.tscn` and `workshop_ui_regression_test.tscn`: **PASS**, including no tooltip strings, accessible currency/capacity, and existing action/error feedback.
- `workshop_worker_presence_test.tscn`: **PASS**, including building progress and dust/arrival behavior.
- `test_scene_worksite_presentation.tscn`: **PASS**, including City Storage E position and opening its menu.
- `workshop_keeper_integration_test.tscn`: **PASS**, including E → keeper dialogue → Continue → construction menu and the built-workshop interaction. Its inherited schema-8 arrival checks also passed.
- `test_scene_job_board_closed_feedback.tscn`: **PASS**, including the schedule boundaries and world feedback.
- Headless project startup for 180 frames: **PASS**, exit 0; this is a bounded launch check, not a full playthrough.

Before the changes, `workshop_construction_ui_test.tscn` failed its expectation that E opens the construction menu immediately. The current keeper interaction opens a dialogue first; the current keeper integration test above exercises that path. This older fixture was not changed or counted as a pass.

One Job Board rerun initially stopped when the fixture held a name label that the board's periodic refresh had freed. The fixture now reacquires the label after the frame wait; its subsequent rendered rerun passed. This adjusts the test only, not the refresh behavior.

Rendered evidence from the same isolated fixture: [build before](evidence/workshop-label-tooltip-2026-10-31/before-build.png), [build after](evidence/workshop-label-tooltip-2026-10-31/after-build.png), [eight workers after](evidence/workshop-label-tooltip-2026-10-31/after-build-workers.png), [workshop before](evidence/workshop-label-tooltip-2026-10-31/before-workshop.png), [workshop after](evidence/workshop-label-tooltip-2026-10-31/after-workshop.png), and [wallet icon hover](evidence/workshop-label-tooltip-2026-10-31/after-wallet-hover.png). The screenshots show the logical frame enlarged using nearest-neighbor scaling; they do not establish behavior on Windows, Android, or physical GPUs.
