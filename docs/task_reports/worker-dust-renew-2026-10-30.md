# Worker dust after renewal — 2026-10-30

## Problem and change

On baseline `6581b7eb7f3f4558efd344688b0958678daa5ed2`, a controlled renewal of an expired builder reproduced activity dust while the worker was still returning. The diagnostic reported `travelling=true`, the old construction task in the plot's arrival cache, and `eligible=true`; an assertion that no dust should appear failed.

Dust eligibility now also requires a current matching, arrived physical approach when one exists. The existing empty-approach case retains the legacy inside-plot behavior. The same visual gate applies to clearing/building and running workshop orders. This changes neither contract/payment rules nor construction or production timing; it does not move the interaction prompt.

## Evidence

- [Before, returning](evidence/worker-dust-renew-2026-10-30/before-returning.png) and [after, returning](evidence/worker-dust-renew-2026-10-30/after-returning.png). These single frames complement the diagnostic and do not by themselves prove the entire travel interval.
- [After arrival](evidence/worker-dust-renew-2026-10-30/after-arrival.png) shows the active bar and dust.
- [Renewal, return and arrival animation](evidence/worker-dust-renew-2026-10-30/renew-return-arrival.gif) records the rendered fixture, including the return and post-arrival dust. The 84 frames are played at 10 fps to match the fixture's 0.1-second movement steps. Screenshots and GIF use nearest-neighbor scaling from the 400 × 225 logical viewport. The fixture invokes the existing renewal API and advances movement explicitly; it is not a recorded manual playthrough.

## Verification

Godot `4.5.1.stable.official.f62fdbde1`, isolated XDG save/config/cache, one engine process at a time:

- `test_scene_worker_idle_progress.tscn`: **PASS** for `roundtrip`, and for separate `write` then `read` processes. Assertions cover expiry, no dust and gray progress throughout renewed travel, physical arrival, and progress resuming; the write/read path repeats renewal after Continue.
- The same idle-progress fixture rendered on X11/llvmpipe at 400 × 225 logical / 1200 × 675 window: **PASS**, with the animation and screenshots above.
- `workshop_worker_presence_test.tscn`, rendered: **PASS**, including clearing/building and running workshop-order arrival, dust and reload behavior.
- `test_scene_prepaid_contracts.tscn`: **PASS**; bounded headless project startup (`--quit-after 180`) exited successfully. The latter is a launch check, not a completed game test.

The rendered driver reported that changing V-Sync mode is unsupported. A first presence run also reported no ALSA device before passing; the clean verification used Godot's Dummy audio driver. This fixture does not validate another graphics driver, platform, or a human playthrough.

The separately requested Job Board and contract-panel layout revisions are not part of this dust-only change. The annotated source images could not be materialized as local files in this executor through the available Library transfer, so those revisions remain pending their required pixel review.
