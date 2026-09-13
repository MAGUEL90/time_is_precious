# Worker Hub, tools and contribution XP

Date: 2026-09-11
Status: PASSED — NEEDS HUMAN REVIEW
Branch: feature/process-workshop/clay-worksites
Baseline: 0f971ab330b83e2c8502ef943ddd04e94019565a
Starting tree: dirty, existing local edits preserved.
Risk/scope: limited integration in worksite test fixtures, reusable city tool storage and sandbox Worker Hub. No production autoload, project-setting, worker resource schema or existing workshop Hub rewrite.

## Approved behavior implemented

- Worker Hub has Status, Tools and Level tabs. Status lists active assignments first, activity, location and Productive days, with Manage and confirmed Remove.
- Tools are owned by CityToolStorage, not the UI. Each physical unit has a unique ID and at most one equipped worker. Distinct units of the same type can be assigned independently. Any worker may receive tools.
- Hauler requires an equipped cart before selection/assignment. Missing requirement appears in red in the assignment selection page; selection is rejected. Non-Hauler equipment remains optional in this MVP.
- Tools cannot be changed while Working/Travelling or during an active Daily shift. Optional tools may be changed when off shift. An assigned Hauler retains its required cart until its Daily assignment is removed. Loaded removal finishes its existing trip first. After removal the cart remains equipped until explicitly returned through Tools; it is not silently shared.
- Productive days increments only on a day with at least one completed contribution. Waiting or an incomplete gathering cycle does not count. This replaces the old Days worked / Days delivered labels.
- User-approved rate: one profession XP per gathered item; one profession XP per successfully delivered item. Rejected deliveries, walking and waiting award none. Productive days is informational and never multiplies XP.
- Level tab displays current profession, existing star value, XP total and contributions. No automatic star increase or invented XP threshold/progress-bar percentage.

## Ownership and limits

CityToolStorage is a reusable Node holding unique tool units. Fixture seeds supplies via `test_hauler_carts`; the Hauler demo provides one cart and an optional Stone Hammer. Inventory-to-City-Storage deposit/withdraw UI, real cart ItemData/art, durability and optional-tool bonuses remain unimplemented. No procurement is simulated beyond explicit test supplies.

WorkerData.profession_xp owns current-profession XP. The fixture keeps productive-day and contribution history across assignment removal/reassignment within the same scene. Profession switching/multiple historical profession tracks and persistence across scene reload/save are not implemented. Existing test-scene lifetime limitations remain.

The old production WorkerHubUI workshop job panel is preserved. The new worker control is attached only to the clay worksite fixture. Daily target quantity/destination selection UI is still a separate pending approved feature; this task does not claim it exists.

## Playtest

Open `scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite_hauler.tscn`, press F6, then K for Worker Hub. Close menus and press F7 to advance 30 minutes. The demo starts with Laborer and equipped Hauler scheduled for tomorrow, with one cart and optional hammer in city supplies.

Check XP after gathering/delivery; Manage opens Tools; try changing equipment during a shift; Remove with No/Yes; once unassigned, Unequip returns the cart to city supplies and allows allocation to another worker. Main fixture defaults to no seeded cart; missing-cart feedback is exercised automatically in the WorkerControl test.

## Validation and evidence

- WorkerControlTest PASSED headless and graphical at 1200x675: optional tools, distinct units, exclusive cart allocation, mandatory requirement, red assignment feedback, work locks, off-shift Unequip through actual button, 1 XP per item, partial-shift XP, productive days, no auto-star, Hub open/pause/close, Remove No/Escape/Yes and retained XP/history.
- ClayWorksiteHaulerTest, ClayWorksiteDailyTest, WorksiteCommuteTest PASSED.
- Main launch exit 0; git diff --check passed. Targeted source/scene review completed; unrelated local edits preserved.
- Graphical captures inspected: `%TEMP%/worker-hub-status.png`, `worker-hub-tools.png`, `worker-hub-level.png`, `worker-hub-remove.png`, `worker-cart-required.png`.
- Initial Tools overlap and red panel fallback found during visual review were corrected and rerendered. Actual Tools selection/Unequip button tests pass after correction.
- Existing certificate-store and ObjectDB/15-resource exit diagnostics remain; no new blocking runtime errors.

## Changed files

Created: `scenes/storage_destination/city_tool_storage.gd`; `clay_worker_management.gd`; `test_scene_worker_control.gd/.tscn`; sandbox `worker_control.gd/.tscn`; this report.

Modified: worksite fixture, Daily scheduler, assignment UI, worksite inspector, Hauler demo/test. No asset deletion, settings or protected governance changes. No commit, push or merge.

## Execution ownership

Astra root owned model/integration decisions, City Storage tools, equipment guards, productive days, XP wiring, all executed regression/graphical tests, visual corrections and final review. Luna XHigh implemented the bounded tabbed Worker Hub scene/script. Root reviewed and corrected the delegated UI before acceptance; no gameplay decisions delegated.
