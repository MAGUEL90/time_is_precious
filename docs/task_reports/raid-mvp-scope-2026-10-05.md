# Raid branch — wall and manual combat playtest

Status: PASSED — NEEDS HUMAN REVIEW (build and manual raid checkpoint; random-raid balance remains pending).
Date: 2026-10-05
Branch: feature/time-world/raid-mvp
Baseline: 83a67f3efb7bb734e4d5efd201ad02600e89369d (merchant MVP merge, PR #110)
Starting working tree: first checkpoint began clean except the scope document; the second checkpoint preserves and extends its uncommitted changes.
Risk: LEVEL 3 for the scoped runtime/storage integration. Director-owned balance is not enabled implicitly.

## Latest Director direction

The wall starts destroyed. The first playtest is building it: an instant, free Build button creates a level 1 wall with 50 HP. Durability is represented by HP for this checkpoint. Wall upgrades, weaponry and watchtowers follow later. The previously proposed 100 HP profile was superseded and was not enabled.

The eventual raid lasts at most 60 real gameplay seconds, with a hit every five seconds. Raider strength minus wall Defend gives nonnegative wall damage. At zero HP the raiders enter; a result panel reports stock losses, destruction, satisfaction loss and fleeing residents. No soldiers exist yet.

## Playtest instructions

1. Run the normal project and enter the city map, or F6 `scenes/content_scene/content_scene.tscn`.
2. In the lower-right wall panel, choose **Details**.
3. The wall starts ruined at level 0. Choose **Build wall (free)**.
4. Confirm level 1 and **50 / 50 HP**, with a filled durability bar. No time or Inventory materials are consumed.
5. Close/reopen the panel and enter/leave home: the same wall state remains, with no repeat-build action.

Construction has panel presentation only in this checkpoint. There is no new wall sprite, collision perimeter, construction animation, upgrade, weapon slot or paid repair economy.

## Continuing the playtest: manual raids

After building the wall, open **Debug** (button or backtick). The first row below
time controls now offers:

- **Raid light**: fixed debug damage of 3 HP per hit. From full 50 HP it survives
  twelve five-second hits and ends at 14 HP after 60 real gameplay seconds.
- **Raid heavy**: fixed debug damage of 5 HP per hit. From full HP it breaches on
  the tenth hit, at 50 seconds. An already-damaged wall can breach sooner.
- **Reset wall HP**: explicit debug restoration of a damaged standing wall, for
  repeating tests. It does not change level, report, next schedule or balance.
  A breached wall uses the existing **Rebuild wall (free)** action instead.

Controls require an already-built wall, active gameplay and no ongoing attack.
They never seed stock or citizens. Opening Debug does nothing to the raid state.
The debug panel and old report close when a test starts, exposing the live HP bar.
The result opens automatically once at the end. An active raid continues across
home/map changes, and world-time acceleration does not accelerate its real-time
hit counter. Pause and scene transitions suspend the counter.

A separate free-repair API/button has fixture coverage but its production setting
remains disabled pending the Director's balance choice. Nonzero theft, satisfaction
and departure parameters also remain disabled in the main profile. The dormant
population effects now go through CitizenManager and remove matching visible actors;
reports in the main build-only profile correctly show zero such losses.

## Runtime and UI

`RaidBootstrap` on the city map creates a single `CityRaid` ledger under existing `WorkStateRuntime`, plus one persistent `RaidUI`. It follows the merchant's session ownership pattern and requires no new autoload. The production `wall_playtest.tres` explicitly permits free construction and leaves random raids disabled. The template resource is loaded after script initialization and deep-duplicated for runtime use. A regression exposed incomplete exported values on a compile-time preloaded template; runtime loading fixed this, and both the profile-value assertions and actual map Build test pass.

The small HUD shows castle/wall HP and level. Details stay compact before any raid report; reports expand to a scrollable panel. The UI subscribes once, formats copies, opens each new report once and never reapplies losses. It does not pause or unpause other systems. Escape is handled only when otherwise unhandled and details are open.

Wall state lasts for this running session. Closing the game resets it. No existing disk-save schema was changed; persistence across restarts is not claimed.

## Raid foundation — test fixtures only

The reusable state and report presentation are available through explicit debug tests and deterministic fixtures. They are not an enabled random-raid balance profile:

- Building the initial wall starts a configurable grace period when raids are enabled.
- A bounded random interval selects the next attack. Warning text does not reveal its exact date.
- Repeated/rewound clock updates cannot reroll or duplicate an attack. A jump over a warning grants the configured preparation lead rather than replaying missed raids.
- Clock progress schedules the event; attack strength is rolled once per raid, and elapsed real gameplay time produces individual hits. Pausing gameplay or a scene transition stops the attack timer. The last hit at 60 seconds resolves before the survival result.
- Surviving damage remains. Reopening panels or calling Build again cannot heal a damaged standing wall.
- Breach effects resolve once, then the next recovery interval starts. Report dictionaries are deep copies.
- `CityToolStorage.take_raid_loot` subtracts actual counted stacks with a total whole-item capacity and a configurable reserve per stack. Sorted item IDs make the first foundation deterministic. Equipment, opened food portions, personal Inventory and unrelated workshop storage are not taken.
- Test breach satisfaction loss applies to actual resident data, retains the existing 0.01 floor, and reports the actual average loss in percentage points. Fixture departures exclude workers and retain at least one resident.
- Destruction currently counts the castle wall only. There is no general building damage/destruction system. A preexisting ruin is not counted as newly destroyed twice.

Before enabling raids on the main map, the Director still needs to set Defend, attack strength, schedule, theft limits, satisfaction/departure rules and recovery/repair costs. Worker departure and destruction of other buildings require their own integration; the dormant foundation does not claim those systems are complete.

## Changed files

- New `scenes/raid/`: config script, build-only profile, state ledger, map bootstrap and UI scene/script (with script UID sidecars).
- `scenes/content_scene/content_scene.tscn`: one bootstrap script resource/node.
- `scenes/storage_destination/city_tool_storage.gd`: guarded bounded-loot API; inactive in the build-only profile.
- `scenes/debug/time_debug_overlay.gd`: explicit manual raid/reset controls.
- `scripts/autoload/citizen_manager/citizen_manager.gd`: guarded nonworker departure and signal.
- `scenes/citizen_actor/citizen_actor.gd`: remove the actor matching a departed resident.
- New test scenes/scripts: `test_scene_wall_build`, `test_scene_raid`, `test_scene_raid_ui`, `test_scene_raid_playtest`, `test_scene_raid_recovery`.
- `scenes/test_scenes/content_depth_time_debug_test.gd`: isolate multi-day construction/depth verification from player needs; gameplay needs are unchanged.
- `ROADMAP.md`, `ARCHITECTURE.md`, and this report: checkpoint status and ownership boundaries.

No assets deleted/renamed; no control-pack, project-setting, plugin, autoload-definition or save-format changes. Godot editor side effects on project settings and three addon import metadata files were reverted after inspection.

## Validation

Engine: existing Godot 4.5.2, GL Compatibility. No engine/dependency installation.

- Project editor import/parse and normal startup smoke: passed, no script/parse errors.
- WallBuildTest: actual map UI build, HP/level, no resource/time charge, repeated use, menu pause ownership and home/map continuity.
- RaidRegressionTest: synthetic schedule, hit timing, blocked/weak/breaching attacks, bounded stock conservation, satisfaction/flight, immutable reports and repeated resolution guards.
- RaidUITest: HP/timer, auto-open once, rebind/unbind, accurate report units, no data mutation, viewport bounds and long report scrolling.
- RaidPlaytestTest: actual Debug buttons, real five-second processing/pause, HP/results, active home/map continuation, rebuild, and Debug reset without enabling gameplay repair.
- RaidRecoveryRegressionTest: repair guards, fixed strength per raid, recovery without rerolls, last unemployed resident protection, worker exclusion and actor departure signal.
- Existing CityFoodStockTest and CityClothingNeedsTest passed at the first checkpoint; PopulationEmploymentIntegrationTest, MerchantMainMapLoopTest and DebugProductionFlowTest passed at the second checkpoint.
- ContentDepthTimeDebugTest initially failed both on this branch and a separate checkout of baseline 83a67f3: multi-day advancement triggered player collapse and prevented construction completion. Its isolated fixture now disables player needs/fatigue; all original assertions remain. The corrected baseline and final branch graphical runs passed.
- Graphical wall and report tests run at a 1200×675 desktop window with the project's 400×225 logical viewport. Captures inspected under `/workspace/scratch/raid-captures/`.
- `git diff --check` and changed-file review: passed; only the listed scope remains changed.

The virtual graphics driver cannot enable V-Sync; graphical validation used software rendering and Dummy audio. The initial capture attempt also reported no ALSA device; subsequent captures explicitly used Dummy audio. These are environment limitations, not gameplay failures. Android, restart persistence and live raid balancing are untested.

Human playtest and merge remain pending. No commit, push or merge performed.

### 2026-10-08 — attack screen warning
- Requested presentation change: a soft red pulse around the screen edges while the castle is under attack.
- RaidUI owns the mouse-transparent overlay, behind its controls. It follows the attacking phase, stops on resolution/unbind, and freezes animation with the existing raid pause/transition gates.
- No gameplay balance or project settings changed.
- Godot 4.5.2 RaidUITest passed headless and with GL Compatibility at 1200x675; captures inspected for the active red edges and clean post-raid report. Virtual-display VSync warning only.

### 2026-10-08 — softer warning pulse
- User feedback: reduce distracting pulse intensity. Peak edge opacity reduced from 55% to 22%, with a narrower opacity swing and a slower 3-second cycle (previously 1.6 seconds).
- RaidUITest passed headless on Godot 4.5.2; diff check passed. The revised subjective intensity awaits local playtest.
- Wall interaction versus City Layout remains a design discussion; construction flow is unchanged.

### 2026-10-08 — wall painting setup
- Imported the user's asset commit 141d32e by fast-forward.
- Added empty ContentScene/YSortWorld/WallStone TileMapLayer and a separate wall_stone_tile_set.tres, with both 112x48 textures sliced into occupied 16x16 atlas cells.
- Nearest filtering and existing world Y sorting retained. Layout is left for the user to paint; collision, terrain autotiling and raid-driven visual changes are not configured.
- Godot 4.5.2 editor import and main-map headless launch completed without script/resource errors. No project settings or addon changes retained.

### 2026-10-08 — ruined wall layout
- Fast-forwarded the user's plot design (87924f0), preserving the ground layout and other scene edits.
- Painted 67 cells on YSortWorld/WallStone using only atlas source 0 (wall_stone_0). The perimeter follows the outer edge of the northern city plot, with a three-tile southern entrance.
- Wall artwork remains a static editor layout; construction/upgrade visual swapping and collision are not part of this pass.
- Loaded/rendered the actual main scene in Godot 4.5.2 GL Compatibility and inspected a 1200x900 overview screenshot with HUD hidden and temporary overview camera. Capture-only camera/window changes were outside the repository.

### 2026-10-08 — build from a physical wall spot
- User requested wall improvement through a nearby spot or NPC instead of the HUD Details panel. Implemented a labeled Wall Management sign by the south wall using the existing nearest-interactable E routing; NPC art/dialogue remains a later extension.
- Details and automatic raid reports are now read-only. The management view exposes the existing free instant build/rebuild only while the player has live physical access. Leaving range, changing maps, pausing or losing player availability revokes access; closing the panel never changes pause/movement ownership.
- Authored wall cells now display source 0 when ruined and source 1 when HP is positive. Build/rebuild/breach and map reentry preserve the user's exact tile positions and atlas coordinates.
- No new balance, repair approval, NPC behavior, collision or save schema. Scope remains the authorized raid UI/main-map integration with a narrow Player input route.
- Godot 4.5.2 editor import and RaidUITest passed. GL Compatibility preview at 1200x675 verified the E prompt, management panel, successful 50 HP build and intact-wall artwork. Screenshots: /workspace/scratch/wall-management-spot.png, wall-management-menu.png, wall-management-built.png. Virtual-display VSync warning only.
- WallBuildTest and RaidPlaytestTest passed: real Player E routing, read-only Details, immediate stale click after teleport, management closure on exit/map free, free build invariants, repair fixture, breach/rebuild and atlas/layout continuity. Final diff check passed.

### 2026-10-08 — caretaker dialogue replaces the board
- Director requested an NPC and repair dialogue instead of the wall board. Replaced the board art/caption with Mandor Tembok using the existing worker character assets; retained the node path and nearest-E routing.
- Native Dialogue Manager conversation offers "Perbaiki tembok (gratis)" when the wall needs work, or "Nanti saja". The selected work directly builds/rebuilds a ruined wall or repairs a standing damaged wall after dialogue ends; no management panel is opened. Full HP and active raids explain why work is unavailable.
- Retains free instant construction at level 1 / 50 HP and enables the existing free instant repair option for this requested repair playtest. No new costs, progression or random-raid balance.
- The NPC holds only a wall_npc movement lock and never pauses the world clock. Physical access and authoritative wall state are rechecked at commit; cancel, leaving range, pause, collapse and map exit discard work and release the NPC lock.
- Godot 4.5.2 dialogue import and RaidUITest passed. Native dialogue response tested in GL Compatibility at 1200x675: work completes at 50 HP and movement resumes. Dialogue/response screenshots inspected; portrait uses the same character appearance. Virtual-display VSync warning only.
- WallBuildTest and RaidPlaytestTest passed on Godot 4.5.2: native response selection, decline, stale/out-of-range action rejection, movement/time cleanup, full-HP/active-raid/repair-disabled gating, repair and rebuild, and visual state across map changes. Helper initially used 4.6.3; root reran both with the required 4.5.2 binary. Diff check clean.
