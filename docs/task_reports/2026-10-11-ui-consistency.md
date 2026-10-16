# Current-loop UI consistency pass

Branch: `fix/gameplay-hud/ui-consistency`.
Baseline: `c814cf3` (sleep autosave and Shelter display); starting tree clean.
Risk: **LEVEL 2 — LIMITED UI INTEGRATION**. Authorized by the request to tidy all
UI and the follow-up “Pertahankan gaya, rapikan semua UI”.
Status: **PASSED — NEEDS HUMAN REVIEW** for the active-loop polish described here.
Human visual acceptance and merge remain pending. Root reviewed two narrow helpers
(Job Board empty state and inventory popup bounds) and all resulting diffs.

## Scope and acceptance

Audit the current playable HUD, City Hub, raid inspection/report/notifications,
inventory/actions/item transfer, physical City Storage, merchant, NPC greetings,
Worker Hub, hiring, workshop construction/assignment/production/storage and Work
Progress. Preserve the existing Mesopotamian pixel assets, English text, 400x225
logical viewport and player actions. Correct observed spacing, alignment and
clipping. Keep pixel font sizes at the existing 6/12/18 steps and retain native
icon pixels. Screens already fitting and readable retain their existing layout.

Gameplay, economy, progression, raid numbers, save data/schema, dialogue meaning,
input mappings, autoloads, plugins and project settings are outside this task.
Experimental/orphaned menus are not silently activated or redesigned.

## Implemented corrections

- Shared HUD small-label variants and the older side-action caption use size 6
  instead of 10. Existing 12/18 headings remain. Disabled HudShortcutButton text
  now uses the same muted brown as the established workshop square-button states.
- Shelter uses a three-line, 24px-high row matching Food and Clothing: values,
  capacity/need meaning, then short/spare/covered status. The house texture remains
  native and nearest-filtered. The City Hub frame remains 300x196 in both tabs.
- Inspect has 16px content margins, 4px section gaps and sufficient height for
  its title, ETA, cards and Back button. Fixed-width centered raider cards no
  longer stretch across the whole panel when fewer types are present; their
  brown fill matches the existing list palette. No composition data changes.
- Physical City Storage is centered. Its former left offset still reserved
  space for the old separate Supply panel, which is now part of City Hub.
- Both inventory item-confirmation entry paths clamp the actual popup bounds
  to the viewport with the existing 4px margin. Dropping near an edge no longer
  puts its confirmation buttons offscreen. Quantities/actions remain unchanged.
- Job Board centers the existing empty-state message in the vacant applicant
  region. Its feedback row stays reserved for errors and successful hiring;
  the frame and populated selection/hiring flow remain the same.

## Changed files

Modified production presentation:
- `resources/ui_gameplay_theme/ui_gameplay_theme.tres`
- `scenes/ui/hud_side_action/hud_side_action.tscn`
- `scenes/ui/inventory_ui/inventory_ui.gd`
- `scenes/ui/job_board_ui/job_board_ui.gd` and `.tscn`
- `scenes/storage_destination/city_storage_access_ui.tscn`
- `scenes/raid/raid_ui.gd`
- `scenes/raid/raider_inspection_panel.gd` and `.tscn`

Modified verification/documentation:
- `scenes/test_scenes/test_scene_inventory_modal_pause.gd` (both edge-popup paths)
- `scenes/test_scenes/test_scene_raid_ui.gd` (frame padding and captures)
- `scenes/test_scenes/test_scene_traveling_merchant_access.gd` (fixture setup only)
- `ROADMAP.md`

Created: this report. No files deleted, renamed or new assets introduced.
The reviewed editor-generated changes in `project.godot` and three Dialogue
Manager SVG imports are excluded under the user's existing cleanup authorization.

## Verification and evidence

Godot 4.5.2, Linux/Xorg, GL Compatibility, 1200x675 native window and unchanged
400x225 logical viewport. Final editor import/parse exited 0 with no script errors.
Thirteen current-flow native fixtures passed after the edits:

| Fixture | Coverage |
| --- | --- |
| `test_scene_raid_ui` | Notifications, Inspect/card counts, padding, supply/footer fit, reports and repeated refresh |
| `test_scene_city_progression_hub` | Fixed tab size, icons, level-up, dense construction/attack and breach display |
| `test_scene_inventory_modal_pause` | Both confirmation paths at bottom-right edge; modal open/close and pause ownership |
| `clay_worksite_test/test_scene_city_storage_supply_flow` | Physical storage, deposit, equipment, access and reopen lifecycle |
| `ui_layout_review_test` | Eight workers, long name, transfer, empty hiring/progress/storage |
| `main_map_hauler_start_test` | Populated Job Board, real hiring and cart equipment |
| `test_scene_traveling_merchant_access` | Buy/sell, quota/funds/capacity states, long balance, departure and repeated use |
| `test_scene_traveling_merchant_greeting` | Greeting, choices, trade entry and dialogue lifecycle |
| `test_scene_defense_dialogue` | Iddin greeting/quotes/choices, construction, watchtower and live Inspect |
| `clay_worksite_test/test_scene_worker_control` | Status, tools, equipment, needs/details, management and popup bounds |
| `mudbrick_player_flow_test` | Production list/details, job review, work progress, fees and output |
| `workshop_construction_ui_test` | Clearing, worker selection/assignment, construction and upgrades |
| `condition_hud_regression_test` | Existing player-condition HUD layout and state |

