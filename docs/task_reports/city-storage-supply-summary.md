# City Storage supply summary and branch handoff

Date: 2026-09-22
Branch: `feature/workers/city-storage-supply`
Baseline: `4de7d0521648712b277851b9b6ec90ea07772fab`
Starting tree: 64 dirty paths; all preceding work retained.
Status: IMPLEMENTED / LOCAL QA PASSED; NEW SUMMARY VISUAL CHECK PENDING
Risk: Level 2 limited UI integration of approved existing supply rules.

## Objective and authorization

The Game Director confirmed the F6 clothing/satisfaction checklist worked: automatic
seven-day supply, a five-point satisfaction shortage, and recovery after physical deposit.
The follow-up approves a City Storage supply summary, the eight-person/seven-garment
shortage/recovery scenario, and preparation of documentation and a branch review handoff.

The player needs to distinguish clothing already distributed from spare stock and the
additional garments required. Existing per-person needs, +5/-5 satisfaction, +3/-5
reliability and seven-day validity remain the approved authority. This work adds no
manual clothing equip, new supply rules, global satisfaction or outbound logistics.

## Scope and acceptance

- The physical Area2D City Storage menu retains Food Supply and its existing item grid.
- A compact Clothing Supply panel reads `get_clothing_supply_summary()` from the same
  CitizenNeedsManager/provider. People includes unique residents and unlinked workers.
- Covered counts currently valid seven-day allocations. Reserve counts whole available
  garments. Awaiting counts people without valid coverage. Short is the additional stock
  required after reserve is considered. It is not a forecast for all future renewals.
- A deposit updates Reserve immediately; pending coverage says `Ready next day` when
  reserve is sufficient. It becomes Covered only during the daily supply evaluation.
- Opening/refreshing the display cannot distribute clothing, consume items or alter needs.
- Refresh on stock, time, population addition and completed needs evaluation; disconnect
  listeners on closing. Food, clothing and the grid remain readable at 400x225.
- Eight people with seven clothes yield 7/8 coverage and Short 1; a one-item deposit yields
  Reserve 1 and Short 0 with coverage still 7/8; the next day yields 8/8 and Reserve 0.

Root owns UI, integration, documentation, Canva and final review. A bounded Luna XHigh
subtask extends only the existing CityClothingNeedsTest for the eight-person backend case.
Expected edits: `city_storage_access_ui.gd/.tscn`, the clothing/food-UI regressions,
ROADMAP/architecture/task reports and the existing actual-flow Canva slide.

Protected control files, design/economy values, autoload behavior, assets, saves, project
settings, deferred workshop work and unrelated edits are out of scope. Git handoff is
preparation for review; no commit, push, PR creation or merge is performed in this step.

## Validation plan

Run the clothing distribution and rendered supply UI regressions, the nearby physical
deposit/equipment flow, population integration, parser and normal GL launch. Review the
actual rendered shortage, reserve-ready and covered states; test zero people, large stock,
population growth, scene transitions, read-only summaries and listener cleanup. Finish
with a snapshot comparison, diff review and an explicit list of remaining human checks.

Pre-edit files and hashes: `%TEMP%/tip-city-supply-summary-20260922/before/` and
`before-manifest.json`.

## Delivered and verified

The new left Clothing Supply panel and existing right Food Supply panel surround the
unchanged item grid. The clothing display uses the existing summary API and completed
needs signal. No backend, item policy, daily amount, lifetime or balance changed in this
follow-up. Root inspected the delegated backend regression and both UI production files.

Five regression suites plus editor parse and the normal GL launch passed with Godot
4.5.1 stable. Each process used separate temporary APPDATA, LOCALAPPDATA and TEMP paths;
no personal saves were read or changed. The seven cases all exited zero:

| Case | Verification |
| --- | --- |
| `clothing` | Eight unique residents, four linked worker records, seven garments; one uncovered person loses 5 satisfaction points while covered people gain 5; one physical deposit and next-day recovery; reads do not allocate or consume |
| `food-ui-gl` | Rendered 7/8 shortage, reserve-ready 7/8 and covered 8/8; stock/time/needs/population refresh; zero population, nine-digit stock, repeated open/close; runtime scene retention |
| `population` | Linked workers remain one supply recipient with their resident |
| `food-daily` | Existing daily food, portion, shortage and duplicate-day behavior |
| `supply-flow-gl` | Area2D/E access, real deposit interface and worker equipment flow |
| `parse` | Editor import/parse completed |
| `main-gl` | Normal main scene launched and exited successfully |

