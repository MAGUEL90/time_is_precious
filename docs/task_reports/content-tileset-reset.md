# Content tileset replacement and authoring reset

Date: 2026-09-28. Branch: feature/process-workshop/main-map-access.
Baseline: 94bf6a9 with pre-existing uncommitted gameplay and authored UI changes.
Scope: LEVEL 2 limited scene integration, explicitly requested by the Game Director.
Status: PASSED - NEEDS HUMAN REVIEW. No commit or merge.

## Changes

- Copied the supplied 288x256 PNG unchanged into assets/tile_set. Source and copy
  SHA256 match: 0EB51A107CB273BB74897FF4C3E46D14C1473E80586A2404644FED0428EC0684.
- Created ground_tile_set.tres with one 16x16 atlas, 240 nontransparent cells.
  All four content tile layers use it and contain no painted cells. No inherited
  atlas coordinates, terrain rules or collision polygons are carried across.
- Retained WorkshopPlot and InitialWorksites/JobBoard at their original positions,
  along with the initial applicant, Player/camera, HUD, inventory/progress UI and
  return spawn marker. Player condition protection remains enabled.
- Removed the old Worksites instance, HomeDoor and embedded NightmareWorld from
  ContentScene. Reusable source scenes and old shared tilesets remain intact.
- Preserved the complete pre-reset map in the test-only fixture
  scenes/test_scenes/fixtures/content_worksites_map.tscn, without duplicating the
  production scene UID. Resource/production/City Storage tests and their playtests
  now load that fixture. Workshop interaction, clearing, hiring and construction
  tests still use the current ContentScene. Construction playtest no longer
  assumes a Worksites node exists.

## Validation

- Godot 4.5.1 editor import completed; new texture and resources loaded.
- Native Compatibility rendering at 1200x675: WorkshopPlotAccessTest PASS,
  including empty layers, atlas bounds, plot E interaction and Job Board E access.
- WorkshopClearingTest PASS: player/worker clearing and scene reload.
- WorkshopHiringRosterAudit PASS: initial applicant, hire and plot roster sync.
- ResourceWorksitesTest and two-cycle MudbrickPlayerFlowTest PASS using the
  preserved map fixture. These are not claims of production integration in the
  newly empty map.
- Rendered empty map inspected: plot, hand prompt, Job Board, Player and HUD visible.
- git diff --check passed. Existing local edits retained; project settings,
  autoloads, gameplay rules and reusable source scenes unchanged by this task.

Existing shutdown diagnostics remain: ObjectDB instances leaked and 15 resources
still in use (16 during editor import). The second editor process also reports
the existing MCP port occupied. No new runtime/parse/atlas errors observed in
passing tests. An initial board test needed a short physics settling interval
after unpausing; no production interaction change was required.

## Limits

This is an empty authoring map ready for manual tile painting. Automatic terrain
connections, new collision boundaries and a replacement layout are not authored.
Normal material gathering, home access and Nightmare World are unavailable here
until placed again. Existing player protection prevents collapse during accelerated
time testing. City Storage suites were redirected but not individually rerun;
the resource and production fixture paths were exercised. Final visual acceptance
belongs to the Game Director.
