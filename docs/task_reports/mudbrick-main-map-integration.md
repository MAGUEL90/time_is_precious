# Mudbrick main-map integration

Date: 2026-09-26
Branch: feature/process-workshop/main-map-access
Baseline: 94bf6a9
Status: PASSED - NEEDS HUMAN REVIEW for bounded integration; normal-game start remains PARTIAL.
Risk: LEVEL 2, authorized workshop-flow integration.

## Audit and scope

The parked checkpoint at 4de7d05 already supplied guidance and two-cycle production tests. Its original uncommitted worktree was read only and preserved. Applied only the four workshop menu script/scene patches and imported their formatter and fixtures. Current item-info bindings from the newer City Storage work remain intact. Existing construction, map layout, debug materials and player-needs changes were preserved.

The formatter explains pending delivery, output fees, missing Drying Yard, drying batches, active drying and finished output. This is functional guidance integration; visual polish remains deferred by the Game Director. Recipes, fees, duration, economy, global managers and project settings were not changed.

## Verification

Godot 4.5.1, GL Compatibility, 1200x675 with the existing logical viewport. All five suites exited 0:

- Mudbrick main-map flow: actual plot E interaction, worker selection and Build, three-day construction, released builder reused for production, deposit through UI, two complete Shape/pay/Dry/pay cycles, Drying Yard level-2 upgrade using ten finished bricks, and one finished brick withdrawn.
- MudbrickPlayerFlowTest: isolated two-cycle regression, cancellation preservation, fees, ownership, pending/short-batch guidance and layout assertions. Added a completed-cycle guard against premature PASS.
- WorkshopUIRegressionTest.
- MudbrickProductionChainIntegrationTest.
- WorkshopConstructionUITest.

Rendered active-drying and finished-stock screenshots inspected. Guidance and actions fit the existing viewport. Diff reviewed and whitespace check passed. Existing ObjectDB shutdown leaks / 15 resources still in use remain; no new script errors observed.

## Files

- Modified: workshop_menu_ui.gd/.tscn and workshop_storage_menu_ui.gd/.tscn; ROADMAP.md.
- Imported: workshop_flow_hint.gd/.uid; mudbrick_player_flow_test.gd/.uid/.tscn; mudbrick_mvp_playtest.tscn.
- Added: mudbrick_main_map_flow_test.tscn; this report.

## Human playtest and limits

Open scenes/test_scenes/mudbrick_mvp_playtest.tscn and press F6 for a manual production fixture with a Laborer, two recipes, facility materials and 100 Shekel. E opens Workshop: Manage Storage -> deposit inputs -> Assign Work -> Shape Wet Mudbricks -> pay Held Output -> Build & Upgrade Drying Yard -> Assign Work -> Sun-Dry -> pay finished output. The main-map automation is scenes/test_scenes/mudbrick_main_map_flow_test.tscn.

Fixture resources and worker are test-owned; final bricks are never seeded. The map integration test restores deterministic worker condition after construction, so it does not validate multi-day citizen-needs balance. Normal gathering, hiring/onboarding, full daily-loop balance, disk save/load and final UI polish remain pending. No commit, push or merge performed.
