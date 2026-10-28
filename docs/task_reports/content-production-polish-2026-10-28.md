# Content polish on the prepaid integration branch

Status: local checkpoint for human review; no main merge, push, or PR.

## Verified baselines and isolation

- Remote `main`: `d6ea244cf1a5be4a791977daa57e2806bdbdb134`.
- Remote `feature/economy/prepaid-worker-contracts`: `ce501a129e96fba95b80615410fb00dd665e00db`.
- Both remote heads were read through the connected GitHub API. Git HTTPS transport was unavailable; no remote refs were guessed or updated.
- Local integration base: `dd33915e3e07820bd618cd815a15489697572d39`, following `1735162`, `155c54e`, and `9726842`.
- Work branch: `fix/content-scene/production-polish-20261028`, created at that integration head. The previous integration and content-checkpoint branch refs remain unchanged.
- Starting working tree contained owner/editor changes in `project.godot`, three Dialogue Manager SVG import files, and untracked reports/evidence/import metadata. They were preserved and excluded from this checkpoint.
- Level 2 limited integration: the approved presentation, resource collision/navigation, and interaction polish. No contract policy, recipe, production rate, save schema, main branch, payroll branch, personal save, OBS configuration, or recording changed.

The AGENTS control pack and design/architecture/progress documents were read. No relevant checkout `.agents/skills` directory was present. The owner's explicit Sol 6.1 High request superseded the historical model defaults in AGENTS. Narrow worker/site, keeper, and cursor tasks were delegated; root reviewed and tested their actual changes.

## Selective delta

### Resource sites and workers

The integration already had real-time WALK paths, arrival-first production, foot sorting, and open-shift assignment. These were retained rather than replacing them with the older preview base scripts. Native shift hours remain 07:00–15:00. New assignments before opening wait for opening, those within the shift depart that day and produce only after actual arrival, and assignments at/after closing use the next shift. Prepaid 3/6/9-day quotes, paid intervals, expiry/renewal, and atomic hiring remain unchanged.

Latest clay/reed artwork already existed at `assets/objects/worksites/clay_site.png` and `reed_site_content.png`. Main-map references now use it. Sprite offsets retain the former opaque contact bottom at site Y+6 and schema8 slot target Y+11.5; site/world positions and stored target identities are unchanged. A resource helper supplies matching real player collisions and opaque-bottom Y-sort anchors. Navigation refreshes on workshop phase changes, and retains the copied city geometry while parked at home.

Workers with no matching work clips for hair/clothes keep those unsupported layers absent consistently across idle/walk/work. Linked citizen data and player appearance are unchanged. Reed workers remain visible in travel, hide only with matching physical arrival and native WORKING status, then reappear on withdrawal/shift exit. A separate water splash replaces the hidden worker's work effect and stops on pause/transition.

Reed output selects a path-reachable point outside authored solids, merges existing stacks, and keeps unclaimed units if no safe point exists. Tests physically move the player along the route and invoke the native E pickup handler. **This proves current authored-solid access, not dry-shore classification:** the production world still has no authoritative walkable/dry tile metadata. The focused preview's atlas IDs were deliberately not copied. A future shoreline-authoring decision must define that metadata/collision before claiming arbitrary future terrain edits cannot place output in water.

### Main workshop keeper and art

Only `main_workshop` uses the reusable keeper presentation. `workshop_2` retains its existing board. The native positions and plot IDs remain intact. Existing canonical `assets/objects/workshop_1.png`, `vase_type_1.png`, and `barrel.png` match the owner's preview bytes, so no duplicate artwork or UID was retained.

The building/footprints shift 11 logical pixels horizontally within the plot so the artwork's doorway aligns with the existing schema8 entry feet `(0,24)`. The 12-pixel opening fits the existing navigation clearance. Physical player entry/rear-wall contact and actual worker entry are tested. No separate product icon overlay is added; menu output/upgrade logic is native.

