# Shared interaction prompts and highlight

2026-09-28, feature/process-workshop/main-map-access. Authorized local integration
of interaction visuals, including Player selection and the separate worksite flow.
Pre-existing dirty work and authored scenes preserved. No commit/merge.

- Shared E prompt now uses the same brown 16x16 panel atlas as clean/build, with
  a 16x16 minimum and runtime size so inherited scene offsets cannot shrink it.
- Cleaning uses assets/ui/ui_icon/hand_job_icon.png; building retains the hammer.
- Player target changes apply a warm brightness tint to Sprite2D,
  AnimatedSprite2D and Polygon2D artwork. Original self_modulate colors are
  restored when target changes, leaves range or Player exits the tree. Controls,
  prompts and CanvasLayers are excluded; no material/shader replacements.
- BuiltWorkshop identifies the authored plot as its artwork root. The separate
  worksite nearest-target flow uses the same helper and clears it when hidden.
- Existing interaction eligibility, ranges, recipes and timing are unchanged.

Validation: native Godot 4.5.1 Compatibility at 1200x675. WorkshopPlotAccessTest,
WorkshopClearingTest, WorkshopConstructionUITest, ResourceWorksitesTest and
MudbrickPlayerFlowTest passed. Assertions cover 16x16 E size, hand_job texture,
highlight application/restoration and existing interactions. Rendered cleaning
and Job Board highlights inspected. Other NPC/pickup/sleep/storage artwork uses
the shared hook but was not individually visually reviewed. Custom drawings with
no Sprite2D/AnimatedSprite2D/Polygon2D are not affected by this artwork helper.

Existing test-process MCP port 9877 conflict and shutdown ObjectDB/resource-in-use
diagnostics remain. No feature-script errors observed in these runs. Final visual
acceptance remains with the Game Director.
