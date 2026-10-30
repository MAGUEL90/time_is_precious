# Staged content integration - 2026-10-27

Branch: `feature/content-scene/prepaid-integration-20261027`.
Verified base: `ce501a129e96fba95b80615410fb00dd665e00db` from `feature/economy/prepaid-worker-contracts`.
Content source remains `85dca9a8e509cfa712510c02649497b5a824e402` on the unchanged checkpoint branch.

## Stage 1: artwork and resource integrity

Selectively ported52 asset/metadata paths:48 additions and4 existing PNG replacements. All art bytes come from the reviewed content snapshot; variants and canonical UID/import settings are retained. No world scene, terrain, stockpile/date-palm removal, recipe, fee, save adapter, debug/guard, capture harness, project setting or payroll rule is included in this stage.

Validation used an isolated disposable copy of the prepaid source plus these exact assets. Only that QA copy disables MCP autoload/editor plugin to avoid sharing control ports; the production project settings are unchanged. APPDATA/LOCALAPPDATA and all test profiles are isolated under evidence, never personal saves.

- Cold headless Godot4.5.1 import: exit0, no timeout.
- `asset_organization_test`:176/176 pass, exit0; all25 image mappings, exact PNG hashes, imported dimensions/readability and canonical/retained UID resolution.
- Existing `test_scene_prepaid_contracts`:PASS,0failed, exit0. This run is a native prepaid baseline control, before batch/UI changes.
- Existing Windows root-certificate-store diagnostic remains; no parse/script failures in those runs.

No main merge, push, PR, or modification to the original preview/checkpoint branch was performed. Later UI/arrival work is separate and is not validated merely by these asset checks.

## Stage 2: prepaid candidate cards and atomic multi-hire

Ported the compact candidate-card design onto native applicants and contract quotes. Duration remains 3/6/9 days; cards show package cost rather than an invented daily wage. Candidate checks persist through scrolling. Successful hiring clears selection instead of silently selecting the next applicants. The batch backend validates every candidate and the full wallet quote before publishing all memberships and applying one debit; guarded callbacks cannot reenter recruitment.

Isolated QA uses exact final source for this stage, native payroll project settings apart from the documented test-only MCP removal, and disposable profiles:

- Native prepaid contract regression: PASS, exit0.
- Native population/employment regression: PASSED, exit0.
- New `test_scene_content_prepaid_ui`: PASS (0 failed), rendered GL runtime, exit0. Covers independent selections, all contract durations/total quotes, exact and insufficient funds, invalid/duplicate candidates, repeat clicks, observer reentry, retained worker progression on rehire, scroll, closure and empty applicants.
- Actual 400x225 and nearest-neighbor 1200x675 rendered initial/selected/insufficient states inspected. These screenshots contain test-fixture candidate names, not production applicant replacements.

Arrival-first accounting and schema8 migration are separate work in progress; these UI results do not establish their correctness or merge readiness. No rate, native single-hire contract rule, world layout, save profile or main/payroll branch changed in this stage.
## Stage 3: storage and workshop presentation

Ported compact wallet display, live capacity/storage and empty-output icons, WORKING card tint, Back-only nested navigation and persistent deposit menus. Both ItemTransfer callers refresh in place, including empty inventory and failed transactions. City storage still calls the native treasury-enabled transaction; no wallet/treasury rule is replaced.

- `test_scene_content_deposit_ui`: PASSED, exit0 (repeat/failed/empty deposits, callbacks, Back/pause, access loss and treasury cash refresh).
- `mudbrick_player_flow_test`: PASSED, exit0 (unchanged native recipes, fees and pickup flow).
- `test_scene_storage_treasury`: PASS, exit0.
- `workshop_ui_regression_test`: headless PASSED, exit0; final GL PASSED, exit0. The first GL run passed assertions but crashed during teardown. Fixture cleanup now queues UI deletion and drains two frames before exit; assertions and production code were not weakened. The native crash cause is not proven beyond this successful focused repair/control.

All evidence uses isolated profiles/MCP-disabled disposable QA copy. Windows certificate-store warning persists. No manual F6 or production-profile execution is claimed.
## Stage 4: physical arrival and schema8

