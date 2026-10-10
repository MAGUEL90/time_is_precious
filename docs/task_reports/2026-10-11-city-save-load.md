# City Hub spacing and manual city checkpoint

Branch: `feature/time-world/city-save-load`.
Baseline: `fb7c2283e01eab097b294dca265284811297484e` (city progression).
Starting working tree: clean. Risk: **LEVEL 3 — SYSTEM CHANGE**, authorized by
“oke bisa kita kerjakan save/load”; limited to the existing main-city loop.
Status: **PASSED — NEEDS HUMAN REVIEW**. Human merge decision: pending.
Agent: Codex (root integration and final review; delegated narrow helpers/tests/UI).

The requested checkpoint covers the current main city, not the isolated Clay F6
save fixture. A new version-1 JSON slot lives at
`user://city_save/checkpoint_v1.json`; the existing worksite slot remains separate.
Save and Load are explicit City Hub actions. There is no offline production and
no automatic load or overwrite on launch. Load restores the checkpoint's clock.

## Ownership and compatibility plan

`CitySave` is a child of the existing `WorkStateRuntime` host, bound by the main
map's RaidBootstrap. No new autoload or project settings are required. Explicit
field lists cover city progression and settlement cursors, raid party/timing/
construction/loot, player condition/position/inventory, residents/workers/needs,
City Storage including equipment and portions, immigration, merchant visits,
workshop construction, production orders/processes/output ownership and fees,
and main-map worksite stocks, ground output, jobs and hauling cargo. Dropped
player inventory items retain their quantity and map position.

The schema uses a bounded JSON value codec with explicit Resource factories.
No save-controlled script or resource path is loaded. Full decoding, type checks,
reference checks and version checks finish before any live owner is changed.
Owner state is applied synchronously, callbacks/storage references are rebuilt
from the authored map, then presentation refreshes without emitting elapsed days
or minutes. Saving/loading during transient transactions, gathering, manual
clearing, sleeping or scene transitions is refused. Active wall jobs and raids
are stable checkpoint states and remain supported.

A prior valid slot is retained as `.bak`. Staging is validated before replacement.
Corrupt or unsupported primary files remain untouched and block replacement.
Recovery uses a valid staged/backup file only if the primary is absent. Observed
external file changes block writes until a new explicit Load. Unsupported future
versions require a deliberate migration rather than silently defaulting fields.

## UI and changed files

City Hub retains its 300 x 196 logical-pixel frame on both tabs. Section gaps
separate the title, tabs and city progress; supply rows have more spacing, and
the progress bar stays vertically centered. The shared footer anchors the manual
Save/Load controls and compact result status without moving between tabs.

Modified: `scenes/raid/raid_ui.gd`, `scenes/raid/raid_bootstrap.gd`,
`ARCHITECTURE.md`, `ROADMAP.md`.
Created: the five `scenes/new_scenes/save_game/city_save_*.gd` helpers and UIDs;
the `test_scene_city_save`, `test_scene_city_save_file`,
`test_scene_city_save_values`, and `test_scene_city_save_economy` scripts,
scenes and UIDs; this report. No files deleted or renamed.

## Verification

Godot 4.5.2, Linux, GL Compatibility, 400 x 225 logical viewport / 1200 x 675
native window. Final editor import/parse exited successfully without script errors.

- Disk-boundary fixture passed: missing/corrupt/unsupported files, staging and
  backup recovery, prior-primary retention, external-change rejection, file-size
  and nonfinite/depth guards.
- Value-codec fixture passed: explicit citizen/worker/order/station/batch factories,
  nested collections, exact int64/RNG values and rejection of malformed or
  incomplete fields and unapproved types.
- Main-city checkpoint fixture passed: repeated Save/Load, later-day checkpoint,
  paid active wall construction, player inventory/dropped items, city progress,
  active raid and looting continuation. Invalid loads left live owners unchanged;
  corrupt saves stayed intact; Load did not repeat breach penalties or loot.
- Fresh-process write then read passed at day 7: all captured owners and RNG
  state matched the file after closing/restarting Godot.
- Economy fixture passed using real gameplay APIs: hired citizens and needs,
  clothing allocations, allocated tools, resource-site workers, outbound cargo,
  delivery to City Storage, ground yield, active drying process, completed
  output/fee ownership, and NPC workshop work orders. Restored jobs completed
  once, without duplicating stock or fees. Float comparisons allow 1e-10 absolute
  JSON roundoff; counts, IDs, arrays and 64-bit RNG values remain exact.
- Native checkpoint and City Hub layout fixtures passed. Both tabs retain the
  same frame; Save/Load/Last raid/Close stay within the margin, including the
  dense construction-plus-attack layout. Screenshots were visually reviewed.
- Focused regressions passed: city progression, raid recovery, raid looting and
  raider composition.
- Final diff review excludes editor-generated `project.godot` and three Dialogue
  Manager SVG import changes; these were backed up, then restored with explicit
  user permission. No addon, autoload, project setting, input action, balance or
  existing legacy save-schema changes remain.

The existing godot-mcp runtime bridge printed a localhost port 9877 listener
error in this environment; test scenes still completed and passed. Native Linux
also reports unavailable driver VSync. Neither is a new save/load script error.

## Playtest and limits

Open the main city, press **C**, then **Save** in City Hub. Change stock, let work
or a raid advance, and press **Load**: the stored world and clock return together.
To test restart persistence, Save, close/reopen the game, then C > Load.

This is one explicit main-city checkpoint, not autosave or offline simulation.
Home/nightmare/scene transitions and transient transactions must finish before
saving/loading. Title-menu Continue, multiple slots, saves in other maps and
migration from future schema versions remain outside this task. A corrupt
primary deliberately stays untouched rather than silently selecting an older
backup. Power-loss durability beyond verified staging/rename recovery was not
physically fault-injected. Windows and Android execution were not tested here;
the user's Windows playtest remains the next acceptance check.
