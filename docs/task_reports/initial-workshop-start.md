# Initial workshop materials and hiring

Superseded implementation: the separate Gather component described below was removed after
the Game Director clarified reuse of Clay Worksite. Current behavior and validation are in
`shared-resource-worksites.md`. This report records the earlier checkpoint only.

Date: 2026-09-26
Branch: feature/process-workshop/main-map-access
Baseline: 94bf6a9; existing construction and mudbrick integration changes preserved.
Risk: LEVEL 2, explicitly approved material-source and initial-applicant integration.
Status: PASSED - NEEDS HUMAN REVIEW for initial materials/hiring/construction; full production funding remains PARTIAL.

## Approved scope

The Game Director approved four fixed gathering sources using E and a time/output preview, delegated provisional quantities/durations, and approved one initial Laborer applicant through the existing Job Board and wage rules. UI polish is deferred.

- Wood: 3 logs / 60 minutes.
- Reeds: 4 bundles / 30 minutes.
- Straw: 3 bundles / 30 minutes.
- Water: 3 jars / 15 minutes.

Values and positions are authored in scenes/content_scene/startup/initial_worksites.tscn and editable in Godot. Sources are repeatable for this MVP; they do not define finite stock or regeneration. Clay keeps its existing worksite. Gathering awards personal Inventory items, checks capacity and uses existing time-driven conditions.

The initial applicant uses a stable ID in the existing citizen store. Map visits do not replace the hired worker or create another applicant. Legacy prototype workers are preserved; the new start test clears its own test-process roster to prove this path without relying on them.

## Changes

- Added reusable material gathering spot and compact confirmation UI.
- Added initial-worksites scene and applicant bootstrap; instanced it on the current authored map without moving existing content.
- Added Player interaction dispatch for the gathering group.
- Added initial_workshop_start_test for empty-inventory gathering, hiring and construction.
- Updated approved design notes and progress documentation.

## Validation

- InitialWorkshopStartTest PASS: empty initial inventory, no pre-hired workers, actual E at Job Board, existing wage, all four gathering previews, cancellation, full-capacity rejection and retry, exact yields/time, leaving range, interruption after 20 minutes yielding one log, repeated confirmation, clay via existing hourly work UI, workshop construction using gathered materials and the hired Laborer, worker release, and reload without a duplicated applicant.
- PopulationEmploymentIntegrationTest PASS before integration: existing applicant/hire/assignment rules.
- Mudbrick main-map two-cycle test, ContentWorksitesIntegrationTest and WorkshopPlotAccessTest PASS after integration.
- Native Godot 4.5.1 at 1200x675; four gathering-preview captures and Job Board capture produced, Wood/Job Board renders reviewed. Functional information and buttons are visible; existing Job Board styling/truncated row labels remain part of deferred UI polish.
- The first start-test run failed because its teleport immediately after closing Job Board used stale physics overlap; the fixture now waits five physics frames before E. The final run completed cleanly. No initial failed run is counted as passing.
- Editor startup/import exited 0 but ended with a scan-aborted warning; successful runtime loads verify the new scenes/scripts, not a completed full editor scan. Existing MCP port-in-use and ObjectDB shutdown resource warnings persist. No new script errors in passing runs.
- Root reviewed delegated gathering scripts/scenes and corrected duplicate-signal/invalid-property issues before final tests; no gameplay manager or project-setting changes. Diff and whitespace checks passed.

## Remaining limits

No starting money, new income source, wage changes, save system, global manager registration, or project settings changes. Normal access to Shekel for existing production fees remains a separate design gap. Existing player-needs debug overrides remain enabled at the Game Director's request. Final scene placement/art, balanced conditions/citizen needs and UI polish are not claimed complete.
