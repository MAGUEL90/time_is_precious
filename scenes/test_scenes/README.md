# Regression entrypoints

Use Godot 4.5.x. Run an individual scene with F6, or from the project root:

```sh
godot --headless --path . res://scenes/test_scenes/mudbrick_production_chain_integration_test.tscn
```

Check the engine version first with `godot --version`; pass the full path to the
4.5.x binary if the default command selects another version. A fresh checkout
needs `godot --headless --editor --import --path .` before command-line tests.

## Prepaid worker contracts (2026-10-23)

Use **Godot 4.5.1** and an isolated `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, and
`XDG_CACHE_HOME` for these tests. Run only one engine process at a time.

| Scene | Coverage / arguments |
| --- | --- |
| `test_scene_prepaid_contracts.tscn` | Fixture: wallet purchase, packages, independent expiry, manual renewal, legacy boundaries, dismissal, transaction guards |
| `test_scene_contract_assignment.tscn` | Fixture: same-day 07–15 assignment, partial output, daily cap, hauler cargo |
| `test_scene_contract_notifications.tscn` | Fixture: existing !, acknowledgement, contract/merchant/raid events, long-name scrolling; rendered runs save screenshots |
| `test_scene_contract_continue.tscn` | Fixture: separate processes with `-- --contract-phase=write`, `read`, `readrenew`, `legacy-read`, `legacy-renew-read`, `assignment-write`, `assignment-read` in that order |
| `test_scene_contract_journey.tscn` | Normal New Game journey with active needs and earned income: `-- --journey-phase=write`, then `read` in separate processes |
| `test_scene_contract_ui_review.tscn` | Continue the earned journey checkpoint; `-- --contract-ui-phase=prepare`, `capture` (rendered), `write`, `read`; see driver for checkpoint paths |

Older seven-day city-payroll fixtures/journeys document the superseded rules;
they are not acceptance tests for wallet contracts. Older next-day commute/
departure fixtures likewise require updated expectations before reuse.
See `docs/task_reports/prepaid-worker-contracts-2026-10-23.md` for evidence and limits.

## Current map and production

| Scene | Coverage |
| --- | --- |
| `main_map_worker_hub_test.tscn` | Current `WorkerRuntime`, K/J modal controls and pause release |
| `main_map_hauler_start_test.tscn` | Current-map hiring, Cart equipment ownership, reload and dismissal |
| `debug_production_flow_test.tscn` | Current-map construction and two production cycles using explicit debug supplies |
| `mudbrick_production_chain_integration_test.tscn` | Held output, rejected empty-wallet payment, fee payment, drying and overdue fees |
| `population_employment_integration_test.tscn` | Population/employment separation and worker lifecycle |

The current PR #115 map has Clay, Wood, Reed, Straw and Water worksites and
matching stockpiles under `YSortWorld/WorkerRuntime`. The earlier no-resource-map
statement described the 2026-10-03 authoring checkpoint. Some worksite tests still
use `fixtures/content_worksites_map.tscn` or isolated Clay fixtures:
`resource_worksites_test.tscn` covers resource hauling and withdrawal, while
`initial_workshop_start_test.tscn` covers gathering, hiring and construction.
Their fixture setups do not prove the complete current-map economy from zero.

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

## Known incompatible legacy entrypoint (2026-10-18)

`current_map_funded_production_test.tscn` reuses the older
`mudbrick_player_flow_test.gd` with `use_authored_map=true`. That branch still
expects `YSortWorld/Worksites`; the current ContentScene uses WorkerRuntime.
It fails before production and is not valid current-map acceptance evidence.
Use `mudbrick_main_map_flow_test.tscn` for supplied integration coverage and
`mvp_first_playthrough.tscn` for normal-start evidence. The old failure is retained
in the audit report; do not count a timeout/forced shutdown as PASS.

`test_scene_city_progression_hub.tscn` currently fails the dense attack/construction
viewport check on the imported d6ea244 baseline as well as this branch. Its
headless capture helper also returns before layout settling; a temporary
three-frame probe removes the frame-equality failure but not viewport overflow.
`test_scene_wall_build.tscn` also fails its older caretaker-dialogue assertions.
See the 2026-10-18 audit evidence; neither is accepted as a passing suite.

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

## Food MVP walking route

`food_walking_playtest.tscn` validates the authored six-palm layout over 72 game
hours with movement input, normal player speed and the live world clock. It uses
real pickup interaction, work execution, home doors and sleep; it does not grant
food, refill trees, disable needs, teleport, or manually advance travel time.

```sh
TIP_FOOD_SEED=1 godot --headless --fixed-fps 60 --path . scenes/test_scenes/food_walking_playtest.tscn
```

Repeat with seeds 2 and 3. `--fixed-fps 60` performs offline fixed-step simulation;
it preserves gameplay speed ratios but does not measure host wall-clock pacing.
Look for `FoodWalkingPlaytest: PASS`, exit 0, and the structured `WALK_RESULT`.
Work and sleep retain their production time skips. Meals use the existing inventory
use action with automated quantity selection. This is scripted navigation, not a
human usability test. See `docs/task_reports/food-walking-playtest-2026-10-05.md`.

The older `food_survival_playtest` remains a teleported comparison. Its explicit
`TIP_FOOD_TREES` count is isolated from the production map's authored tree count.

The 2026-10-17 gameplay/main integration retains six palms on the newer wall city
layout. `date_pickup_access_test.tscn` checks all eighteen pickup positions for
authored land, clear approach, real E interaction and restored movement. The older
72-hour walking report/route is historical and does not certify this new layout.
PR #115 persists registered source slots, refill timers and RNG in schema v4;
source views stay separate from personal inventory drops. Explicit readers handle
v1/v2/v3. See `test_scene_pickup_sources.tscn` and the 2026-10-18 source report.


## Normal-start MVP journey (2026-10-18)

`mvp_first_playthrough.tscn` is separate from supplied production fixtures. It
opens New Game with zero personal resources/workers, walks using input, gathers,
eats, supplies city food, hires, builds and pays for repeated brick production.
Merchant requests remain randomized; player/worker needs remain active. UI
callbacks and known routes make this system automation, not human/visual QA.

Use **Godot 4.5.1** and a fresh isolated user-data directory for write. For example
on Linux, after import (replace the binary path):

```sh
export XDG_DATA_HOME="$(mktemp -d /tmp/tip-journey.XXXXXX)"
/path/to/Godot-4.5.1 --headless --path . --fixed-fps 60 res://scenes/test_scenes/mvp_first_playthrough.tscn -- --journey-phase=write
/path/to/Godot-4.5.1 --headless --path . --fixed-fps 60 res://scenes/test_scenes/mvp_first_playthrough.tscn -- --journey-phase=read
```

Run the commands as two processes against the **same** data directory. The
write phase requires two drying batches, a brick sale, yard level 2 and a sleep
checkpoint for PASS; a day-limit without these goals is PARTIAL/exit 2. Read
compares the entire saved snapshot at Continue before clock drift, then returns
to the city and resumes food upkeep. Read counters start at zero: pair its result
with its write run. Exit 0 plus the named PASS and **no runtime/leak errors** are
required. Bound the process externally (the audit used 600s write / 120s read);
a timeout is not a pass. `MVP_VISIT`, `MVP_MEASURE`, and `MVP_RESULT` expose the
observed requests, economy and conditions. No seed is forced, so outcomes differ.
See `docs/task_reports/mvp-first-playthrough-2026-10-18.md` for evidence and limits.

### Worker payroll stage 1 (fixture and normal-income journey)

Run `test_scene_worker_payroll.tscn` for first-payment atomicity/deposit checks.
Run `test_scene_payroll_continue.tscn` in six separate processes with
`-- --payroll-phase=write`, `pending`, `waiting`, `paid`, `sleep-write`, `sleep-read`,
in that order, sharing one initially empty isolated XDG data directory. The last
pair uses the real home bed and startup Continue. These tests inject rates/money;
they are not a normal-start economy journey. Use Godot 4.5.1. See
`docs/task_reports/worker-payroll-stage1-2026-10-22.md` for stage limits and evidence.

After approval of temporary rates on 2026-10-22, use
`test_scene_payroll_first_playthrough.tscn -- --journey-phase=write` then `read`
in separate Godot 4.5.1 processes with the same initially empty isolated XDG data
folder. Use `--headless --fixed-fps 60`; allow up to 600s write / 120s read.
The driver inherits navigation/upkeep/merchant helpers from the original MVP audit,
but runs only normal income → explicit treasury deposit → pending hire → first
payment → clearing → real sleep checkpoint → exact Continue. It never grants money,
materials or workers, overrides rates, or forces merchant requests. Merchant luck
can delay first income; a deadline without completion returns PARTIAL (exit 2).
The older full `mvp_first_playthrough` route still assumes immediate hire and is
historical pre-payroll coverage; do not treat it as current payroll acceptance.

### Paid-worker production integration

`test_scene_paid_production_journey.tscn` extends normal onboarding through
construction, Shape fees, one Drying batch, output withdrawal and bed/Continue.
Use fresh isolated XDG directories with `--headless --fixed-fps 60`, then
`-- --journey-phase=write` and `read` as separate processes (600s / 120s bounds).
It inherits the stage-1 checkpoint path, so never reuse an older run's directory.
The first paid period is a hard acceptance boundary; incomplete production returns
PARTIAL/exit 2. Merchant requests and needs stay active. A brick sale is recorded
if available but is not required for this gate. This does not test renewal.
See `docs/task_reports/paid-production-integration-2026-10-22.md` for the fixture
companion, normal evidence and limits.

For deterministic mid-work persistence coverage, run
`test_scene_paid_production_continue.tscn` in three separate Godot 4.5.1 processes
with `-- --production-phase=write`, `continue-shape`, and `continue-dry`, sharing
fresh isolated XDG data/config/cache paths. This is explicitly a fixture: money,
materials, clear weather, construction clock placement and production RNG seed
are test-owned. It verifies pending-worker rejection, exact mid-Shape/mid-Drying
Continue, distinct payroll/fee balances, and no duplicate output or fee entries.
It refuses an existing checkpoint instead of deleting it.

### Seven-day renewal and payroll pause

Use Godot **4.5.1**, isolated XDG data/config/cache directories, and separate
processes sharing the same data directory for each multi-phase test below.
Require exit 0, the named PASS, and no runtime/leak errors; timeout is not PASS.

- `test_scene_payroll_renewal.tscn`: due-group atomicity, current-rate renewal,
  continuing paid workers, no arrears/replay, production and mixed-team progress.
- `clay_worksite_test/test_scene_clay_worksite_payroll.tscn`: paused gathering,
  partial progress, cargo and eligibility at the 08:00 boundary.
- `test_scene_renewal_continue.tscn -- --renewal-phase=write`, then `expire`,
  `resume`, `finish`: full snapshots, active production, fractional construction,
  schema v1–v5 migration and strict v6 validation.
- `test_scene_payroll_cargo_continue.tscn -- --cargo-phase=write`, then `paused`,
  `resume`, `deliver`: actual map/start menu/Continue and City Storage delivery.
  These four scenes use explicit money/material/clock fixtures; they do not prove
  normal-income viability. Bound each process to 120 seconds.
- `test_scene_renewal_journey.tscn -- --renewal-phase=write`, then `fund`, `read`:
  normal needs-active continuation from the earned production checkpoint. Copy
  that checkpoint to `user://renewal_journey/checkpoint.json` first. Use
  `--headless --fixed-fps 60` and 360/360/120 second bounds. This driver does not
  grant resources or override time/needs/rates/RNG; the worker is idle here.

