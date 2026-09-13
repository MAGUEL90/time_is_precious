# Worker/worksite disk save MVP

Date: 2026-09-13
Branch: feature/process-workshop/clay-worksites
Status: PASSED — NEEDS HUMAN REVIEW

## Scope and authority

The Director accepted the proposed next MVP checkpoint: persist worker assignments, equipment, Hauler destination/target, storage contents and contribution XP across closing/reopening the current prototype. Persistence is a LEVEL 3 risk within this explicitly requested scope. Existing human scene/assets changes remain intact. No autoload, project setting, production scene, balance, or control-pack changes are planned.

Implement in the interactive `test_scene_hauler_delivery_setup.tscn`, with a scene-local save coordinator and versioned JSON snapshot. Include the clock, natural stock, ground output, player inventory and in-flight cargo as dependencies of item/XP conservation. Worker employment, dismissed workers, unique tool ownership and productive days must also survive restart. Only committed Daily assignments (Start Work) are persisted; uncommitted panel selections remain drafts. No offline production or automatic level increase.

## Schema/compatibility contract before implementation

- First schema version: 1; scenario: `clay_worksite_mvp`.
- Local prototype slot: `user://worksite_mvp/save_v1.json`. Isolated from production and existing regression fixtures.
- JSON contains explicit whitelisted scalar fields, IDs and vector coordinates. Never load resources, scripts, arbitrary file paths, Callables, or serialized objects from save data.
- Destinations use stable supplied IDs, resolved against the current scene registry. Runtime node references and callbacks are rebuilt locally.
- Validate the entire snapshot and cross-references before changing live state. Restore replaces, rather than appends, saved state. Do not replay production/delivery events while loading.
- Write a temporary file, verify it, retain the previous valid snapshot as backup, then replace the primary. Missing files start fresh. Corrupt, unsupported older/future versions and unresolved destinations must remain preserved and block automatic overwrite. There is no earlier disk schema to migrate.
- Autosave settled state and flush on normal close; abrupt editor/process termination can retain only the latest completed autosave. Do not save during an unfinished synchronous/manual work transaction.

## Acceptance / planned QA

Fresh process save then fresh process load; repeated load; exact tool/worker/XP/destination/target retention; partial gathering and outbound/returning cargo resume exactly once; target and next-day behavior; pickup/inventory conservation; fired workers stay fired; missing/corrupt/old/future saves; invalid IDs, duplicate ownership and missing destinations reject without partial writes; backup and interrupted replacement recovery; existing delivery/worker tests and main project parse/launch. Use isolated APPDATA/LOCALAPPDATA under TEMP for all QA.

Work split: Astra Medium owns implementation and verification. Luna XHigh is not delegated.

## Implementation and boundaries

- Added `worksite_save_state.gd` (explicit schema, validation and reconstruction) and `worksite_save_store.gd` (disk writes, backup, load and autosave).
- The existing delivery setup script enables persistence for interactive F6 use. Its `persistence_enabled` Inspector property can disable it for a clean temporary playtest. The existing `TIP_TEST_HAULER_TARGET=1` regression remains isolated and does not access this slot.
- Destination IDs `storage_a` / `storage_b` resolve to the current reusable StorageDestination nodes. There is one chosen destination per Hauler; no route editor or multi-stop route was added.
- Autosave checks every 0.5 seconds, including paused menus, writes only changed settled snapshots, and handles a normal window-close notification. Stops during an unfinished player-work transaction retain the last completed checkpoint. An abrupt editor stop/power loss may lose changes since the last successful autosave; no filesystem power-loss guarantee is claimed.
- Natural stock, ground piles, player inventory and cargo form one snapshot. Collecting pickup animations are omitted because the inventory has already received those items. Partial Laborer progress, daily minutes, route phase, rejected cargo and pending removal are retained.
- Employment records, dismissed-worker XP, unique tool ownership, contribution totals and productive days restore by replacement. Day lists are converted back from JSON numbers to integers. Gameplay award signals are not replayed. Existing world lighting is refreshed with clock signals suppressed, followed by the presentation time update.
- The schema is the first prototype disk format. Unsupported version 0 and future version 2 are explicitly rejected and preserved, not migrated or silently reset. Invalid IDs, storage registry/active destination position changes and duplicate equipment slots block load before mutation. Corrupt primary files remain intact even if a backup exists; after a human moves the corrupt primary aside, a valid `.bak` can restore automatically. A missing primary after an interrupted rotation recovers `.bak` (or a verified `.tmp` when no backup exists).
- A byte comparison detects an existing file changed since this session read it and stops overwrite. This is protection against already-observed external changes, not a multi-process locking protocol.
- No existing save was available to migrate from past sessions. First launch after this change begins with the scene's normal seed data. The scope is this worker/worksite prototype; full-game quests, workshops, player conditions/EXP, economy and offline simulation remain outside it.