The keeper is bald, with brown beard and sash_tunic layers synchronized to the game's left/right facing convention and stable one-pixel deadzone. Its interaction area is 20 logical pixels; native E focus is tested from adjacent 16-pixel approaches. The E prompt follows visible directional art at a measured four-pixel gap. The workshop-only balloon reuses the wall caretaker panel, responses, typewriter and close conventions, places responses above text and normally anchors eight pixels below visible player art with viewport clamping. Clearing/building text leads to native menus; completed workshop E belongs directly to the native backend, without a blank greeting. Cancellation does not start work or charge inventory.

### Cursor

The owner's native 32×32 PNG is byte-identical at `assets/ui/ui_icon/cursors/mouse_icon.png`. A Player child installs it with alpha-derived hotspot `(6,1)` and restores defaults on leaving gameplay. It preserves native size, rejects empty/oversized input, supports arrow/hand/ibeam and skips native calls headless. No viewport/project settings or autoload change is required.

## Deliberately excluded recording setup

No three-Laborer applicant override, global tooltip suppression, preview supplies/money, always-on guard, 1h/3h/6h preview controls, capture/autorun harness, focused-map layout/terrain replacement, stockpile/date-palm deletion, session-only save adapter, or treasury-routing replacement was ported. Existing production debug behavior was not replaced by recording defaults. Main terrain, house, stockpiles, native applicants and normal startup remain native.

## Verification and evidence

Godot 4.5.1 GL Compatibility on Windows. All runs use a disposable tracked-source QA copy with isolated APPDATA/LOCALAPPDATA/USERPROFILE; MCP is disabled only in that copy. Graphical runs are hidden/offscreen and do not operate the user's mouse/keyboard or stop their game. No manual F6 or Android acceptance is claimed.

Evidence and targeted before-edit backups: sibling `polish-integration-20261028/` (`backup/`, `verified/`, `worksite-final/`, `acceptance/`, `regression/`, `cross-process/`). Final outcome JSON files record OS exit codes; passing markers alone are not used to accept runs containing parse/resource failures.

- Cold import/parse completed with exit 0; existing Windows certificate-store/system-directory diagnostics are documented baseline environment warnings.
- Native prepaid contract regression, storage treasury, save values and save file suites: exit 0.
- Prepaid candidate UI/atomic batch regression: GL exit 0, including invalid/insufficient/exact quotes, repeated selection/Hire, duration options and closure.
- Native content actual-arrival regression: GL exit 0, including real WALK frame changes, bounded physical movement, reassignment, shift/time-jump and paid-arrival accounting.
- Cursor fixture: headless and GL exit 0; native image, hotspot, limits and repeated install/cleanup.
- Worksite presentation fixture: actual player collision at clay/reed, exact legacy target preservation, physical worker arrival, hidden reed lifecycle/pause/reassignment, merged output, full player route traversal and native pickup; GL renders include frozen identical-frame worker front/back and player front/back probes.
- Keeper fixture: native E, directional layers, four-pixel hint gap, adjacent range, response order, text fit/viewport clamping, cancellation/reopen, native completed menu ownership and physical door contact. It extends native clean/build/production, expiry/renew, schema1–7 migration, schema8 rejection and city/home ownership tests. PNG byte hashes, imported alpha and every visible pixel match the canonical art. Godot's existing alpha-border import fills only invisible RGB; it is logged separately.
- Eight separate-process workshop save/Continue runs (pending/arrived in city/home, write/read): exit 0 with keeper-enabled native content and unchanged schema8 target. These do not use personal save slots.

Earlier runs exposed and corrected fixture node-name assumptions, an invalid capture during an intentionally detached-map probe, raw transparent-RGB comparisons, and a prompt type annotation. An intermediate asset copy also exposed duplicate UID/stale import paths; only those new identical copies were removed, canonical assets retained, and valid import/render runs repeated. Superseded failures remain in evidence, not counted as passing acceptance. The `.ps1` batch launcher was rejected by local execution policy; that launcher was not retried or used, and no policy setting changed. Godot was invoked directly for isolated tests.

## Review boundary

This checkpoint is compatible presentation/collision work on top of the unmerged prepaid integration, not proof that the entire branch is ready for main. Human visual/playthrough review is still required. Dry-shore metadata and future shoreline edits remain an explicit limitation; dynamic crowd avoidance and Android are untested. No game-wide production financing/balance claim is made from fixtures. The owner retains merge authority.
