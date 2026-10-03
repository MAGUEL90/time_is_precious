# Content depth sorting and time debugging

Date: 2026-10-01. Branch: feature/process-workshop/main-map-access.
Baseline: 94bf6a96556021c919d3225ac1637fad37a52e71 with extensive existing
uncommitted gameplay and authored map changes. Scope: authorized LEVEL 2 scene
presentation and development tooling. Status: PASSED - NEEDS HUMAN REVIEW.
No commit, push or merge.

## Result

WorkshopPlot now participates in the map's existing YSortWorld through its own
y_sort_enabled root. Wall/table artwork sorts at its lower edge, the small Board
at its feet, and floor debris stays at z_index -1. Matching Sprite2D offsets keep
the artwork in its authored world position. Table material props share the
building's depth while retaining their original visual offsets. Board access and
prompt positions use its image center, preserving the existing interaction range.
The authored ResourceIcon duplicate is retained and aligned with the Board.

Job Board and the reusable WorkShop table also sort from their feet with offsets
that preserve their displayed positions. Player stays at world z_index 0 and
its layered body/clothes/head remain one sorted unit. Ground tile layers retain
-30/-20/-10. Plot captions and shared E prompts use z_index 10 so characters do
not obscure interaction text. Existing NPC, pickup and storage roots already use
foot pivots and retain their atomic character/object visuals. No map layout,
collision, movement speed or project rendering settings changed.

TimeDebugOverlay is a separate scene under scenes/debug, attached only to the
current ContentScene. A small Debug button at the upper left and backtick (`)
toggle its panel. Controls provide x1/x10/x60 and +30m/+3h/+1d. Opening the panel
is nonmodal. Release builds remove the overlay via OS.is_debug_build(). This is
scene-local tooling; no new autoload, Input Map action or project setting.

The normal clock retains its configured seconds_per_minute. Acceleration adds
the extra minutes through advance_one_minute/day_cycle, preserving minute/day
signals and normal movement/physics rate. Jumps use advance_minutes one minute
at a time. Gameplay/tree pause, time pause, transition, sleep, collapse and player
movement locks stop acceleration/jumps. Existing player need protection remains.
Speed defaults back to x1 when this map's debug overlay is recreated.

## Verification

Godot 4.5.1 editor import and native Compatibility rendering at 1200x675 passed.
ContentDepthTimeDebugTest checks actual rendered pixels with a test-owned solid
Player visual: front/behind ordering for wall, small Board and Job Board. It also
checks preserved picture/interaction centers, panel keyboard toggle, x10/x60
minute totals, pause guards, real worker clearing completed by +3h, +1d calendar
advance and x1 stopping extra time. The debug panel and depth captures were
visually inspected. The native Player remains in the ordinary scene tests.

Five nearby regressions passed: WorkshopClearingTest, WorkshopPlotAccessTest,
WorkshopConstructionUITest, WorkshopPlotIndependenceTest and MudbrickPlayerFlowTest.
Test positions now use InteractableComponent instead of the old Sprite center,
because Board.position is its sorting pivot. git diff --check passed.

Existing ObjectDB/15-resource shutdown diagnostics remain (16 during editor
import), and the extra editor reports the occupied MCP port 9876. No new feature
parse/runtime errors observed. Android and release exports were not executed.

## Changed files

- scenes/player/player.tscn
- scenes/job_board/job_board.tscn
- scenes/workshop/workshop.tscn
- scenes/workshop_plot/workshop_plot.tscn and workshop_plot.gd
- scenes/content_scene/content_scene.tscn
- scenes/components/interactable_label_component/interactable_label_component.tscn
- scenes/debug/time_debug_overlay.gd and time_debug_overlay.tscn
- scenes/test_scenes/content_depth_time_debug_test.gd and .tscn
- Board-position adjustments in existing clearing/access/construction/start tests
- This task report and ARCHITECTURE.md presentation/debug ownership note

Previously authored layout, hidden HUD choices and other branch work preserved.
Shared workshop stock/production remains the previously documented MVP boundary.