Root inspected shortage, ready-next-day, fully covered and large-value captures at the
actual 400x225 logical viewport. Labels fit inside their panels without overlapping the
grid or each other. All three shortage/recovery captures were copied and hash-verified to:

`C:/Users/Hendro/.codex/visualizations/2026/09/13/01a09d21-3741-7360-9bd0-e04ff7988583/city-supply-summary/`

Runner and logs: `%TEMP%/tip-city-supply-summary-20260922/qa/`.
Existing certificate-store and ObjectDB/resource shutdown diagnostics remain in these
runs (15 resources; 16 during editor parse). No GDScript parse or test assertion failure
was reported. This UI task does not claim to resolve those existing diagnostics.

Canva slide 3, **City Storage Supply - Implementasi Aktual**, now mentions the supply
summary and distinguishes the confirmed human supply playtest from the locally tested
new clothing panel. The authenticated browser editor showed `All changes saved`; the
updated four-line storage label and status were also visible after reopening the design.
Slides 1/2 and other pages were retained.

Design: https://www.canva.com/design/DAG29BWgJp0/59ed7aJ8QwpNd2mIOEh31g/edit

## Final scope review and human handoff

Seven of the 64 snapshotted paths changed in this follow-up; the other 57 retain their
pre-edit hashes. This report is the only new repository file. The changes are:

- `scenes/storage_destination/city_storage_access_ui.gd` and `.tscn`
- `scenes/test_scenes/clay_worksite_test/test_scene_city_clothing_needs.gd`
- `scenes/test_scenes/clay_worksite_test/test_scene_city_food_ui.gd`
- `ROADMAP.md`, `ARCHITECTURE.md` and `docs/task_reports/city-storage-clothing.md`

The follow-up diff was reviewed against the snapshot. The accumulated branch's stock
transactions, physical access, shared intake policy, runtime provider, needs evaluation,
worker Details and Inventory Send removal were also inspected for the handoff. Earlier
checkpoint regressions remain recorded in their original task reports; they are not
represented as newly rerun suites here. The parked workshop worktree and the branch/HEAD
recorded above remain unchanged. No commit, push, PR creation or merge was performed.

The prior clothing lifecycle and satisfaction checklist is human-confirmed. The only
new human check is the summary's presentation in normal use:

1. F6 `scenes/test_scenes/clay_worksite_test/test_scene_city_clothing_playtest.tscn`.
2. Press N once, then E at the City Storage area.
3. Check the Clothing Supply panel: People 1, Covered 1/1, Reserve 1, Awaiting 0,
   Short 0, All covered. Food Supply and the item grid should remain readable.

The 8-person shortage/restock/recovery sequence is already covered by automated backend
and rendered integration tests; repeating the complete seven-day playtest is unnecessary
unless the new visual check finds a problem. Human review of this panel and the accumulated
diff remains before committing/publishing the branch. The Game Director owns merge approval.

## Prepared commit / PR description

Suggested title: `feat(storage): complete physical city supply and needs visibility`

City supplies now come from the shared physical City Storage. Players deposit eligible
food, clothing, Shekel and worker tools at its Area2D; incoming Haulers use the same item
policy, and deposited goods stay city-owned. Raw materials and Gold Nugget are rejected
without partial transfer. Worker equipment selection uses the same city provider.

Daily food uses ready meals and retained portions. Clothing supplies one unique person
for seven days and renews automatically when stock exists. Worker Details shows individual
Food/Clothing/Shelter results and the approved satisfaction/reliability changes. The storage
menu shows food availability and clothing coverage, reserve and shortage; depositing a
garment updates reserve immediately and coverage at the next daily evaluation.

Validation: the earlier supply/filter/clothing checkpoints include targeted regressions
and the Game Director's manual passes. The final summary follow-up passed five regression
suites, editor parse, GL launch and rendered checks, including seven garments for eight
people and next-day recovery after one deposit. New panel visual review is pending.

Known limits: state survives scene changes within the current session; restart save/load,
city-to-workshop hauling, Shekel spending and city capacity balancing remain deferred.
Existing certificate-store and shutdown resource diagnostics are documented above.

## Title / Close layout follow-up - 2026-09-23

