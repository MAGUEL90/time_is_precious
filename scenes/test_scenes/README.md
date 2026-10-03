# Regression entrypoints

Use Godot 4.5.x. Run an individual scene with F6, or from the project root:

```sh
godot --headless --path . res://scenes/test_scenes/mudbrick_production_chain_integration_test.tscn
```

Check the engine version first with `godot --version`; pass the full path to the
4.5.x binary if the default command selects another version. A fresh checkout
needs `godot --headless --editor --import --path .` before command-line tests.

## Current map and production

| Scene | Coverage |
| --- | --- |
| `main_map_worker_hub_test.tscn` | Current `WorkerRuntime`, K/J modal controls and pause release |
| `main_map_hauler_start_test.tscn` | Current-map hiring, Cart equipment ownership, reload and dismissal |
| `debug_production_flow_test.tscn` | Current-map construction and two production cycles using explicit debug supplies |
| `mudbrick_production_chain_integration_test.tscn` | Held output, rejected empty-wallet payment, fee payment, drying and overdue fees |
| `population_employment_integration_test.tscn` | Population/employment separation and worker lifecycle |

The current map has no resource sites or stockpile destinations. Worksite tests
use the preserved `fixtures/content_worksites_map.tscn` or isolated Clay fixtures:
`resource_worksites_test.tscn` covers resource hauling and withdrawal, while
`initial_workshop_start_test.tscn` covers gathering, hiring and construction.
These fixtures do not establish that gathering or hauling is available on the
current main map.

## Audit regression cases

| Scene | Coverage |
| --- | --- |
| `test_scene_player_action_locks.tscn` | Pickup/dialogue overlapping collapse, Nightmare escape/timeout, and independent movement restrictions |
| `test_scene_plot_collapse_handoff.tscn` | Manual plot clearing interrupted by collapse, followed by playable Nightmare and world return |
| `test_scene_negotiation_needs.tscn` | Negotiation applies only the configured elapsed-time needs costs |
| `test_scene_inventory_modal_pause.tscn` | Inventory shortcuts, repeated open/close, underlying Workshop pause and exit cleanup |
| `test_scene_worker_rehire_regression.tscn` | Actual midnight reapplication, preserved profession/XP, first-time defaults and eligibility |
| `test_scene_city_storage_overflow.tscn` | Atomic deposit/cargo rejection above the integer limit and exact-limit success |
| `clay_worksite_test/test_scene_clay_worksite_teardown.tscn` | In-flight owner removal, cancellation, freed Player and payout reentry conservation |
| `test_scene_clock_state_broadcast.tscn` | State refresh updates the time label without needs drain, duplicated work or day ticks; real minute/midnight advancement still works |
| `test_scene_transition_timing.tscn` | Actual Home ExitDoor transition, movement on both sides of the fade, failed transition restrictions, playable Nightmare timing and return |
| `test_scene_dialogue_runtime_regression.tscn` | Plugin singleton, runtime compilation, mutation/conditional choices and two real Player/NPC/balloon open/close cycles |

The existing City Storage supply/content tests expect the approved single,
unallocated startup Cart. The hauling fixture exposes seven authored destinations;
City Storage still rejects clay.

For automated Hauler fixtures, set `TIP_TEST_HAULER=1` for
`clay_worksite_test/test_scene_clay_worksite_hauler.tscn`, or
`TIP_TEST_HAULER_TARGET=1` for `clay_worksite_test/test_scene_hauler_delivery_setup.tscn`.
Without those switches the scenes are interactive demos.

## Reading results

An automated suite must reach its named `PASS`/`PASSED` result, exit successfully,
and have no unexpected script or resource-loading errors. A forced `--quit-after`
exit is only a bounded launch check. An unfinished or timed-out suite has not passed.
Headless execution does not validate rendering or screenshots.
`workshop_worker_presence_test`, `workshop_assignment_discard_test`, and
`content_depth_time_debug_test` require rendered frames and must use a graphical
Godot session; their unconditional frame waits do not finish in headless mode.

Shutdown must also be clean: ObjectDB or retained-resource diagnostics are failures
of that check even when gameplay assertions pass. Keep `DialogueManager` last in
the existing autoload list; the audit follow-up verifies this order on Godot 4.5.2.
Do not suppress errors or warnings to obtain a pass.

The graphical audit used X11 with Mesa llvmpipe at the existing 400 x 225 logical
viewport and 1200 x 675 window. Its exact driver warning about unsupported V-Sync
changes is an environment limitation recorded separately. This does not validate
another OS, physical GPU or Android. The depth test waits for construction splash
animations to finish before comparing built-art pixels. The dialogue regression
can also run graphically and saves a screenshot when `TEMP` names a writable folder.

## Retired prototypes

The inactive `work_state_smoke_test`, old-map `main_map_worksites_test` and
`normal_start_production_audit`, and composite `branch_acceptance_flow_test` were
removed during audit part 1. They had no incoming runtime references and targeted
an inactive scenario or the removed map layout. The empty-wallet payment invariant
is retained in the production-chain integration suite. Historical task reports
describe their original runs; Git preserves the old fixtures.

This directory also contains shared worksite and worker UI code used by production.
Do not treat every file under `test_scenes` as disposable test scaffolding.
