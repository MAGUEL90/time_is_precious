# Worker Tools feedback layout correction — 2026-09-13

Status: PASSED — NEEDS HUMAN REVIEW

## Problem and correction

The earlier fix kept positions stable but reserved two separate feedback rows (8 + 16 px). Together with the three equipment rows and the 12 px worker name, this exceeded PageStack's available height. The full-rect ToolsPage grew upward and overlapped the tabs. The earlier regression checked only unchanged positions, so it did not catch stable-but-invalid geometry.

Both feedback labels now share one fixed 8 px FeedbackArea below the equipment. Cart required uses the existing red style and takes priority over ordinary feedback. Empty feedback keeps the same area; one-line messages ellipsize if needed. The 330 x 200 panel, existing margins, title/name font sizes, six equipment cards, worker portraits and user-edited Details panel remain unchanged.

Selecting a working worker no longer clears the lock message immediately after rendering it. Gameplay locks and equipment rules are unchanged.

## Changed files

- `scenes/test_scenes/ui_sandbox/worker_control/worker_control.tscn`: shared feedback area.
- `scenes/test_scenes/ui_sandbox/worker_control/worker_control.gd`: new feedback paths, exclusive message visibility and retained lock message.
- `scenes/test_scenes/clay_worksite_test/test_scene_worker_tools_layout.gd` and `.tscn`: focused layout regression.

## Verification

- New test reproduced the bug before the correction: ToolsPage, worker name, worker scroller and footer extended outside PageStack; worker selection also cleared lock feedback.
- New test passed after the correction at the current 400 x 225 viewport with a 1200 x 675 development window: content below tabs; controls within PageStack; name/slots/footer separation; unchanged six-slot, name, preview-anchor and character positions across Working, Idle, Cart required, long feedback and reopen states; panel remains 330 x 200.
- Working, Idle and Cart-required screenshots inspected separately.
- WorkerControlTest passed. One graphical run reported a native Godot signal 11 during shutdown after all assertions had passed; a standalone rerun passed and exited 0. Root cause of that intermittent shutdown crash is unverified.
- Main headless smoke exited 0. Existing certificate-store and ObjectDB/15-resource shutdown warnings remain.
- Compared against the pre-edit scene/script copies: user styling is preserved; only the feedback section and its wiring changed. No stale feedback-node paths found. `git diff --check` passed.

No production managers, game balance, rendering settings, or other user modifications changed. No commit/push/merge.