See `docs/task_reports/worker-payroll-renewal-2026-10-22.md` for exact source-save
provenance, fixture distinctions, results and limitations.

### Dismissal without payroll refund

Use Godot 4.5.1 and isolated XDG data/config/cache directories. Run
`test_scene_dismissal_continue.tscn -- --dismissal-phase=write`, then `rehire`,
`pay`, `expired` as separate processes sharing one initially empty data directory
(120s bound each). This is a fixture: money, XP, clock placements and re-applicant
eligibility are explicit grants. It checks archive/rehire, no refund or later
charge, one new payment, and completed-vs-active construction references.

For needs-active normal evidence, copy the earned renewal checkpoint into
`user://dismissal_journey/checkpoint.json`, then run
`test_scene_dismissal_journey.tscn -- --dismissal-phase=write` and `read` with
`--headless --fixed-fps 60` (360s / 120s bounds). It uses normal workshop/Worker Hub
controls and a bed save; no money/needs/time grants. Rendering write under the
normal1200×675 window also captures the confirmation at logical400×225. Do not
reuse the source save directory. See the dismissal task report for source SHA,
UI evidence, the transient workshop-selection limitation and exact results.

### Idle workshop selection after Continue

`test_scene_idle_assignment_continue.tscn -- --idle-assignment-phase=write`, then `read`,
uses separate Godot4.5.1 processes with one initially empty isolated XDG data
folder. It distinguishes a transient idle selector from actual worker reservations,
checks capture/prepare do not mutate the live selection, and verifies direct
Worker Hub dismissal after Continue. This is a fixture, not an earned-income run.

