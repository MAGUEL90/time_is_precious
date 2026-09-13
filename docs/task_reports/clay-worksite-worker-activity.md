# Worksite assignment and activity separation

Date: 2026-09-09
Risk: Level 2 limited worker lifecycle integration, authorized by the request to separate assignment and activity before XP.
Branch: feature/process-workshop/clay-worksites. Existing local edits and scene layouts preserved.

## Behavior

- Start Daily creates the standing order immediately; it does not advance world time.
- During 07:00-15:00, work begins immediately with the next elapsed minute contributing progress. A 10:02 start has 4h58m left today, not a deferred eight-hour shift tomorrow.
- Before 07:00 workers rest until today's shift; at/after 15:00 they rest until tomorrow's shift. Empty stock during the shift means Waiting for resources.
- WorkerData now separates order reservation (`is_reserved`) from actual activity (`is_working`). RESTING and WAITING_FOR_RESOURCES were appended to the existing enum; IDLE and WORKING numeric values are unchanged.
- Daily updates activity at start and each clock tick. Depletion settles collected output, stops worked-minute accumulation and releases active site capacity while retaining the standing order.
- Withdrawal releases the order and sets Idle. Night rest and depletion do not silently cancel the assignment.
- Workshop backend, assignment UI and selection guards use reservation checks, preventing a resting/depleted worker from accepting a concurrent job. Inventory, worker hub and assignment status text use actual activity.

## Changed files

- resources/worker_data/worker_data.gd
- scripts/autoload/work_manager/work_manager.gd
- scenes/workshop/workshop.gd
- scenes/ui/inventory_ui/inventory_ui.gd
- scenes/ui/worker_hub_ui/worker_hub_ui.gd
- scenes/ui/workshop_worker_assignment_ui/workshop_worker_assignment_ui.gd
- scenes/test_scenes/clay_worksite_test/clay_worksite_daily.gd
- scenes/test_scenes/clay_worksite_test/clay_worksite_session.gd
- scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite_team.gd

## Validation

- ClayWorksiteDailyTest: PASSED headless and graphical at 1200x675, including start within shift, before-shift rest, 15:00 rest, next-day resumption, depletion waiting, unchanged worked minutes while waiting, reservation guards, withdrawal, and shared activity text.
- Explicit WorkManager checks reject both resting and depleted reserved workers.
- ClayWorksiteInspectionTest, ClayWorksiteGatheringTest, PopulationEmploymentIntegrationTest and WorkshopUIRegressionTest: PASSED.
- Main launch smoke: exit 0. Diff reviewed; git diff --check clean.
- Existing certificate store / ObjectDB / 15 resources at exit diagnostics remain. No new blocking errors observed.

## Boundaries

Daily jobs remain scene-local; persistence and a global cross-system daily work budget are not implemented. No save/load compatibility claim. Rate remains 6 clay/hour for all roles and configured daily stock remains 72-72. The previously discussed profession rates and scarcity ranges are not activated. No XP contribution changes.
