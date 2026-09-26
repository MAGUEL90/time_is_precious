# City Storage clothing and worker needs visibility

Date: 2026-09-22
Branch: feature/workers/city-storage-supply
Baseline: 4de7d0521648712b277851b9b6ec90ea07772fab
Starting tree: dirty; all previous City Storage work retained.
Status: IMPLEMENTED / LOCAL QA AND HUMAN F6 PLAYTEST PASSED; BRANCH REVIEW PENDING
Risk: Level 3 integration; the seven-day clothing rule is explicitly approved (Level 4).

## Authority and objective

The Game Director confirmed all three final item-filter playtest points worked, including
player intake, clay Hauler destination restrictions and daily food consumption. The new
request authorizes continuing physical clothing supply, worker needs visibility, and an
actual-implementation flow in the existing Canva design. The explicit clothing choice is:
one clothing item serves one person for seven days, automatically replaced when expired;
if no replacement stock exists, the clothing need is unfulfilled.

Root owns architecture, design interpretation, documentation, Canva editing, engine runs and
final review. Three bounded Luna XHigh subtasks implement the specified backend, read-only
UI and targeted regression respectively. The initial clothing checkpoint preserved other
gameplay values; the approved satisfaction follow-up is recorded below. No commit, branch
change, PR or merge is authorized.

## Contract and scope

- Existing accepted finished clothing IDs are used equally: one whole item per person,
  seven daily evaluations, with no item-quality or outfit-visual rule added.
- Issuing on day D covers D through D+6; replacement is due on D+7. The item leaves available
  city stock at issue. There is no returned item, personal Inventory transfer or daily
  consumption of a second clothing item during the valid period.
- Residents and linked workers share one identity/allocation. Unlinked workers participate
  once; shortages retain the established resident-first order. Clothing issue and daily
  evaluation are guarded against duplicate/reentrant consumption.
- CityToolStorage owns available physical stock; CitizenNeedsManager owns runtime clothing
  allocations and last daily need results. Scene changes retain this runtime state. Full
  restart/save persistence remains out of scope.
- Worker Hub Details shows Food, Clothing, Shelter, remaining clothing days, resolved
  satisfaction/reliability and the actual last daily change. No prior evaluation is shown
  as unknown. Opening a UI must never consume supplies or evaluate a day.
- Clothing HUD/readiness uses physical clothing and active allocations. Food, shelter,
  wages, tools, capacity, recipes, production and reliability amounts are preserved.
  Satisfaction uses the approved follow-up below. No new punishments, production
  multipliers or worker dismissal.
- Canva gets a new actual-implementation slide after recommendation slide 2; preserve the
  earlier slides. Label implemented/validated, new work awaiting human review, and deferred
  logistics/treasury/save features accurately.

Expected files: CityToolStorage, CitizenNeedsManager, ImmigrationManager, worker-management
rows, WorkerControlUI script/scene, gameplay HUD, focused regression fixtures and relevant
design/architecture/roadmap/report documentation. No protected control-pack, project setting,
addon, save file, item resource, production-scene placement or resource-schema edits.

Pre-edit snapshot: %TEMP%/tip-city-clothing-20260922/before/ and before-manifest.json
(57 files including all 55 prior dirty paths and two initially clean test/UI targets).

## Validation plan

Test issue/renewal at day 7/8, shortages/recovery, linked-worker deduplication, unchanged
Inventory/tools/food, duplicate/reentrant evaluation, actual clamped satisfaction changes,
UI unknown/fulfilled/missing/long-value states, repeated open/close and runtime retention.
Run the nearest food, population/employment, worker-control and City Storage regressions,
editor parse and GL launch/captures with isolated temporary user data. Root reviews actual
diffs, rendered output and Canva save confirmation before marking the checkpoint passed.

## Delivered and reviewed

- Physical clothing transactions and seven-day runtime allocations use the shared city
  provider and the food recipient identity/order. No old clothing points are consumed.
- Worker-management rows bind the read-only daily result. Worker Hub Details is scrollable,
  refreshes when a full evaluation completes, and shows unknown needs before evaluation.
  Legacy HUD and immigration clothing readiness now read physical stock/valid coverage.
- Root reviewed all delegated changes against the pre-edit snapshot. Review changes include
  a named seven-day lifetime constant, a single HUD summary authority, current values for
  unevaluated workers, proper closure-state assertions and actual clamped-delta assertions.
- Food regression fixtures restore the new allocation/result maps. The rendered food test
  now verifies clothing retention through the real home/city transition as well.
- Canva slide 3, **City Storage Supply - Implementasi Aktual**, is editable and saved in
  the existing design: https://www.canva.com/design/DAG29BWgJp0/59ed7aJ8QwpNd2mIOEh31g/edit
  It covers one-way player deposit, accepted-item filtering, inbound Hauler routes, distinct
  Storage A/B, tool allocation, daily food/seven-day clothing and daily need effects.
  The initial subtitle marked clothing/Details as locally tested and awaiting human playtest;
  the later human confirmation and supply-summary follow-up are recorded below.
  Slides 1 and 2 retain the historical snapshot and accepted recommendation respectively.
  Outbound workshop logistics, Shekel spending and restart saving are explicitly deferred.