The dismissal journey above now fires directly after Continue: no workshop
reselect/release workaround. Old earned checkpoints may differ only in the explicit
ASSIGNED → HIRED repair for an idle worker with no persistent reservation. New
snapshots omit that transient status consistently; schema stays v6. See
`docs/task_reports/workshop-idle-assignment-2026-10-22.md` for this fix's evidence.

### Payroll UI readability review

`test_scene_payroll_ui_review.tscn -- --ui-phase=capture`, then `write`, `read`
uses an isolated copy of the earned v6 renewal checkpoint from the final payroll
acceptance report. Use Godot4.5.1 with `--fixed-fps 60`. The optional rendered
`capture` process saves unedited 400×225 viewport screenshots, leaving the
checkpoint untouched. Run `write` and `read` headless as separate processes for
real bed/Continue coverage. The driver verifies that Job Board has no deposit
controls, cancels then confirms one earned Shekel via physical City Storage,
checks the read-only City Management cash summary, and cancels worker dismissal.
Needs stay active; no grants. See
`docs/task_reports/city-storage-treasury-review-2026-10-22.md` for current behavior.
The earlier readability report describes the superseded Job Board spinner.

`test_scene_storage_treasury.tscn` is an explicit-grant transaction fixture:
mixed cash/goods atomicity, cap and wallet rejection, invalid selections,
signal reentry, and compatibility with legacy physical coin receipts.
`clay_worksite_test/test_scene_city_storage_supply_flow.tscn` also covers the
physical selector, stale confirmation, access loss, and unchanged item filters.

The older `test_scene_city_food_ui.tscn` is incompatible with the current UI:
it expects the hidden physical City Supply side panel and ignores two authored
startup applicants in its consumer count. It is not current UI acceptance evidence.

### Payroll cash-flow balance samples

`test_scene_payroll_balance.tscn -- --journey-phase=write`, then `read`, uses
Godot4.5.1 headless with `--fixed-fps 60`. Give every sample fresh isolated XDG
folders; share them only between that sample's write/read processes. Allow600s
write/120s read. This inherits normal onboarding/production with no grants or
RNG/rate/needs overrides. It sells available bricks within carrying capacity rather
than retaining ten for a future upgrade, and observes the remaining first paid
period. Upkeep's final-day bed checkpoint is reused to avoid sleeping an extra day.
A PARTIAL result is evidence of an unmet route goal, not a test to reroll away.

Results use `user://paid_production_journey/` and checkpoints use the inherited
`user://payroll_first_playthrough/` path. See the balance report for the three
preselected samples, cash reconciliation, pilot-driver correction and limits.
