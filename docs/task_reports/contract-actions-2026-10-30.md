# Contract confirmation actions — 2026-10-30

This is a partial follow-up to the owner's Job Board review. The three contract-duration buttons no longer set native tooltips, the final action reads `Confirm`, and the redundant top-right `X` is removed. `Back` and Escape retain the existing cancellation path; the keyboard focus loop now covers the duration choices, Back and Confirm. The full name tooltip for shortened names and currency descriptions are retained.

The wallet source, prices, candidate selection, 3/6/9 durations and batch transaction logic are unchanged. The remaining annotated layout, icon, margin and font changes are pending pixel inspection of the owner's reference images in the execution environment.

## Verification

Godot `4.5.1.stable.official.f62fdbde1`, isolated XDG data/config/cache, one engine process at a time:

- `test_scene_content_prepaid_ui.tscn`: **PASS** headless and rendered, including no duration tooltip, focus reachability, repeated Back/open, no payment on opening or cancellation, changed quotes, insufficient funds and a single atomic final payment. Long names and 3/6/9-day choices were also checked.
- `test_scene_job_board_closed_feedback.tscn`: **PASS** headless, including the opening-time boundaries, repeated attempts and existing E prompt position.
- Rendered captures use the 400 × 225 logical viewport, scaled nearest-neighbor to 1200 × 675. The X11/llvmpipe driver reported that changing V-Sync is unsupported. An initial baseline launch failed because X11 was not running; after starting the dummy display the rendered baseline and final fixture passed.

[Before](evidence/contract-actions-2026-10-30/before.png) · [After](evidence/contract-actions-2026-10-30/after.png) · [After, long name](evidence/contract-actions-2026-10-30/after-long-name.png). These are controlled fixture renders, not a manual playthrough or final layout review.
