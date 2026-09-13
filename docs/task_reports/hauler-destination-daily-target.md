# Hauler destination and daily target

Date: 2026-09-13
Status: PASSED — NEEDS HUMAN REVIEW
Branch: feature/process-workshop/clay-worksites
Baseline: 0f971ab330b83e2c8502ef943ddd04e94019565a
Starting tree: dirty; existing human scene/asset/code changes preserved.
Risk: LEVEL 2 limited integration within the approved worksite prototype and reusable StorageDestination. No new global service or protected settings changes.

## Scope and behavior

Implements the approved first MVP step: choose a destination and a positive daily item target when adding a Hauler. The form starts with the editable 20-item example. Cart capacity remains three items per trip.

- Selecting a Hauler with its required cart opens the compact Hauler Delivery form. Cancel/animated close returns to worker selection without adding the Hauler.
- Confirm stages the worker, destination and target together. Next returns to the main worksite panel; Start Work commits the plan for the next day at 07:00. Closing the main panel discards uncommitted setup.
- Storage endpoints under the fixture register themselves in the `storage_destinations` group. Existing explicit site mappings remain available. Each endpoint exposes `display_name`; set distinct names in the Godot Inspector. Selection stores the endpoint path, independently for each Hauler.
- Destination availability and worker eligibility are rechecked on confirmation and job start. Full storage remains a valid destination but prevents loading until it has capacity.
- Target progress counts successful storage receipts only. A target of 20 uses loads `3 + 3 + 3 + 3 + 3 + 3 + 2`, including the last partial load while natural stock is still available.
- Upon reaching the target the Hauler completes its return leg, stops new deliveries, and keeps the standing Daily assignment. The existing roaming behavior applies outside active hauling. The next day starts a fresh delivery counter with the same destination and target.
- Failed unloads return cargo to the worksite without target progress or XP. Existing rules for shift-end completion and removal in transit remain.
- Worker Progress includes destination and `Today: received / target items`. Productive days and XP continue to count actual contribution.

No gathering rate, cart capacity, equipment effect, level threshold, or worker identity was changed. Persistence and player-to-city tool procurement remain separate MVP steps; these plans and fixture storages are still scene-local.

## Try it

Open `scenes/test_scenes/clay_worksite_test/test_scene_hauler_delivery_setup.tscn` and press F6. The scene provides Arad, Belum with a cart, and Storage A / Storage B. It opens Clay Site A's menu.

1. Choose Worker, assign Arad, then choose Belum. Select Storage A or Storage B and set the target. Confirm with Assign.
2. Next → Start Work. Once menus are closed, F advances to the next day at 06:45; F7 advances 30 minutes. K opens Worker Hub.
3. Reopen the worksite's Worker Progress to inspect its destination and daily receipts. Repeat F to test tomorrow's standing assignment.

The original `test_scene_clay_worksite_hauler.tscn` demo still auto-schedules its team; its interactive target is now 20. Its legacy stress-test mode uses a high explicit target so removal, rejection, and end-of-shift scenarios remain reachable.

Editable form: `scenes/test_scenes/ui_sandbox/clay_worksite_inspector/hauler_delivery_setup.tscn`. Panel geometry, labels and buttons are scene-authored. Its local script binds data and applies the existing pixel font/button theme to form controls without changing shared themes.

## Verification

- HaulerDeliverySetupTest: passed headless and graphical 1200×675; two destinations, two independent targets, non-mutating open, cancel/close/reopen, empty storage, invalid targets, stale destination recheck, next-day start, final 2-item load, exact stop, full/rejected delivery, same destination on the second day, clay conservation, proportional XP, productive days, and F8 debug advance.
- Graphical captures inspected: setup, no storage, long values, and Worker Progress. Panel content remains within the viewport. Names and targets do not resize the setup panel.
- ClayWorksiteHaulerTest: passed; repeated trips, rejected cargo return, in-transit removal, final depleted-site load, and post-shift completion.
- WorkerControlTest: passed graphical and headless; equipment, employment, worksite navigation, and stable Tools layout.
- WorkerToolsLayoutTest, ClayWorksiteDailyTest, ClayWorksiteGatheringTest, StorageDestinationTest: passed.
- Main project headless launch: exit 0.
- Reviewed task diffs against pre-edit copies, plus whitespace checks. No pre-existing scene layout, assets, production autoloads, dependencies, or project settings edited in this task.

During development, visual review caught default-font styling and an auto-wrap minimum-size expansion in Worker Progress; both were corrected and graphical validation repeated. A headless-only WorkerControlTest failure came from its screenshot helper skipping layout settling; the helper now waits for containers in both modes, and headless validation passes.

Existing engine diagnostics remain: root certificate store error and ObjectDB/15-resource shutdown warnings. No new blocking errors remain. No Android or save/load compatibility validation is claimed.

## Files and ownership

Modified: `storage_destination.gd`, `clay_worksite_hauling.gd`, `clay_worksite_daily.gd`, `clay_worksite_assignment_ui.gd`, `test_scene_clay_worksite.gd`, `clay_worksite_inspector.gd`, `test_scene_clay_worksite_hauler.gd`, `test_scene_worker_control.gd`.

Added: `hauler_delivery_setup.gd/.tscn`, `test_scene_hauler_delivery_setup.gd/.tscn`, and this report. No deletions or renames.

Astra root: inspection, implementation, test fixture, executed validation, visual review, and documentation. Luna XHigh: no delegation. No commit, push, or merge.

## Follow-up: retain setup when reopening Worker (2026-09-13)

Status: PASSED — NEEDS HUMAN REVIEW. Risk: LEVEL 1 local UI correction, same branch/baseline and existing dirty tree.

The user reported that Next showed 2/2 workers, but returning to Worker erased them. `_show_roster(true)` emitted `worker_setup_discarded` every time the roster opened. Removed that emission: reopening now reads the same unstarted worker selections, storage choice, and daily target. Explicit Back → Yes and closing the main worksite menu retain their existing discard behavior. No scene layout or gameplay values changed.

Extended `test_scene_hauler_delivery_setup.gd` to reproduce repeated Next → Worker → Next, verify both slots plus the complete Hauler plan, check Back → No retention, and exercise Worker Progress through its visible button. The new assertions failed before the fix and passed afterward, headless and graphical at 1200×675. Reopened 2/2 slots and the main-menu Worker Progress button were captured and inspected. ClayWorksiteDailyTest and main-project launch also passed; existing engine shutdown diagnostics are unchanged.

Worker Progress appears in the bottom-left footer of the main worksite menu after Start Work commits a standing assignment. Next alone stages settings and does not show this progress button. Each Hauler still has one chosen storage endpoint; no multi-stop route editor was added.

Changed in this follow-up: `clay_worksite_inspector.gd`, `test_scene_hauler_delivery_setup.gd`, and this report. Compared against pre-edit copies; no unrelated changes, settings, assets, or production systems touched. Astra root performed all work; no subagent delegation or Git publication.