Logs: `/tmp/ui-polish-*.log`; editor: `/tmp/ui-polish-editor.log`.
Baseline captures: `/workspace/scratch/ui-polish/before/`.
Final captures: `/workspace/scratch/ui-polish/after/` (125 PNGs including the
existing emergency pulse sequence). Representative screenshots were reviewed
visually; the count is not a claim that every pulse frame was individually audited.

Two historical fixture findings were kept explicit:
- Merchant Access initially failed before polish because it assumed the first
  visit was day 1, while the map now enables a day-0 debug visit. The fixture now
  opts out of that debug flag before entering the tree. Production scheduling is
  untouched; the full existing accounting/access test then passed.
- `clay_worksite_test/test_scene_city_food_ui` failed during the baseline audit.
  It still asserts a visible separate Supply panel beside physical storage and
  older fixture consumer counts. That obsolete layout fixture is not migrated in
  this presentation pass and is not counted as passing. Current City Hub Supply
  is checked by the Raid UI/City Progression fixtures, and physical storage by
  City Storage Supply Flow. Its log is
  `/tmp/ui-audit-clay_worksite_test-test_scene_city_food_ui.log`.

The pre-existing godot-mcp localhost port 9877 listener error and virtual-driver
VSync warning remain environment messages. Final current-flow runs have no script
errors or leaked-object warnings. `git diff --check` passes.
Windows/Android execution and every unused prototype screen are unverified.

## Where to edit current screens

| Screen | Current source |
| --- | --- |
| Shared HUD text/buttons | `resources/ui_gameplay_theme/ui_gameplay_theme.tres` |
| Top/bottom HUD | `scenes/ui/top_hud/`, `scenes/ui/bottom_hud/` |
| City Hub / notification / raid report | `scenes/raid/raid_ui.tscn` and `.gd` (dynamic rows live in the script) |
| Raider cards | `scenes/raid/raider_inspection_panel.tscn` and `.gd` |
| Inventory | `scenes/ui/inventory_ui/`, `scenes/ui/item_action_confirm_panel/` |
| Physical City Storage | `scenes/storage_destination/city_storage_access_ui.tscn`, `city_storage.tscn` |
| Job Board | `scenes/ui/job_board_ui/` |
| Live Worker Hub | `scenes/test_scenes/ui_sandbox/worker_control/worker_control.tscn` and `.gd` |
| Workshop panels | `scenes/ui/workshop_*_ui/` |
| Merchant trade | `scenes/ui/traveling_merchant_ui/` |
| NPC dialogue frame | `dialogue/game_dialogue_balloon/game_dialogue_balloon.tscn`; compact fitting in the merchant/caretaker scripts |

The similarly named `scenes/ui/worker_hub_ui/` is an older unreferenced prototype,
not the Worker Hub opened from the main map. Its placement is recorded, not renamed.


## Follow-up: remove all game tooltips (2026-10-11)

The Game Director explicitly requested removal of all tooltips, including the
item descriptions that appeared on hover. This continues the same UI-polish
branch, `fix/gameplay-hud/ui-consistency`, from clean baseline
`ba8cff90946b1aed09ea8021b1d02e1c3b1b1a03`. Risk: Level 1, UI presentation only.
Acceptance: no game tooltip appears on hover; item actions, selection, equipment,
transfers, notifications and explicit Details/Inspect panels still work.
Gameplay, saves, balance, dialogue, project settings and editor plugins are outside scope.

Removed native tooltip text from notifications, city satisfaction/wall metrics,
raid loot icons, Debug controls, unavailable workshop workers and hauler
storage destinations. Job Board explicitly disables ItemList's automatic item
text tooltips whenever it rebuilds its applicant list.

Removed item-info panel instances and hover bindings from Inventory, City Storage,
Worker Hub equipment, item transfer and workshop storage. Inventory no longer
reopens that same description panel when selecting an item. Its page selector no
longer depends on the removed panel node. The unused shared ItemInfoPanel resource
files remain in the repository; no game UI instantiates them. Hover selection
frames and clickable action/Details/Inspect panels retain their existing behavior.

Changed source files in this follow-up:

