# Fixed workshop plot and initial construction MVP

Date: 2026-09-26
Branch: feature/process-workshop/main-map-access
Baseline: 94bf6a9. The initial access preview was already uncommitted when the construction follow-up began; its work was preserved and revised.
Risk: LEVEL 2 - bounded map, worker, inventory and clock integration. The Game Director approved worker-built construction, three days for one worker, team-dependent duration, and delegated material selection.
Status: PASSED - NEEDS HUMAN REVIEW. Construction mechanics validated; normal-game material acquisition remains incomplete.

## Final behavior

- A native hammer icon replaces the plot's E glyph. E opens requirements directly; no intermediate hammer panel.
- Recipe: 6 Wood Logs, 12 Clay Lumps, 8 Reed Bundles (existing icons; total weight 50).
- Select idle eligible workers; duration is ceil(4320 / selected worker count) game minutes: one 3 days, two 1.5 days, three 1 day.
- Build takes materials from personal Inventory once and reserves the selected team. Missing inputs, duplicate IDs, busy/unavailable workers and repeated start requests are rejected.
- Team and recipe are fixed for this build. Closing the panel does not cancel construction. World time advances it while the player is elsewhere.
- Completion releases builders and instances the existing WorkShop scene. Its established storage, production and facility menus remain responsible for production.
- No construction fee, new role restriction, skill multiplier, relocation, rotation, cancellation/refund UI or disk persistence is added.

## Implementation boundaries

The authored plot is at world (0, 40), local (-256, -168) under ContentScene/YSortWorld. Move WorkshopPlot in the editor to choose the final location. Footprint, Sprite2D and interaction shape remain editable. Existing table art is a placeholder; no former-workshop story is canonized.

`scenes/workshop_plot/workshop_construction_state.gd` lives as MainWorkshopConstruction beneath the existing WorkStateRuntime. It owns the single MVP construction state, material transaction, team reservations and absolute world-clock deadline. The plot owns proximity/modal lifetime and completed scene presentation. No new autoload or project setting is introduced. WorkerData/WorkerDatabase APIs are reused. Linked citizens transition HIRED -> ASSIGNED -> HIRED; already-assigned citizens are excluded.

The construction state survives map removal/reload in the same running game. Initial construction has no item output or escrow, so it does not misuse a production WorkOrder. WorkManager and ProcessManager remain unchanged. Ordinary production after construction still has the prototype's existing shared workshop-storage behavior.

## Validation

Godot 4.5.1 validation of this follow-up:

- WorkshopConstructionTest PASS: no/duplicate/missing/busy/travelling/already-assigned workers, missing materials, exact material deductions, reentrant/repeated starts, partial-consumption rollback with preserved external inventory changes, 1/2/3-worker deadlines, worker dismissal/job exclusion, citizen assignment/release, deadline boundaries and repeated/backwards timestamps. Actual map removal/recreation retains construction; completion opens the existing workshop.
- WorkshopConstructionUITest PASS at 1200x675 / logical 400x225: real E input, select three worker checkboxes, enabled Build, start/resume, progress panel, world-time completion and existing workshop menu. Ready/progress/completed screenshots inspected in the session visualization directory (`construction-ready.png`, `construction-progress.png`, `construction-built.png`).
- WorkshopPlotAccessTest PASS after construction integration: proximity/hammer prompt, direct requirements, modal guards, open/close/reopen, out-of-range/plot-removal cleanup, unchanged stock when inspecting.
- Latest WorkshopPlotAccessTest PASS: hammer overlays a native 16x16 panel; the debug supply button supplies missing recipe inputs while the requirements panel is open, rejects insufficient capacity without partial supply, and repeated presses do not stack materials. Rendered prompt and supplied requirements screenshots inspected.
- ContentWorksitesIntegrationTest and WorkshopUIRegressionTest PASS after integration.
- Normal graphical main launch and dedicated F6 construction playtest launch exited 0 without script errors.
- Headless editor parse/import exited 0; existing editor MCP port was busy, without parse errors. Final runtime tests had no script errors.
- First construction-test run exposed untyped arrays in the fixture despite its PASS text. Typed-array fixes and completed-section guards were added; the final rerun completed cleanly. That first run is not counted as passing.
- Diff reviewed; `git diff --check` passed. No existing authored transforms/tile data, autoload registrations, addons or project settings changed.

Existing shutdown diagnostics (ObjectDB instances/resources still in use) remain outside this task. Unsandboxed Godot execution is used after a native crash in the sandbox. No complete production loop, disk save/load, or human playtest is claimed.

## Human playtest

For accelerated-time debugging, the main-map and home Player instances now enable the existing `debug_disable_player_needs` Inspector flag. It keeps Focus full and Hunger/Fatigue at minimum, bypassing condition-driven collapse. Disable that flag on both instances to return to normal condition testing. WorkshopPlotAccessTest passes with the authored main-map flag and verifies a critical condition is restored on a time tick without collapse.

Open `scenes/test_scenes/workshop_construction_playtest.tscn` in Godot and press F6. This scene supplies test Inventory materials and three hired builders. The player starts at the plot and player needs are disabled only in this fixture. Press E at the hammer, select one to three TEST builders, then Build. Close any panel and press F8 to advance 12 game hours; two presses finish a three-worker build, six finish a one-worker build. E then opens the existing Workshop menu. The underlying world clock is used, so city daily evaluation still runs. Restart F6 for a fresh fixture. No save slot is read or written.

On the main map in an editor/debug build, approach the empty workshop plot open its requirements panel with E, and click **Debug: supply**. This explicitly tops up missing inputs for one recipe (6 Wood Logs, 12 Clay Lumps, 8 Reed Bundles), preserves existing inventory, and checks capacity before supplying anything. There is no automatic material seed on the main map, and the button is hidden in release builds. No F9 binding is used.

## Remaining playable-start gaps

- Normal main-map acquisition of Wood Logs and Reed Bundles is not implemented by this change; the supply button is an explicit debug convenience only.
- First-worker onboarding and initial hires still need normal-flow validation; existing prototype/legacy workers are supported.
- Construction worker travel/animation, final building art, story and final map placement remain follow-ups.
- The parked mudbrick checkpoint remains untouched; this does not finish ROADMAP Priority 1.
