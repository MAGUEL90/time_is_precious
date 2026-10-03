# Workshop depth and build-material debugging

Date: 2026-10-01. Branch: feature/process-workshop/main-map-access.
Baseline: 94bf6a96556021c919d3225ac1637fad37a52e71. Starting tree contains
extensive existing uncommitted implementation and authored map/art work.
Scope: authorized LEVEL 2, local plot presentation repair and development tools.
Status: PASSED - NEEDS HUMAN REVIEW. No commit, push or merge.

## Findings and change

The previous solid-probe checks covered side-wall/Board ordering but missed the
rear wall: all plot artwork sorted at the lower side-post edge. A new rendered
test reproduced a player inside the ruin still appearing behind the rear wall.

The same 48x48 level 0/1 texture now renders through seven nonoverlapping regions:
rear wall, upper/lower side posts, table and table feet. Each source pixel remains
in its authored position. Rear wall sorts at y -11, side posts at y 24, and table
and resource props at y 10. Board access/prompt center remains (16,26), with its
existing sort pivot (16,34). The authored ResourceIcon duplicate is retained and
now receives the built Board texture too, preventing the old Board image from
covering it after completion. No art files, map layout, collision, player controls,
project settings or autoload implementation changed.

Missing materials is the expected Inventory gate, not a second-plot state error.
The current empty map has no raw-material sources. A separate Debug panel button,
Build materials, fills deficits up to the existing construction requirement:
6 wood_log, 12 clay_lump, 8 reed_bundle. It preserves surplus and preflights the
complete missing weight; a full bag receives nothing. Repeated clicks do not
accumulate kits. Supplies are explicit and debug-only, including while the build
menu pauses gameplay; the existing Inventory signal refreshes its requirements.
Time controls still stop during pause. No automatic supply or balance changes.

## Verification

- Reproduced the rear-wall failure before repair; the added regression passes.
- Native Godot 4.5.1 Compatibility at 1200x675: ContentDepthTimeDebugTest passes
  with actual layered Player/object/background pixel comparisons for rear wall,
  both plot Boards, Job Board, built rear wall, built table and built Board.
- Debug supply checks cover empty Inventory rejection, deficit-only fill, surplus,
  repeated clicks, atomic full-bag rejection, refill inside the real paused build
  menu without time advancement, normal kit consumption, and completion via real
  time signals while the second plot remains uncleared.
- Five nearby regressions pass: WorkshopClearingTest, WorkshopConstructionUITest,
  WorkshopPlotIndependenceTest, WorkshopPlotAccessTest, MudbrickPlayerFlowTest.
- Editor import and git diff --check pass. Rendered debug panel/native Player
  captures inspected. Texture region coverage and placement checked exactly.

Existing ObjectDB/15-resource shutdown diagnostics remain (16 during editor
import); the extra editor reports the already occupied MCP port 9876. No new
blocking parse/runtime errors observed. Android/release export not tested.
Debug supplies do not restore the removed normal resource-site economy.
Shared workshop production/storage remains the existing MVP limitation.

## Files changed in this follow-up

- scenes/workshop_plot/workshop_plot.tscn and workshop_plot.gd
- scenes/debug/time_debug_overlay.gd
- scenes/test_scenes/content_depth_time_debug_test.gd
- ARCHITECTURE.md and this task report

All unrelated prior local work retained. Human merge decision remains pending.