The Game Director requested an independent top-right Close button so City Storage's
title can be centered. This Level 1 UI-only change keeps the current branch and baseline
with its 65 pre-existing dirty paths. `city_storage.tscn` now places Close directly under
CityStorage, anchored top-right, while the Title label fills its existing row and centers.
The physical access script, Worker Hub script and existing WorkerControl regression now
use the new `Close` path. No supply, balance, input-map or project-setting changes.

Godot editor parse, normal GL launch, WorkerControlTest (GL) and CityFoodUITest (GL)
passed. Root inspected the rendered physical menu and equipment picker: the title is
centered, the close icon remains separate, and neither overlaps. Existing certificate-store
and shutdown-resource diagnostics remain. Logs/captures and pre-edit copies of the four
implementation/test files are under `%TEMP%/tip-city-title-close-20260923/`.
Those four diffs were reviewed; this report records the result. No commit or merge.
The screenshot showed an unsaved Godot editor tab; its in-memory edits were not accessed
or discarded. These changes apply to the files on disk.

## Combined City Supply layout - 2026-09-23

The Game Director requested City Storage on the left, a centered Available/Equipped
summary using the existing separator asset, and one City Supply panel on the right
containing both food and clothing. Level 1 presentation-only work continued on
`feature/workers/city-storage-supply` at `4de7d0521648712b277851b9b6ec90ea07772fab`
with 85 pre-existing dirty paths preserved.

Changed files for this follow-up: `city_storage_access_ui.gd`,
`city_storage_access_ui.tscn`, `test_scene_city_food_ui.gd`, and this report.
The physical modal uses two adjacent panels with the existing food panel texture.
Its centered RichTextLabel embeds `separator_icon_2.png` between the stock counts.
The shared equipment-picker context label remains separate. All existing food/clothing
values, refresh signals and deposit behavior remain unchanged.

CityFoodUITest and CityStorageSupplyFlowTest passed with GL Compatibility, including
long quantities, shortage, retained portions, next-day clothing coverage, repeated
open/close, read-only refresh and deposit flow. The normal main scene launched and
exited successfully. Rendered screenshots were inspected at the 400x225 logical
viewport / 1200x675 desktop configuration. Other display sizes and Android were not
tested. Existing certificate-store and shutdown resource diagnostics remain.

Pre-edit copies: `%TEMP%/tip-city-supply-layout-20260923/`.
Logs and screenshots: `%TEMP%/tip-centered-headers-20260923/qa/city-supply-layout/`,
`city-supply-flow-layout/` and `city-supply-main/`.
The three source/test diffs were reviewed against the pre-edit copies; whitespace
checks passed. No protected files, gameplay, settings, commit or merge changes.
Status: PASSED — NEEDS HUMAN REVIEW.

### Wider supply and lower item info follow-up

The Game Director requested a wider City Supply and lower-centered item info.
City Supply now spans 178 logical pixels (previously 114), matching City Storage.
The combined layout stays centered with an eight-pixel gap; storage shifts 32 pixels
left and the supply right edge moves 32 pixels right. Item info centers on the viewport
and sits above the action buttons, with viewport bounds clamping.

Changed the physical access scene/script and extended the existing CityFoodUITest
with clothing/food tooltip bounds and position checks. That GL suite passed, including
all existing stock, coverage and refresh checks. Normal GL launch passed. Captured
normal and item-hover states were visually reviewed. Prior engine shutdown/certificate
diagnostics remain; other resolutions/mobile remain untested. Pre-edit copies are in
`%TEMP%/tip-city-supply-wide-20260923/`; evidence is in
`%TEMP%/tip-centered-headers-20260923/qa/city-supply-wide/` and `city-wide-main/`.
Reviewed the three diffs; whitespace checks passed. Same branch and baseline, 85 prior
dirty paths preserved. UI-only; no gameplay/settings changes or commit/merge.

## Authorized commit checkpoint - 2026-09-26

The Game Director requested committing the completed branch progress, including authored UI tweaks. Pre-commit GL checks passed: CityFoodStockTest, CityFoodDailyTest, CityClothingNeedsTest, CityStorageSupplyFlowTest, CityStorageHaulingTest, WorkerControlTest and CityFoodUITest. Staged whitespace check passed. Main launch first exited with Windows code -1073741819 without a script error; an isolated repeat completed with exit 0. The first exit remains unexplained. Existing certificate-store and shutdown resource diagnostics remain. Logs are under the temporary tip-centered-headers-20260923/qa/commit-* directories. This checkpoint does not claim save/load or Android validation. No push or merge requested.
