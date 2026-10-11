# UI asset integration — 2026-10-11

Status: PASSED — NEEDS HUMAN REVIEW.
Branch: `fix/gameplay-hud/ui-consistency` (continuation of the requested UI polish).
Baseline: `dd1daa6`, clean working tree. Risk: Level 1, presentation-only changes.

## Scope and asset source

The user requested the newly committed artwork in Worker Hub ratings, raider
travel/Inspect, wall textures, loot and defense construction indicators. Fetched
`chore/assets/ui-update` and cherry-picked asset-only commit `d1e017f` as `d0e2676`.
All 36 asset files are preserved exactly; the other supplied building/character
assets are retained in the commit without adding unrelated gameplay placement.

The Heavy image is actually named `heavt_raider_icon.png`. It is mapped to Heavy
without renaming the author's file. All requested icons are 16x16. Updated wall
atlases remain 112x48 with the same 16px tile grid; existing painted cells and
ruined/built atlas mappings remain intact.

## Presentation changes

- Worker Hub Status, Level and Details use the star texture plus the existing
  numeric rating. Level entries retain wrapping for long names.
- Castle and raider travel markers use the supplied textures at native resolution,
  whole-pixel positions and nearest filtering. Scheduled progress remains intact.
- Inspect shows a 32x32 portrait panel for each nonzero type, native texture inside,
  and `xN` underneath. Card refresh, back navigation and detection gates are retained.
- Raider type resources supply their artwork. The UI also resolves artwork by ID
  for older or fixture inspection data without a texture.
- Shared world/City Hub construction indicators use wall/watchtower textures.
  Remaining time, paused status and progress remain visible. City Hub wall metrics
  use the wall icon, with aligned metric bars.
- Live theft uses a loot icon, count and weight/capacity. Raid reports show a loot
  total icon beside individual stolen items. Actionable status messages and
  numerical information remain available; no tooltips were added.

Production files modified beyond the asset commit:
`scenes/raid/defense_work_progress.gd`, `raid_travel_progress.gd`, `raid_ui.gd`,
`raider_type_icon.gd`, `raider_inspection_panel.gd`, `raider_inspection_panel.tscn`,
`light_raider.tres`, `normal_raider.tres`, `heavy_raider.tres`, and
`scenes/test_scenes/ui_sandbox/worker_control/worker_control.gd`.
Existing Raid UI and Worker Control fixtures were updated. This report is new.
No files were deleted or renamed. No gameplay values, save schema, autoloads,
addons or project settings changed. Reviewed editor-generated metadata was backed
up and restored under prior user authorization.

## Verification

Godot 4.5.2 import completed. Native Linux/Xorg tests at 1200x675, unchanged 400x225
logical viewport: Raid UI, Worker Control, Raid Playtest and Raid Expedition passed.
Headless City Save and Raid Composition also passed. The save code already strips
texture objects and reconstructs party icons from configuration; no save changes
were needed. Runtime screenshots were inspected for Inspect cards, Worker Hub,
construction, live loot, raid reports and updated wall artwork.

An initial Raid UI fixture run had a duplicate local variable name introduced in
its card-size assertion; corrected and rerun successfully. One Worker Control
rerun hit an existing deferred-refresh race between synthetic Unequip/Equip
clicks. Its fixture now waits another process frame before selecting the rebuilt
slot. Both subsequent native runs passed; equipment implementation is unchanged.

Evidence: `/workspace/scratch/asset-icons/`. Final logs: `test_scene_raid_ui-reviewed.log`,
`worker-final-1.log`, `worker-final-2.log`, `test_scene_raid_playtest.log`,
`test_scene_raid_expedition.log`, `test_scene_city_save.log`,
`test_scene_raid_composition.log`. Native dummy-display VSync warning only in final
runs; no script errors. `git diff --check` passed. Windows/Android unverified.

## Follow-up: quantity inside the card

User clarified that the 32x32 panel should contain both the portrait and `xN`.
From clean baseline `43e0387`, the card now encloses a native 16px portrait and
6px quantity text with 3px padding and a 1px gap. CardsRow minimum height is 32px.
Only the Inspect script/scene, existing Raid UI fixture and this report changed.
Native Raid UI regression passed at 1200x675, including exact 32x32 sizing and
quantity containment inside the padding. Screenshot reviewed. Evidence:
`/workspace/scratch/raider-count-inside/`. No gameplay changes; Windows/Android
remain unverified. `git diff --check` passed.