- `scenes/debug/time_debug_overlay.gd`
- `scenes/raid/raid_ui.gd` and `raid_ui.tscn`
- `scenes/storage_destination/city_storage_access_ui.gd`
- `scenes/test_scenes/ui_sandbox/clay_worksite_inspector/hauler_delivery_setup.gd`
- `scenes/test_scenes/ui_sandbox/worker_control/worker_control.gd`
- `scenes/ui/inventory_page_selector/inventory_page_selector.gd`
- `scenes/ui/inventory_ui/inventory_ui.gd` and `inventory_ui.tscn`
- `scenes/ui/item_transfer_ui/item_transfer_ui.gd`
- `scenes/ui/job_board_ui/job_board_ui.gd`
- `scenes/ui/workshop_storage_menu_ui/workshop_storage_menu_ui.gd`
- `scenes/ui/workshop_worker_assignment_ui/workshop_worker_assignment_ui.gd`
- The existing Worker Control and City Food UI fixtures now check the requested
  absence of hover descriptions instead of expecting the removed panels.
- This report.

No files were created, deleted or renamed. Four editor-generated metadata changes
were inspected, backed up and restored under the user's prior authorization;
`project.godot` and addons are unchanged in the final diff.

Validation: Godot 4.5.2, GL Compatibility, Linux/Xorg, 1200x675 window,
unchanged 400x225 logical viewport. Editor parse/import passed without script
errors. Nine existing fixtures passed:

- Inventory Modal Pause (including item action popup navigation)
- Worker Control (including equipment hover and equip/unequip)
- City Storage Supply Flow (including deposits and item transfer)
- Raid UI (including City Hub, notifications, Inspect and reports)
- Hauler Delivery Setup (`TIP_TEST_HAULER_TARGET=1`)
- Workshop UI Regression (including worker availability and explicit Details)
- Workshop Construction UI
- Main Map Hauler Start (including populated Job Board)
- UI Layout Review

The first hauler launch opened the fixture's manual mode and was stopped; the
correct automatic-mode rerun passed. The legacy City Food UI fixture still fails
its old separate-Supply-layout and consumer-count expectations. Comparing its
error messages with the pre-change baseline found no new errors; its updated
no-tooltip checks produced no failures. This legacy test is not counted as passed.

A final source audit finds only empty tooltip assignments, explicit tooltip
suppression and test assertions in game code. No game UI still references the
ItemInfoPanel scene. Reviewed captures show Inventory's item action confirmation,
Worker Hub equipment storage and raid results without hover descriptions.
Evidence: `/workspace/scratch/no-tooltips/` (logs and `captures/`).
The native dummy-display VSync warning and unavailable host audio device were
observed; the hauler rerun used the Dummy audio driver. No script errors or
leaked-object warnings were found in current-flow tests. `git diff --check` passed.
Windows and Android execution remain unverified. Status: PASSED — NEEDS HUMAN REVIEW.

## Screenshot follow-up: panel stacking and pixel layout

Continued on `fix/gameplay-hud/ui-consistency` from clean `0ab0c49`, within the
requested Level 1 UI scope. Notifications now use 16px content margins and a
bottom-aligned Close button. City Hub and its passive notification icon render
below Inventory, Job Board, Worker Hub, immigration and workshop job modals.
Escape closes the foreground Inventory without also dismissing City Hub below.
Supply uses native 16x16 nearest-filtered icons within integer-padded 24px columns;
tab panel dimensions remain unchanged. Job Board uses a square pixel focus border.
Its already-disabled automatic tooltips were verified with a real populated list,
mouse hover and a wait beyond the native tooltip delay.

Changed production files: `scenes/raid/raid_ui.gd`, `raid_ui.tscn`, Inventory's
script and scene, Job Board's scene, immigration request and workshop job scenes,
and both the active sandbox Worker Control and legacy Worker Hub scenes. Four
existing fixtures were extended: Raid UI, City Progression Hub, Inventory Modal
Pause and Main Map Hauler Start. No gameplay, balance, saves, settings or assets
were changed. The user's separate asset commit is pending remote availability.

Godot 4.5.2 editor import passed. Eight native Linux/Xorg fixtures passed:
Raid UI, City Progression Hub, Inventory Modal Pause, Main Map Hauler Start,
City Storage Supply Flow, Worker Control, Workshop UI Regression and UI Layout
Review. Inventory Modal Pause was rerun after the Escape propagation fix and
passed. Runtime captures were inspected for notification margins, native Supply
icons, foreground Inventory and Job Board hover without a tooltip.

Evidence: `/workspace/scratch/ui-followup/` (logs and `captures/`). Window 1200x675;
logical viewport remains 400x225. Only the dummy-display VSync warning was observed
in native runs using Dummy audio. No script errors appeared. Four editor-generated
metadata files were backed up, inspected and restored under the user's existing
authorization. Windows and Android remain unverified.
Status: PASSED — NEEDS HUMAN REVIEW.
