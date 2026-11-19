# World life animations — 2026-11-04

Status: **PASSED — NEEDS HUMAN REVIEW** for the two presentation changes; see the existing worksite-test failures below.

- Branch: `feature/visuals/world-life-animations-20261104`
- Base: `13a6c0725a08c91bfcbc2606646e8ebf0f668968` (remote `feature/gameplay/character-needs-20261101` at the start)
- Scope: local presentation, with no economy, worker assignment, save schema, project settings, plugins, or resource asset changes.
- The original checkout contained unrelated modifications. Work was done in a separate clone and tests used disposable `XDG_DATA_HOME` directories.

## The two animations

1. **Palm canopy sway.** The existing date-palm image shifts by up to two whole pixels at its top, while its base, node transform, pickup positions, and source identity stay fixed. Each palm has its own material and phase; the motion freezes on tree pause, game-time pause, and scene transition. Existing custom materials are left alone.
2. **Resident footsteps.** A small puff reuses the existing worker-dust drawing when a resident or worker physically moves during the ordinary walk cycle. It appears behind the feet, remains at its world position, and fades. Idle, hidden actors, pause, scene transitions, and large scene/time-skip jumps do not create footsteps. The effect does not alter the native body, clothes, hair, accessory, actor position, inventory, time, or work output. A frame-change listener replaces per-frame polling; each normal walk cycle creates at most one brief puff.

The earlier clay-work puff was removed. The supplied work sprite has no matching work layers for the available clothes and hair: the plain pickup garment covers only one outfit, while the other outfit and resident hair styles have no matching pickup/work sheets. The existing work pose therefore still falls back to its base sprite. Rather than invent mismatched artwork, the second animation now uses the fully dressed existing walk cycle. A complete work-pose identity fix remains dependent on suitable art.

## Visual review

- [Palm sway, five seconds](evidence/world-life-animations-2026-11-04/palm-sway.gif)
- [Dressed resident footsteps, 6.4 seconds](evidence/world-life-animations-2026-11-04/citizen-footsteps.gif)

The footstep recording shows a real resident using the city roaming controller at the 400×225 logical viewport, enlarged with nearest-neighbor scaling. For a clear review, the test fixture hides the HUD and Job Board in both captures; the footstep capture also hides the player, merchant, worksite markers and workshop craftsman. The playable scene and its collision/navigation data are unchanged. Both clips were rendered in Godot 4.5.1 with GL Compatibility and software OpenGL. Human visual acceptance and mobile testing remain open.

## Verification

Godot 4.5.1 stable, isolated user data:

- Editor import and normal project launch: passed without script errors.
- `test_scene_world_life_animation.tscn`: passed headless and graphically. It exercises real resident roaming and verifies four skin tones, both facings, both clothing styles, four hair styles, hat layers, ground-anchored puffs, idle/hidden/pause/transition behavior, large jumps, cleanup, and unchanged inventory, time, pickup positions and citizen profile.
- `date_tree_duplicate_test.tscn`: passed; separate pickup states survive map recreation.
- `test_scene_worker_visual_lifecycle.tscn`: passed; dismissal/rehire retains the correct resident visual.
- `test_scene_city_residents.tscn`: passed; real isolated city checkpoints save and repeatedly load resident visuals.
- Existing worker work and cart animation tests: passed with `TIP_TEST_WORK_ANIMATION=1` and `TIP_TEST_CART_ANIMATION=1`.
- `test_scene_worksite_presentation.tscn`: **failed six existing checks**, concerning the clay prompt versus Job Board art, one clay movement check, both straw focus checks, and two City Storage focus/open checks. The exact same six failures occurred on the untouched base commit under Godot 4.5.1 and 4.6.3. The worksite presentation test is therefore not claimed as passing; its failures need separate investigation.

The effects add no persistent fields. Date-tree recreation and city checkpoint tests cover the relevant existing lifetimes, but they are not a comprehensive compatibility test for every historical save or every scene. User saves were not opened or changed.