## Verification results

Godot 4.5.1 stable; each engine process used isolated temporary APPDATA/LOCALAPPDATA/TEMP.
No personal save was read, overwritten or deleted. Eleven final regression suites passed:

| Suite | Relevant evidence |
| --- | --- |
| CityClothingNeedsTest | whole physical units; invalid/reentrant requests; days 1-7; day-8 renewal/no-stock; recovery; linked/legacy recipients; clamps; read-only summaries |
| CityFoodDailyTest | food accounting, shortage order, duplicate/reentrant evaluation and real multi-day clock advancement |
| CityFoodStockTest | whole food/portion conservation |
| CityToolSupplyTest | shared item filter, atomic intake, equipment and no-return regression |
| WorkerControlTest (GL) | live Details refresh, unknown/met/missing needs, actual deltas, long names, scroll/focus/navigation, no UI consumption |
| PopulationEmploymentIntegrationTest | linked workers share the resident's physical food and clothing |
| ContentWorksitesIntegrationTest | authored content integration |
| CityStorageSupplyFlowTest (GL) | Area2D/E, real deposit and equipment access |
| CityStorageHaulingTest (GL) | accepted/rejected inbound shipments and conservation |
| CityFoodUITest (GL) | readable food states plus clothing/portion retention across home/city transitions |
| HaulerDeliverySetupTest | existing delivery setup with TIP_TEST_HAULER_TARGET=1 |

Root inspected rendered unknown/met/missing/long-name Details at the actual 400x225 logical
viewport, including scrolling down to the reason and satisfaction/reliability changes.
The new manual fixture additionally passed a GL input smoke through N/T/R: day 1 issue,
day 7 retention, day 8 replacement, day 15 shortage and day 16 recovery after deposit.
The recovery smoke uses the guarded provider deposit API; actual Area2D/E deposit UI is
covered independently by CityStorageSupplyFlowTest and remains in the human checklist.

QA logs and the reproducible temporary manual-smoke driver:
`%TEMP%/tip-city-clothing-20260922/qa/`.
Final suite cases: `clothing`, `food-daily-final`, `test_scene_city_food_stock`,
`test_scene_city_tool_supply`, `test_scene_worker_control-gl`, `population`, `content`,
`test_scene_city_storage_supply_flow-gl`, `test_scene_city_storage_hauling-gl`,
`food-ui-cleanup-confirm`, `hauler-setup`.
The final manual input/geometry smoke is `manual-smoke-ready`; final editor parse and
main-scene GL launch are `parse-final` and `main-gl`. All exited zero. `git diff --check`
passed. Captures were copied and hash-verified to
`C:/Users/Hendro/.codex/visualizations/2026/09/13/01a09d21-3741-7360-9bd0-e04ff7988583/city-storage-clothing/`.

Final scope comparison: 14 of the 57 snapshotted paths changed (including the two initially
clean WorkerControl test/scene paths); the other 43 match their pre-edit hashes. New paths
are this report and the clothing regression/manual scenes with their scripts and Godot UIDs.
The branch and HEAD remain the baseline recorded above. Prior item-resource edits, authored
scene placement and the parked workshop worktree were retained without changes in this task.

Findings repaired during QA:

- A new test initially expected Escape to return Details to Manage. Existing navigation
  dismisses the popup back to the Hub; the test now checks that preserved behavior.
- Two GL food/scene-retention runs passed assertions but crashed natively at process shutdown.
  The fixture now allows two frames for cleanup after freeing content. Both subsequent GL
  runs passed and exited normally. The exact native stack lacks symbols; no engine/driver
  root cause is claimed and no production workaround or rendering-setting change was added.
- The manual fixture's initial day skip while the Hub was visible timed out: the existing
  worksite minute callback rebuilt the Hub for every one of 1,440 skipped minutes. The
  test-only shortcut now hides it during the clock jump and refreshes once afterward.
  Runtime minute/daily needs processing remains the real path. Initial popup anchoring and
  the instruction panel bounds were also corrected after inspecting rendered captures.

Existing shutdown diagnostics remain: leaked ObjectDB instances and 15 resources in use
(16 in editor parse). These pre-existing warnings are not expanded into unrelated cleanup.

## Human playtest

F6 `scenes/test_scenes/clay_worksite_test/test_scene_city_clothing_playtest.tscn`.
The fixture supplies one resident linked to one Laborer, 32 city bread, two city clothes,
one shelter slot and a paused clock. Controls are local to this test scene:

1. Press **N**, then **T**. Day 1: clothing Met, seven days remaining, one clothing item
   left in city stock. Scroll Details to inspect the daily reason and values.