## Verification results

- `WorksiteSaveTest write`: PASSED in a fresh headless process. Confirmed timer autosave while a menu pauses gameplay, 07:37 Day 1, seven partial Laborer minutes, an outbound load of three items, two simultaneous Hands/Tool allocations and a dismissed worker's retained XP.
- `WorksiteSaveTest read`: PASSED in a separate GL Compatibility process at 1200 x 675 / logical 400 x 225. Confirmed startup restore, two repeated restores, resumed outbound delivery/empty return, target exactly 20 accepted items, no duplicate XP or productive days, no resource loss, Daily quota resets and continued assignment on later days.
- Rejected delivery with pending removal and a loaded return leg restored, returned cargo once and released the worker. Partial player pickup restored the bag credit and the eight-item ground remainder without duplicating the collecting animation.
- Corrupt JSON, wrong root/header types, versions 0/2, missing worker/destination, invalid cargo, invalid job record and duplicate equipment-slot ownership all rejected without partial state changes or overwriting the original file. A missing registered scene destination also rejected. Backup recovery, subsequent writes, external-change preservation and normal-close notification flush passed.
- `HaulerDeliverySetupTest`, `WorkerControlTest`, `ClayWorksiteDailyTest`: PASSED. Main project headless launch exited 0.
- Captured and inspected `%TEMP%/worksite-save-restored-progress.png`: the restored Worker Progress panel shows Arad/Belum, three gathered items, zero delivered so far, Storage B and target 20. Its existing font sizing and close button remain intact; no scene layout edits were made.
- Existing certificate-store and ObjectDB / 15-resource shutdown diagnostics remain. Deliberately invalid save cases produce expected preservation warnings. No new blocking script errors remain in final runs.
- Initial development tests caught a wrong fixture storage API name, JSON number/string normalization, an Array/String comparison error and missing `cloudy` weather acceptance; corrected and rerun before the final passes.
- QA data lives only under `%TEMP%/tip-worker-save-qa/`; final restart pair uses its `final` directory. Logs: `%TEMP%/tip-worker-save-final-write.log` and `%TEMP%/tip-worker-save-final-read.log`.
- Existing-file incremental diff and whitespace check passed. Pre-edit copy: `%TEMP%/tip-worker-save-20260913-114156`. No human asset/scene layout changes were reverted. No commit, push or merge.

## Manual verification

1. Open `res://scenes/test_scenes/clay_worksite_test/test_scene_hauler_delivery_setup.tscn` and run with F6. Leave `Persistence Enabled` checked.
2. Select Worker, attach the Laborer and Hauler, choose Storage A or B and a target, then Next and Start Work. Start Work commits the assignment; Next alone remains a draft.
3. Close the panel. F advances to tomorrow at 06:45; F7 adds 30 minutes. Let the workers produce/deliver, optionally equip tools before their shift, and inspect Worker Progress or Worker Hub.
4. Wait at least one second after the change, stop the run and launch the same scene with F6. The assignment, tools, target, stocks, worker XP and in-flight cargo resume automatically. Closed-game time does not advance the world.

Save location: `user://worksite_mvp/save_v1.json`, with `.bak` beside it. Godot's Project > Open User Data Folder can locate it. For a fresh throwaway test, disable `Persistence Enabled`; the existing disk slot is left untouched.

File replacement API was checked against the official [Godot DirAccess documentation](https://docs.godotengine.org/en/stable/classes/class_diraccess.html#class-diraccess-method-rename-absolute). The prior snapshot is retained before primary replacement; no power-failure atomicity is inferred from that API.