New site and authored workshop assignments synchronously record bounded feet position, target, task/owner, pending/arrived state and arrival minute on WorkerData. Physical motion consumes frame time, follows copied authored solid geometry and preserves WALK animation; a clock jump alone cannot move or credit workers. The daily task includes workday identity. Workshop production and construction intersect paid time with arrival time once, preserving native team denominator/remainder, recipes, contract prices and duration options. Empty approach state deliberately preserves the historical interpretation of valid schema1-7 active work.

The writer is schema8. Strict version1-7 readers/migrations omit the new field; schema8 validates exact types/keys, finite bounded coordinates, authored targets and active task ownership before applying. Older builds are not promised to read schema8. Personal saves are never used. Native home parking retains the route owner; CityStorageArea now binds its existing persistent storage by stable absolute node path so reparenting cannot invalidate the endpoint. A valid next-day assignment made after closing is accepted before midnight.

Final targeted results (Godot4.5.1, isolated profiles, recorded OS exit0 and no timeout):

- Editor import: exit0, no script/resource parse failures.
- ContentActualArrival GL: PASS, actual WALK frame sequence light_walk_left0,1,2 with11.1328logical-pixel feet movement; pending time jumps, reassignment, paid expiry/resumption, hidden retained processing, before/open/midshift/closing and evening save validation.
- SiteArrivalContinue: write/read PASS in separate processes for pending and arrived checkpoints; exact feet/task restored and no prearrival output.
- WorkshopArrivalSchema8: PASS; native uncleared/clear/build/production, route budget, no-frame jumps, paid/arrival union accounting, schema1-7 migration, malformed schema8 rejection and retained home ownership.
- Workshop separate-process write/read for travelling and arrived city checkpoints: all4pass. Home travelling/arrived write/read: all4pass after stable-storage-binding repair.
- Managed workshop expiry case: PASS. Real three-day hire and renewal, existing nine-day production option, expiry while pending/arrived, frozen unpaid motion/progress, exact wallet quote once, no treasury change/backfill/duplicate output, and precise paid-minute resumption.
- Native PrepaidContractsFixtureTest: PASS,0checksfailed; CitySaveValuesTest:PASS; CitySaveFileTest:PASSED; CitySaveTest:PASS (including pickup/palm persistence, historical migrations and corrupt input refusal).
- ContractContinue real startup sequence write/read/readrenew/legacy-read/legacy-renew-read/assignment-write/assignment-read: all7pass in separate processes. Assignment fixture now physically reaches entry before retaining its original three-minute progress/cash/save assertions.

Fixture corrections were kept separate from production rules: successful workshop output uses native held output_lots, not overflow-only claimable_outputs; body clip names include skin prefix; WALK proof observes frame_changed events rather than an aliased first/last frame. Legacy fixture payloads strip fields absent from their declared version. Historical payroll Continue/cargo/sleep suites retain superseded pre-prepaid expectations and were not treated as passing acceptance; compatibility-only edits do not claim their old semantics are current.

## Review status and limits

This is a selective local integration checkpoint, not a merge/release approval. Main and the content checkpoint refs remain unchanged. The original preview and media remain untouched. Project settings, native startup/save namespace, terrain/map, stockpiles, date palms, treasury policy, recipes and contract rates retain the prepaid baseline. Recording supplies/money, guard, capture/timejump harness, focused map deletion and session-only save adapter are excluded; preview NPC/story/world artwork fitting is not silently applied to the production city.

Navigation uses actual authored solid/tile-physics geometry. Production has no authoritative shoreline/walkability metadata, so focused-preview sand/source IDs were not guessed or ported; shoreline enforcement remains a separate authored-world task. No manual F6, human playthrough or dynamic crowd-avoidance acceptance is claimed. All automated runs use the documented disposable MCP-disabled QA copy, with no screen takeover. The Windows root-certificate diagnostic persists; expected malformed-checkpoint warnings are logged by rejection tests.

Evidence, disposable profiles, exact source hashes, screenshots and original backups are under the sibling preview evidence/integration-implementation-20261027-01 folder. No media/cache/secrets/backups are staged. The historical audit and duplicate backup directory remain untracked for preservation; automatic approval review rejected recursive duplicate-backup cleanup, so it was not bypassed.