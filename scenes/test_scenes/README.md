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

## Reading results

An automated suite must reach its named `PASS`/`PASSED` result, exit successfully,
and have no unexpected script or resource-loading errors. A forced `--quit-after`
exit is only a bounded launch check. An unfinished or timed-out suite has not passed.
Headless execution does not validate rendering or screenshots.

Dialogue Manager currently emits known ObjectDB/retained-resource diagnostics at
shutdown. Keep them visible and report them separately; a passing assertion suite
does not mean shutdown is clean. This exception does not cover other errors.

## Retired prototypes

The inactive `work_state_smoke_test`, old-map `main_map_worksites_test` and
`normal_start_production_audit`, and composite `branch_acceptance_flow_test` were
removed during audit part 1. They had no incoming runtime references and targeted
an inactive scenario or the removed map layout. The empty-wallet payment invariant
is retained in the production-chain integration suite. Historical task reports
describe their original runs; Git preserves the old fixtures.

This directory also contains shared worksite and worker UI code used by production.
Do not treat every file under `test_scenes` as disposable test scaffolding.