2. Use **N** through day 7: no further clothing is used. Day 8 consumes the second item
   and returns to seven days remaining. On day 15, Clothing becomes Missing while food
   and shelter remain Met; satisfaction falls 5 percentage points and reliability 5.
3. Press **R** once to give a garment to personal Inventory. Close the Hub, press **E** at
   City Storage and deposit it through the normal UI. Press **N**, then **T**: the next
   daily evaluation restores Clothing and the positive daily need result. No withdrawal.

The fixture stays running for manual inspection and restores the snapshotted shared state
on exit. It does not add hotkeys, goods, time acceleration or population to production content.

## Remaining limits

Human playtest and accumulated branch review are still required before a commit/PR/merge
checkpoint. City ownership remains permanent; clothing changes no visual outfit. Clothing
and food persist across scenes in the running game only. Full restart saving, capacity
balancing, treasury spending and city-to-workshop supply remain separate approved work.
No commit, push, PR, merge or branch switch was performed.

## Approved satisfaction balance follow-up — 2026-09-22

The Game Director approved reducing the incomplete-needs penalty from 10 to 5 percentage
points per day, retaining the 5-point increase when Food, Clothing and Shelter are all met.
This is one daily result per unique person, regardless of how many needs are missing.
Existing 1%-99% limits, reliability changes, clothing lifetime and automatic supply remain
unchanged. This explicit balance approval covers CitizenNeedsManager and the matching
design documentation (Level 4); the root performs this small follow-up directly.

Acceptance: each missing need alone and several missing needs together apply -0.05 once;
one fully supplied day recovers one shortage day away from the clamps; linked and legacy
workers share the rule; Details displays the resulting -5%; duplicate days remain guarded.
Expected scope is the daily evaluator, the existing clothing/Details regressions and this
report, plus the approved design rule and correction of an outdated architecture sentence.
Project settings, assets, saves, other balance values and unrelated branch work are out of scope.

Baseline remains `4de7d0521648712b277851b9b6ec90ea07772fab` on the same branch. All 64
previously dirty paths were snapshotted to `%TEMP%/tip-satisfaction-balance-20260922/before/`.
Validation: **PASSED — NEEDS HUMAN REVIEW**. Godot 4.5.1 passed CityClothingNeedsTest,
CityFoodDailyTest, PopulationEmploymentIntegrationTest and the rendered WorkerControlTest.
Editor parse and the main-scene GL launch also exited zero. The extended needs regression
covers the approved amount for each individual missing need, all three missing together,
duplicate-day evaluation, linked/unlinked workers, one-day recovery and existing clamps.
The rendered Details capture shows `Satisfaction: 45% (-5%)`. `git diff --check` passed.

All six engine runs used isolated temporary user-data directories. Logs, the runner and
rendered UI capture are under `%TEMP%/tip-satisfaction-balance-20260922/qa/` (capture:
`worker-control-gl/temp/worker-needs-missing-effects.png`). These runs also logged
`Failed to read the root certificate store`; no GDScript parse or assertion failure was
reported. The prior ObjectDB/resource shutdown diagnostics remain (15 resources, 16 in
editor parse). Certificate access and those existing leaks were not changed by this task.

Canva slide 3's existing satisfaction line now reads `+0.05 / -0.05` (the slide uses a
typographic minus). The connector still denied this design; the already-authenticated
browser editor applied the single-number edit and showed `All changes saved`. No connector
transaction was opened. The other slide content and pages were retained.

Changed files in this follow-up:

- `scripts/autoload/citizen_needs_manager/citizen_needs_manager.gd`
- `scenes/test_scenes/clay_worksite_test/test_scene_city_clothing_needs.gd`
- `scenes/test_scenes/clay_worksite_test/test_scene_worker_control.gd`
- `docs/game-concept.md`
- `ARCHITECTURE.md`
- `docs/task_reports/city-storage-clothing.md`

The six diffs were reviewed against this follow-up's snapshot; the other 58 existing dirty
paths retain their original hashes. No files were created, deleted or renamed in the repo.
At that checkpoint the human F6 balancing playtest was pending. No commit, push, PR, merge
or branch switch was performed.

## Human confirmation and supply-summary follow-up - 2026-09-22

The Game Director then reported that the supplied checklist worked and provided the
day-16 recovery Details screenshot: Food, Clothing and Shelter met, seven clothing days
remaining, Satisfaction 99% (+5%) and Reliability 90% (+3%). This confirms the requested
seven-day lifecycle, stock shortage and recovery checklist at the approved balance.
It does not claim long-term economy balancing or full-game save persistence.

The follow-up adds a read-only Clothing Supply panel to the physical City Storage menu
and validates eight people with seven garments, one-item deposit and next-day recovery.
Canva slide 3 now distinguishes the human-tested supply behavior from the locally tested
new summary. Its implementation, QA, remaining visual check and branch review handoff
are in `docs/task_reports/city-storage-supply-summary.md`.
