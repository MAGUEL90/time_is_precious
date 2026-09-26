# City Storage ownership and approved direction

> Follow-up: `city-storage-item-filter.md` records the approved 2026-09-21 item restriction.
> Permanent city ownership remains; the earlier all-registered-items intake is superseded.

Date: 2026-09-20
Branch: `feature/workers/city-storage-supply`
Baseline: `4de7d05`
Starting tree: dirty, containing the previous local physical-access/shared-stock implementation.
Status: PASSED - NEEDS HUMAN REVIEW (deposit-only checkpoint; later integration remains pending)

## Authority and scope

The Game Director accepted the future storage structure in Canva slide 2 and explicitly
changed the player rule: City Storage stock cannot be taken back. This is explicit approval
for the affected ownership design (Level 4), implemented as a bounded update to the existing
city transfer backend/UI (Level 2). It supersedes the earlier withdrawable-item request.
The remaining architecture is accepted as staged direction, not represented as fully built.

Expected code scope: `city_tool_storage.gd`, `city_storage_access_ui.gd`, and the existing
city storage backend/flow regression fixtures. Root updates `docs/game-concept.md` with the
approved rule, `ARCHITECTURE.md` with actual boundaries, `ROADMAP.md` with future gates,
and the Canva diagram. The previous report is retained as a historical checkpoint.

Out of scope for this checkpoint: changing personal Workshop withdrawals, routing city goods
through a workshop without ownership tracking, citizen consumption/balance, item weights,
new capacities, production fees, autoloads, project settings, save schema changes or migration,
deleting/renaming assets, commits/pushes/merge, and modifying governance files.

## Acceptance

- Player deposits registered physical items only through the existing Area2D + E UI.
- The City Storage menu offers Deposit and no Withdraw action. Its quantity screen explains
  that deposited items cannot return to Inventory before the player confirms.
- The old backend withdrawal entrypoint rejects every request without mutation or signals.
- Free stacks, spare equipment and subsequently released equipment stay city-owned.
- Deposit validation, cancel/clear/back, stale selection and access-revocation handling work.
- Equipment remains unique; equip/unequip and home/city runtime retention still work.
- Workshop deposit/withdraw remains intact for existing personal stock.
- Diagram/design/roadmap distinguish approved direction from delivered implementation.

## Verification plan

Run the city backend and full content-flow regressions, nearby Worker Hub and Workshop UI
checks, project import/parse, and main scene launch. Render the content-flow UI at the current
400 x 225 logical viewport / 1200 x 675 window, inspect captured deposit/menu/equipment frames,
and verify Canva saves the one-way arrow and approved status. Use isolated TEMP user data for
Godot verification; preserve real saves. Review incremental diffs against pre-edit copies.

## Forward contract

City deposit transfers ownership permanently. Before the planned City -> cargo -> Workshop
path is enabled, stock/cargo/output must preserve city ownership and distinguish personal
workshop goods. Paying Held Output fees changes availability, not ownership. Mixed-owner
production rules remain to be specified before mixing lots. Citizen distribution and the
initial workshop-building handoff remain TBD, as in the accepted diagram.

Pre-edit documentation copies: `%TEMP%/tip-city-no-return-20260920/`.
Backend/UI pre-edit copies: `%TEMP%/time_is_precious_city_storage_before_20260920/`.
Test pre-edit copies: `%TEMP%/time-is-precious-city-storage-tests-preedit-20260920/`.

## Verification results

- Godot 4.5.1 import/parse: exit 0, no new blocking script errors.
- `CityToolSupplyTest`: PASSED in the root session. Valid and malformed withdrawal requests
  reject without changing Inventory, city stacks, unit IDs, allocation, supply counters or
  emitting change signals. Covers free and released equipment, repeated requests, mixed
  physical-item deposits, deposit conservation, reentrancy and invalid requests.
- `CityStorageSupplyFlowTest`: PASSED headless and in GL Compatibility at 1200 x 675 with
  the existing 400 x 225 logical viewport. Covers Area2D + E, denied distant access,
  no Withdraw control, a stale withdraw-mode request, visible no-return title, layout,
  quantity selection/clear/cancel, stale stock, repeated confirmation, physical stock,
  worker equip/unequip, home/city retention and removal of Inventory Send.
- Root retained the teardown regression by deleting the area while a Deposit dialog is open;
  the final GL run passed with both dialogs freed and movement/pause restored. Existing
  transition and live-position access revocation checks remain covered.
- `WorkerControlTest` and `WorkshopUIRegressionTest`: PASSED. Main scene headless launch
  with `--quit-after 90`: exit 0. Workshop source and its withdrawal implementation were not edited.
- Captured and visually inspected `city-storage-area.png` and `city-storage-area-deposit.png`:
  only Deposit is shown, and `Deposit to City (no return)` fits the quantity dialog.
- Canva slide 2 now says `DISETUJUI - penerapan bertahap`, uses Inventory -> City Storage,
  states no player return, and identifies permanent city ownership across locations.
  Existing slide 1 is labelled an earlier snapshot. Native editable elements were retained;
  Canva reported `All changes saved` and the final slide layout was inspected.
- Incremental source/test/documentation diffs reviewed against pre-edit copies. Existing
  unrelated dirty files preserved; no deletion, rename, dependency, autoload, project-setting
  or save-format change. `git diff --check` passed. No commit, push, PR or merge.

Godot still reports the existing certificate-store diagnostic and ObjectDB/resource shutdown
diagnostics (15 resources on runtime tests, 16 on editor import). No new script error was
observed. Android and human gameplay acceptance were not performed. This checkpoint does
not implement production disk saving, city hauling, workshop ownership routing or citizen
distribution; those have explicit remaining gates in `ROADMAP.md`.

Root QA logs: `%TEMP%/tip-city-no-return-20260920/qa/` (final GL: `render/run-final.log`).
Visual evidence: `C:/Users/Hendro/.codex/visualizations/2026/09/13/01a09d21-3741-7360-9bd0-e04ff7988583/city-storage-no-return/`.
Canva: https://www.canva.com/design/DAG29BWgJp0/59ed7aJ8QwpNd2mIOEh31g/edit

## Changed files in this follow-up

- `scenes/storage_destination/city_tool_storage.gd`: no-return backend gate.
- `scenes/storage_destination/city_storage_access_ui.gd`: Deposit-only actions and title.
- `scenes/test_scenes/clay_worksite_test/test_scene_city_tool_supply.gd`: ownership/atomicity cases.
- `scenes/test_scenes/clay_worksite_test/test_scene_city_storage_supply_flow.gd`: UI/lifecycle coverage.
- `docs/game-concept.md`: approved direction and the superseding ownership rule.
- `ARCHITECTURE.md`: delivered boundary and future ownership requirements.
- `ROADMAP.md`: accepted staged delivery gates.
- `docs/task_reports/city-storage-supply.md`: historical-rule notice.
- This report.

## Human review

Run `res://scenes/test_scenes/clay_worksite_test/test_scene_city_storage_supply_playtest.tscn`
with F6. Enter the City Storage area, press E, and inspect the Deposit-only menu. Try Clear
or Back before confirming, then deposit some items. Equip a deposited cart through Worker
Hub, unequip it, and verify it returns to available city stock without entering Inventory.
