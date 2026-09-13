# Hauler commute without a cart and Page Down debug shortcut

Shortcut update (2026-09-13): the Director subsequently requested F instead of PgDn. The historical test results below describe the earlier checkpoint; current controls use F.

Date: 2026-09-13
Branch: feature/process-workshop/clay-worksites
Status: PASSED — NEEDS HUMAN REVIEW

## Requested behavior

Haulers use ordinary walk animation without a visible cart before reaching the worksite and when leaving after work. The debug next-day shortcut must avoid F8, which the Director reported stops the embedded Godot game.

## Implementation

- Removed the role/equipment-based conversion of every Hauler walk/idle request into a cart pose. The active hauling branch still explicitly requests push_cart while delivering or returning and idle_cart while waiting at the site. Commute and post-work roaming now request ordinary walk/idle, hiding the cart.
- World Hauler actors use the requested original light skin consistently across ordinary movement and cart activity. Stored citizen profiles, non-Hauler appearances, source PNGs, allocations and gameplay accounting were not edited.
- A real commute → idle_cart → push_cart test exposed the separate hand animation clock lagging behind the body. Cart head, hands and cart now follow the body's frame changes, with ordinary animation playback restored when leaving the cart pose. No animation FPS values were changed.
- In the delivery setup test scene, Page Down (PgDn) replaces F8 for advancing to tomorrow at 06:45. F7 remains +30 minutes and K remains Worker Hub. The on-screen hint and existing manual test instructions were updated. The action ignores key-repeat and input while paused. Project input settings and Godot editor settings were not changed.
- Existing Daily behavior stays intact: target completion stops new pickups, a final in-flight delivery/return completes with the cart, and ordinary roaming begins afterward. A finished day retains its assignment for tomorrow.

## Verification

- New regression checks reproduced the old cart-visible commute/departure and F8 handler before implementation.
- HaulerDeliverySetupTest passed with GL Compatibility rendering at 1200 x 675 / logical 400 x 225: commute without cart, arrival with idle cart, active delivery animation, leaving after the daily target without cart, light skin consistency, exclusive cart allocation, target/XP/conservation checks, and existing setup/progress UI checks.
- Shortcut checks passed: Page Down advances exactly to tomorrow 06:45, repeated/paused key events do not advance time, and F8 no longer advances the fixture. This is game-handler validation; the user's embedded editor shortcut was not operated by automation.
- ClayWorksiteHaulerTest passed: removal after completing cargo, late delivery retains the cart beyond 15:00 until completed, and completed-shift departure uses ordinary walk with the cart hidden.
- WorkerCartAnimationTest, WorkerControlTest and WorkerWorkAnimationTest passed. Main project headless launch exited 0.
- Captured and inspected `%TEMP%/hauler-commuting-without-cart.png`, `%TEMP%/hauler-leaving-without-cart.png` and the live delivery capture. The displayed test hint shows PgDn.
- Existing certificate-store and ObjectDB / 15-resource shutdown diagnostics remain. No new blocking errors remain. Incremental diffs and whitespace checks passed.

## Files

- `scenes/test_scenes/clay_worksite_test/clay_worksite_worker_visuals.gd`
- `scenes/worker_visual/base_worker_visual.gd`
- `scenes/test_scenes/clay_worksite_test/test_scene_hauler_delivery_setup.gd`
- `scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite_hauler.gd`
- Manual shortcut instructions in `hauler-destination-daily-target.md` and `hauler-cart-palette-and-progress-font.md`.
- This report.

Pre-edit copies: `%TEMP%/tip-hauler-walk-pagedown-20260913-112050`. Existing scene edits and dirty work were preserved. No commit, push or merge.

Suggested next MVP checkpoint: persist worker assignments, allocated tools, storage destination/target, accepted deliveries, City Storage contents and contribution XP across a close/reopen cycle. This was discussed as a next step, not implemented by this correction.

Work split: Astra Medium handled all investigation, implementation and verification. Luna XHigh was not delegated work.
