# Original light cart assets and Worker Progress correction

Date: 2026-09-13
Branch: feature/process-workshop/clay-worksites
Status: PASSED — NEEDS HUMAN REVIEW (asset/UI changes); Hauler target behavior audited.

## Correction

The Director requested the supplied light head, body and hand artwork without skin recoloring, a 12-pixel Worker Progress title, and removal of its Back button. This supersedes the earlier recoloring and 18-pixel title in `hauler-cart-palette-and-progress-font.md`.

- Cart poses now directly select light_push_cart / light_idle_cart clips for every worker profile. The added palette shader, its UID file and all shader wiring were removed. Ordinary worker appearance, the source PNG files, cart artwork and authored scene tweaks were not edited.
- The pushing hand uses the already existing `assets/characters/shared_assets/hand_assets/push_cart/light/light.png`. No hand artwork was drawn or generated in this correction or the preceding palette task. Head/body/hand atlas paths are explicitly checked by the regression test. Idle cart keeps the separate pushing-hand layer hidden, matching the supplied idle sheets.
- Worker Progress title is 12 pixels. The extra Back button is removed; the existing animated close icon remains functional at its native size. Body labels retain 6-pixel type.

## Why the Hauler stopped

The supplied screenshots show Storage A and Worker Progress at 20 / 20 items. `_hauler_eligible()` stops new trips once accepted storage deliveries reach the daily target; remaining clay and time before 15:00 do not override that target. The current visual controller then uses its ordinary post-work roaming behavior after the return trip. Daily assignment remains for the following day.

The existing delivery test confirms target 20 stops at exactly 20 with clay still available, a final two-item trip, no further delivery credit that day, and a reset the next day. Transport quota and departure behavior were not changed in this correction. An optional question was sent about waiting idle at the site until shift end versus leaving early; no answer had been received when this report was written.

## Verification

- WorkerCartAnimationTest passed with GL Compatibility rendering: original light atlas paths, no recolor materials, synchronized body/head/hands/cart, multiple advancing frames, both directions, native ordinary movement after cart motion.
- HaulerDeliverySetupTest passed headless and with rendering: actual outbound Hauler uses all three light clips without a shader, delivery quota and resource conservation remain valid, assignment reopening remains valid, title is 12, Back is absent, close works, and controls fit the viewport.
- ClayWorksiteDailyTest passed, including Worker Progress removal/cancel flow. Main project launch exited 0.
- Rendered cart poses, live delivery and Worker Progress were inspected at the normal 1200 x 675 window / 400 x 225 logical viewport.
- Existing root-certificate and shutdown ObjectDB / 15-resource warnings remain. No new blocking errors appeared. Incremental diffs and whitespace checks passed.

Evidence: `%TEMP%/tip-worker-cart-animation.png`, `%TEMP%/hauler-delivery-pushing.png`, `%TEMP%/hauler-delivery-progress.png`.

## Files

- Edited: `scenes/worker_visual/base_worker_visual.gd`
- Edited: `scenes/test_scenes/ui_sandbox/clay_worksite_inspector/clay_worksite_inspector.gd`
- Updated checks: `scenes/test_scenes/test_scene_worker_cart_animation.gd`, `scenes/test_scenes/clay_worksite_test/test_scene_hauler_delivery_setup.gd`
- Removed the preceding task's `scenes/worker_visual/cart_skin_palette.gdshader` and `.gdshader.uid`.
- Added this report.

Scoped backup: `%TEMP%/tip-hauler-light-progress12-20260913-095916`. Existing dirty work was preserved; no commit, push or merge was performed.

Work split: Astra Medium performed the investigation, correction and verification. Luna XHigh was not delegated work.
