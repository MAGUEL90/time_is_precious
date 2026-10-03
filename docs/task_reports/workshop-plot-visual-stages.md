# Workshop plot artwork and Board interaction

Date: 2026-09-28. Branch: feature/process-workshop/main-map-access.
Scope: authorized LEVEL 2 local scene integration; existing uncommitted user art,
two-plot map layout and gameplay changes preserved. No commit or merge.

## Behavior

- Removed WorkshopPlot/Footprint, an old decorative Polygon2D with no physics or
  construction role. No other scenes' Footprint nodes were changed.
- Uncleared/clearing: plot_level_0 plus to_be_clean_1 debris, hand prompt.
- Empty/building: plot_level_0 without debris, hammer prompt.
- Built: plot_level_1, object_board_1 and E prompt. The existing WorkShop backend
  remains BuiltWorkshop, with its old table sprite hidden. Production, worker
  assignment, storage and table collision use existing behavior.
- Board.position anchors the interaction shape and all prompts. The construction
  shape remains the author's 15x15 shape. The completed workshop gets its own
  duplicate of that shape at the same position. A single prompt is active per
  stage; the old construction area stops monitoring when built.
- Two table props use the first input item's icon from the existing first JobData
  recipe (clay_lump for mudbrick). JobData is the authority for available work;
  props are visual identification and consume no inventory. This does not add
  gameplay for selecting a new workshop type by depositing arbitrary materials.

## Validation

Godot 4.5.1 Compatibility, 1200x675. WorkshopClearingTest,
WorkshopConstructionUITest, WorkshopPlotAccessTest, WorkshopConstructionTest
and MudbrickPlayerFlowTest passed. Coverage includes exact player clearing time,
worker clearing, debris removal, level-1 artwork/material icons, center-of-plot
not triggering Board access, identical hand/hammer/E positioning, construction
reload, menu access and two-cycle production on the preserved worksite fixture.
Rendered hand, hammer and built stages inspected.

Tests now approach the authored Board instead of old hardcoded plot-center
offsets. Removed the obsolete assertion requiring an empty map: the Game Director
has since painted terrain and added a second plot. Those map edits are untouched.

Existing shutdown ObjectDB/resource-in-use diagnostics remain; no new runtime
errors observed in passing tests. Final visual acceptance remains human review.

## Existing MVP limitation

Both authored plots use MainWorkshopConstruction under WorkStateRuntime and
shared WorkShopStorage/production services. They therefore change construction
stages together. Independent workshop identities, stock and production require
a separate integration task; this visual change does not claim multi-workshop
support. No construction cost, duration, save schema or project settings changed.
