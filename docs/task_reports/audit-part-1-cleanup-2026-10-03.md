# Audit part 1 cleanup — 2026-10-03

Status: `PASSED — NEEDS HUMAN REVIEW` for this bounded cleanup.
Risk: `LEVEL 1 — ISOLATED / LOW-RISK`.
Branch: `chore/project/audit-part-1-cleanup`.
Baseline: `70420caacfb082ab0797b392e91f9e5cbfae409f`; starting worktree was clean.

The Game Director authorized removal or simplification of obsolete part-1 code
when it has no required connection and removal does not disturb existing behavior.
The current main map has `WorkerRuntime`, without resource sites or destinations.
Tests requiring its previous `YSortWorld/Worksites` layout were therefore stale.

The Worker Hub and Hauler startup tests now target `WorkerRuntime`. The Hauler
test retains hiring, Cart ownership, reload and dismissal checks. Resource hauling
remains covered using the preserved populated-map fixture. The debug production
test retains two complete UI production cycles and loses its obsolete hauling
option. Before retiring the old normal-start audit, its empty-wallet payment
invariant was moved to the production-chain integration test: payment must fail
without moving Held Output into free stock or changing the wallet.

The inactive work-state prototype and three temporary editor saves have no
remaining runtime references. A final scan of surviving non-Markdown files found
no references to the deleted paths, filenames or deleted resource/script UIDs.
Historical reports remain historical. No gameplay implementation, addon,
autoload configuration, engine setting or economy value was changed.

## Changed files

Modified:

- `.gitignore` — ignore temporary `.tscn*.tmp` saves.
- `ROADMAP.md` — record this cleanup and correct the stale MCP installation status.
- `scenes/test_scenes/main_map_worker_hub_test.gd` — current-map path and explicit missing-Hub failure.
- `scenes/test_scenes/main_map_hauler_start_test.gd` — current-map hiring/equipment lifecycle.
- `scenes/test_scenes/debug_production_flow_test.gd` — remove obsolete hauling option.
- `scenes/test_scenes/mudbrick_production_chain_integration_test.gd` — preserve empty-wallet rejection coverage.

Created:

- `scenes/test_scenes/README.md` — active entrypoints, retained fixtures and result criteria.
- `docs/task_reports/audit-part-1-cleanup-2026-10-03.md` — this evidence record.

Deleted (13 files):

- `scenes/test_scenes/work_state_smoke_test.gd`, `.gd.uid`, `.tscn`.
- `scenes/test_scenes/normal_start_production_audit.gd`, `.gd.uid`, `.tscn`.
- `scenes/test_scenes/main_map_worksites_test.gd`, `.gd.uid`, `.tscn`.
- `scenes/test_scenes/branch_acceptance_flow_test.tscn`.
- `scenes/player/player.tscn360220884.tmp`.
- `scenes/player/player.tscn403024153.tmp`.
- `scripts/autoload/time_component_manager/time_component_manager.tscn2123253060.tmp`.

## Verification

Engine: `4.5.2.stable.official.6ce3de25a`, headless. Tests used a fresh temporary
project copy and isolated user/cache directories, with a 45-second timeout per
suite. Each suite reached its own success marker and exited with code 0; no
unexpected script or resource-loading errors were recorded.

| Suite | Result |
| --- | --- |
| MainMapWorkerHubTest | PASS |
| MainMapHaulerStartTest | PASS |
| DebugProductionFlowTest | PASS |
| MudbrickProductionChainIntegrationTest | PASSED |
| PopulationEmploymentIntegrationTest | PASSED |
| ResourceWorksitesTest | PASS |
| InitialWorkshopStartTest | PASS |
| WorkshopPlotAccessTest | PASS |

Fresh editor import completed without parse errors. A separate 90-frame main-scene
launch exited successfully; this is a bounded launch check, not a completed test
suite. The startup probe found all 20 autoloads, 37 items and one applicant offer.
World, WorkManager and ProcessManager clocks agreed at 600 minutes; WorkState's
time callback was connected once. `git diff --check` passed and the final diff
was reviewed. Test imports changed only three SVG import metadata files in the
temporary copy; none were copied back to the working tree.

## Remaining limits

- Existing ObjectDB/retained-resource shutdown diagnostics remain: 16 resources
  after editor import, 15 after runtime exits. Verbose launch logs identify all
  15 retained runtime scripts under `addons/dialogue_manager/`. This confirms
  their location, not the underlying cause or long-session memory impact.
- No rendered desktop/mobile playtest was performed. Godot 4.5.1 was not tested.
- No repository test runner or CI workflow was introduced. The README makes
  manual entrypoints and success criteria explicit.
- This cleanup does not complete audit parts 2–8 or authorize a merge.

Session logs and structured results: `/tmp/tip-part1-cleanup-3wtaybj4/validation.json`
and `/tmp/tip-part1-cleanup-3wtaybj4/logs/` (temporary environment artifacts).
