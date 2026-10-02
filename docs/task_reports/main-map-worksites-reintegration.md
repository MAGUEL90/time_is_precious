# Main-map resource worksite reintegration

Date: 2026-10-01
Branch: feature/process-workshop/main-map-access
Baseline: 94bf6a96556021c919d3225ac1637fad37a52e71
Starting tree: dirty, including prior workshop implementation and authored art/map changes.
Risk: LEVEL 2, bounded ContentScene integration explicitly requested by the Game Director.
Status: PASSED - NEEDS HUMAN REVIEW; saved-file implementation tested and live editor refreshed with approval.

## Objective and scope

Place the five approved resource worksites into the extra space authored by the Game Director.
Reuse the existing Clay worksite mechanism and resource configuration. Preserve all existing
map tiles, both workshop transforms/identities, Job Board, Player/HUD and debug protection.
No new gathering controller, balance/economy values, hiring rules, project settings, autoloads,
plugins, save schema or production changes are part of this task.

## Implementation

ContentScene instances `scenes/content_scene/worksites/main_map_worksites.tscn` as
`YSortWorld/Worksites`, at local (-256, -376). It exposes one Clay site and the existing
Wood/Reed/Straw/Water configurations. Source markers and five stockpiles use the existing
inspector, daily scheduler, hauling endpoints and capacity-safe E withdrawal. Each stockpile
retains the existing 96-unit capacity, item filter and interaction shape.

The compact field layout uses resource icons and smaller decorative ground footprints only;
the existing 32-pixel worksite inspection distance, rates, time, costs and capacities are unchanged.
The shared adapter now treats CityStorageArea as optional so a resource-only section can reuse
the same controller without adding an unrelated warehouse to the newly authored space.
The full resource/City Storage regression fixture retains its original physical CityStorageArea.
City tool/equipment runtime ownership remains under WorkStateRuntime as before.

New fields/stockpiles are scene-authored and can be repositioned in main_map_worksites.tscn.
Normal startup grants no materials, hires no workers and provides no carts.

## Acceptance and verification

Godot 4.5.1 GL Compatibility, 1200x675 window and existing 400x225 logical viewport:

- Editor import/parse: passed, exit 0.
- MainMapWorksitesTest: passed, exit 0. Loads the actual current ContentScene; verifies
  all five sources via real E routing, modal guards and cancellation, normal three-hour
  Hourly work with a double-start guard, resource identities, inventory/overflow conservation,
  matching destination filters, full-bag rejection and repeated E withdrawal. Existing
  Job Board remains reachable. Reload retains the runtime provider/applicant without grants.
  Test-owned Laborer/Hauler teams and carts then exercise all five actual Daily routes and
  prove independent stockpile receipts plus ground/delivery conservation.
- ResourceWorksitesTest: passed, exit 0. Existing full-map fixture covers four simultaneous
  resource routes, capacity-safe withdrawals and deposit into the existing workshop.
- ContentDepthTimeDebugTest: passed, exit 0. Existing player/plot/Job Board depth tests and
  standalone time/material debug behavior remain intact with resource fields present.
- Rendered overview, normal player field view and Hourly inspector screenshots inspected.
- Original ContentScene tile-map byte arrays unchanged; live-editor terrain hashes also
  match the pre-task snapshot. Original node blocks retain authored properties.
- Task diff inspected and whitespace checked.

Existing ObjectDB shutdown leaks / 15 resources still in use persist (16 on editor import).
The second import editor reports port 9876 occupied. Two parallel regression processes
produced the known runtime bridge port 9877 conflict; gameplay assertions still passed.
The final current-map test ran alone and had no runtime bridge conflict or script errors.

## Live editor handoff

Before refresh, the editor held the pre-integration ContentScene while saved-file tests loaded
the new Worksites correctly. Its scene-change tool reported Modified based on undo history;
the last action was the authored InitialWorksites move, whose saved/current transform matched.
Godot 4.5.1 does not support the connector's get_unsaved_scenes command. The reload_scene
connector saves before reloading, so it was deliberately not used.

An attempted direct reload without save was rejected by automatic approval review because
it could discard unsaved editor changes. No reload occurred at that point and no indirect
workaround was executed. The Game Director then explicitly answered "Ya, reload dari file
tersimpan". The same direct reload without save succeeded under that authorization. Read-back
confirms the Worksites instance and five markers are present, plot/Job Board transforms are
unchanged, and both terrain hashes still match the pre-task snapshot. Editor stockpile labels
also show the same compact name/count format as runtime. The Worksites node was selected
for the Game Director to inspect.

## Files

Modified: ContentScene, content_worksites.gd, ROADMAP.md.
Created: main_map_worksites.tscn, main_map_worksites_test.gd/.uid/.tscn, this report.
Deleted/renamed: none. Existing unrelated dirty files preserved.

## Remaining limits

This task restores resource access on the new map; it does not close the full normal-game
mudbrick loop. Normal Shekel income, tools/Hauler acquisition and full daily-needs balance
remain outside this task. Worksite stockpiles retain their existing scene-local lifetime and
reset when the map reloads. No disk persistence was added. Separate plot construction still
does not imply separate workshop inventories. No commit, push or merge performed.
