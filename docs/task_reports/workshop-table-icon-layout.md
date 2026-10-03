# Editable workshop table icons

Date: 2026-10-01. Branch: feature/process-workshop/main-map-access.
Baseline: 94bf6a96556021c919d3225ac1637fad37a52e71, with extensive pre-existing
uncommitted gameplay and authored art/map changes.
Scope: LEVEL 2, requested local icon layout controls. No gameplay, balance,
project/addon settings, autoload or recipe changes. No commit, push or merge.
Implementation validated; human approval requested to retain the saved scene
after the editor-tool persistence incident described below.

## Result and usage

In workshop_plot.tscn, expand TableResources and drag ResourceIcon/ResourceIcon2
or change their Inspector Transform position/scale. Each is now a visible clay
preview Sprite2D. The existing ResourceIcon was moved from the root (where it
duplicated Board artwork) into TableResources; Board access remains unchanged.
Defaults preserve the previous displayed clay layout. An editor-only drawing
script on TableResources shows the built table reference for placing the icons.

Runtime hides these previews until construction completes. _show_table_resource
uses the first input's icon from the existing first JobData recipe, replacing
only the Sprite2D textures. Authored transforms remain unchanged for other
material textures. Empty/missing recipes hide the group, and refresh creates no
duplicate Sprite2D nodes. This does not add a workshop-type selection mechanic.

## Persistence incident and recovery evidence

The open scene initially reported unsaved Toggle Visible history. Direct editor
save was rejected twice by automatic approval review because it would persist
all pending scene changes. A comparison of stored node properties with the saved
scene before icon migration returned no differences; post-migration comparison
showed only the ResourceIcon move and two TableResources children.

Editor operations were intended to stay in memory using save=false. However,
the addon's attach_script command ignores that flag and calls save_scene
unconditionally. Attaching the preview script therefore persisted the icon
setup unexpectedly. This was reported to the user and further editor mutations
stopped. Saved/current scene contents were inspected. An exact pre-task scene
copy is retained outside the repository in the task visualization directory as
workshop_plot-before-table-icons.tscn. Unrelated scene properties remain intact.
Human approval to retain this saved setup remains pending. No addon was changed.

A temporary migration helper was removed from the live scene before the final
attachment; the saved scene has no helper node/resource dependency. Early editor
command attempts produced Expression load/ResourceLoader errors and a cached
RefCounted-vs-Node helper mismatch. These are editor-command diagnostics, not
current gameplay parse failures. The helper source is now Node-based and its
headless parse check passes; no temporary helper runs in gameplay.

## Verification

Godot 4.5.1 native Compatibility at 1200x675; seven suites pass:
WorkshopTableIconLayoutTest, ContentDepthTimeDebugTest,
WorkshopConstructionUITest, WorkshopClearingTest, WorkshopPlotIndependenceTest,
WorkshopPlotAccessTest, and MudbrickPlayerFlowTest.

The new layout test configures different icon positions, scales and a group
offset before entering the tree, builds normally, and checks unchanged global
transforms when clay switches to wood. It checks hidden uncleared/empty states,
no duplicate nodes on refresh, and empty-recipe hiding. Existing pixel tests
check native Player depth with the new preview script disabled in gameplay.
Live editor icon selection and table preview screenshots inspected.
Editor import and git diff --check pass. Old ObjectDB/15-resource shutdown
diagnostics remain (16 during editor import), as does occupied editor port 9876.
Android and release exports are untested.

## Files

- scenes/workshop_plot/workshop_plot.gd and workshop_plot.tscn
- scenes/workshop_plot/workshop_table_resource_preview.gd and generated UID
- scenes/test_scenes/workshop_table_icon_layout_test.gd/.tscn and generated UID
- scenes/test_scenes/workshop_table_icon_editor_helper.gd and generated UID
- ARCHITECTURE.md and this report

Other local changes and authored world/interaction positions preserved.
