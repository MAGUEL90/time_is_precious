# Hauler cart motion and Worker Progress typography

Date: 2026-09-13
Status: PASSED — NEEDS HUMAN REVIEW
Branch: feature/process-workshop/clay-worksites

## Request and cause

The default dark Hauler in the delivery setup scene was displaying ordinary walk/idle motion alongside the cart. The imported push_cart and idle_cart character sheets exist only for light skin, and BaseWorkerVisual explicitly fell back to ordinary motion for other tones. The previous cart regression expected that incorrect dark fallback.

Worker Progress used a 10-pixel title, outside the requested 6/12/18 font sizes.

## Changes

- BaseWorkerVisual uses the supplied light cart poses when an equivalent skin-specific cart clip is unavailable. A small canvas shader applies the existing dark, tan or warm skin palette to body, head and hands; worker identity and the supplied cart artwork stay intact. Matching native cart clips take precedence when available. Normal movement restores its original materials and skin art.
- Cart pose layers continue to hide unmatched clothing, hair and accessories. World idle speed and the separate slower Tools preview setting are unchanged.
- Worker Progress title is 18 pixels. The close icon stays at its native 8 x 8 size, vertically centered alongside the title. Existing content fitting accommodates the larger header; body text and buttons retain crisp 6-pixel type. No authored scene geometry, colors, defaults or raster assets were replaced.

## Verification

- Reproduced the original bug: four new dark-cart expectations failed before the fix.
- WorkerCartAnimationTest passed headless and with GL Compatibility rendering. Light and dark push/idle animations advance through multiple frames under repeated play requests; body, head, hands and cart remain synchronized. Dark/tan/warm preserve identity, both directions mirror consistently, and ordinary movement clears the temporary material.
- HaulerDeliverySetupTest passed with rendering at the normal 1200 x 675 window / 400 x 225 logical viewport. The actual default dark Hauler moves on an outbound delivery and advances through at least three push frames. Destination/target accounting and existing assignment-reopen checks still pass.
- Worker Progress checks passed: title is 18, title is not clipped, close remains 8 x 8, content starts below the header, and controls remain within the panel and viewport.
- WorkerWorkAnimationTest and WorkerControlTest passed. The project launched headless and exited 0.
- Rendered cart poses, actual worksite delivery and Worker Progress were inspected. Existing certificate-store and shutdown ObjectDB / 15-resource warnings remain; no new blocking runtime errors appeared.

Evidence: `%TEMP%/tip-worker-cart-animation.png`, `%TEMP%/hauler-delivery-pushing.png`, `%TEMP%/hauler-delivery-progress.png`.

## Changed files

- `scenes/worker_visual/base_worker_visual.gd`
- `scenes/worker_visual/cart_skin_palette.gdshader`
- `scenes/test_scenes/ui_sandbox/clay_worksite_inspector/clay_worksite_inspector.gd`
- `scenes/test_scenes/test_scene_worker_cart_animation.gd`
- `scenes/test_scenes/clay_worksite_test/test_scene_hauler_delivery_setup.gd`
- This report.

Scoped pre-edit copies: `%TEMP%/tip-cart-progress-20260913-094200`. Incremental changes were reviewed against those copies so the existing dirty worktree stayed intact. No commit, push or merge was performed.

Manual check: restart the current delivery test scene, assign a Hauler and start Daily work. Use F for the next day at 06:45, then observe a delivery once output is available. Open Worker Progress from the worksite menu after Start Work.

Work split: Astra Medium handled diagnosis, implementation and verification. Luna XHigh was not delegated work for this task.
