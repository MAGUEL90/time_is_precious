# World life animations — 2026-11-04

Status: **PASSED — NEEDS HUMAN REVIEW** for the two presentation changes; see the existing worksite-test failures below.

- Branch: `feature/visuals/world-life-animations-20261104`
- Base: `13a6c0725a08c91bfcbc2606646e8ebf0f668968` (remote `feature/gameplay/character-needs-20261101` at the start)
- Scope/risk: local presentation, with no economy, worker assignment, save schema, project settings, plugins, or resource asset changes.
- The original checkout contained unrelated modifications. Work was done in a clean, separate clone and tests used disposable `XDG_DATA_HOME` directories.

## The two animations

1. **Palm canopy sway.** The existing date-palm image shifts by up to two whole pixels at its top, while its base, node transform, pickup positions, and source identity stay fixed. Each palm has its own material and phase; the motion freezes on tree pause, game-time pause, and scene transition. Existing custom materials are left alone.
2. **Clay gathering puffs.** A small, earth-colored version of the existing worker dust puff appears once per working pose at an active clay site. It does not emit during arrival, idle, walking, water work, or after withdrawal. These clay puffs freeze on pause/transition and disappear normally on resume. The effect is attached to the worker visual and has no influence on output, stock, timing, or hauling.

The supplied work sprite still has no matching clothes or hair layers, so the worker temporarily uses its existing base work sprite in the recording. This branch does not add or duplicate character artwork.

## Visual review

These are actual frames from the playable city scene at its 400×225 logical viewport, enlarged with nearest-neighbor scaling. The clay recording uses a paid test worker assigned through the normal worksite API; the game clock is held steady for the capture.

- [Palm sway, five seconds](evidence/world-life-animations-2026-11-04/palm-sway.gif)
- [Clay worker, 8.5 seconds](evidence/world-life-animations-2026-11-04/clay-work.gif)

Both captures were rendered in Godot 4.5.1 using GL Compatibility and software OpenGL. Visual acceptance and platform-specific/mobile testing remain for the Game Director.

## Verification

Godot 4.5.1 stable, isolated user data:

- Editor import and normal project launch: passed without script errors.
- `test_scene_world_life_animation.tscn`: passed, including native clay assignment/arrival, one puff per stroke, unchanged stock/output/inventory, idle and water suppression, pause and scene-transition freeze, puff cleanup, independent palm duplication, unchanged pickup positions/state, and graphical capture. The earlier headless version also passed twice consecutively.
- `date_tree_duplicate_test.tscn`: passed; separate pickup states survive map recreation.
- `test_scene_worker_visual_lifecycle.tscn`: passed; dismissal/rehire retains the correct resident visual.
- `test_scene_city_residents.tscn`: passed; real isolated city checkpoints save and repeatedly load resident visuals.
- Existing worker work and cart animation tests: passed with `TIP_TEST_WORK_ANIMATION=1` and `TIP_TEST_CART_ANIMATION=1`.
- `test_scene_worksite_presentation.tscn`: **failed six existing checks**, concerning the clay prompt versus Job Board art, one clay movement check, both straw focus checks, and two City Storage focus/open checks. The exact same six failures occurred on the untouched base commit under Godot 4.5.1 and 4.6.3. The worksite presentation test is therefore not claimed as passing; its failures need separate investigation.

The effects add no persistent fields. The date-tree recreation and city checkpoint tests cover the relevant existing lifetimes, but they are not a comprehensive compatibility test for every historical save or every scene. User saves were not opened or changed.
