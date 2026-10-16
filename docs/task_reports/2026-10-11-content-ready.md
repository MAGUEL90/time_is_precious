# Content workflow readiness — 2026-10-11

Status: PASSED — NEEDS HUMAN REVIEW.
Branch: `fix/gameplay-hud/ui-consistency`, continued from clean `696da34`.
Risk: Level 2 limited startup/persistence integration, authorized by the user's
request to resolve the identified startup/load and debug-default obstacles before
content work. No balance, economy, story or checkpoint schema changes.

## Audit and scope

The previous UI cleanup left no player-facing Load entrypoint. F5 opened the city
directly. The authored map still forced the merchant to arrive on day zero in debug
builds. Explicit debug controls otherwise start at normal speed with player/worker
guards off; fixture money is restricted to tests. Keep the optional debug toolbox,
existing authored applicants/cart and approved raid balance. Do not reorganize
scene assets or alter content-placement authority.

## Implemented

- Added a themed 6/12px startup menu with Continue, New Game and Quit; no tooltips.
- Changed only `run/main_scene` in project settings. F5 opens this menu; F6 on the
  authored ContentScene still opens the city directly for content iteration.
- Startup holds simulation paused. Continue creates the real city, waits for its
  existing CitySave binding and calls the existing loader. Home checkpoints use
  the existing home/fade handoff. Input is blocked while restoration completes.
- Missing saves disable Continue. Invalid saves show feedback without mutating
  files or advancing gameplay, and allow retry or a confirmed fresh start.
- New Game confirms if the four known checkpoint files exist. It compares file
  hashes against the confirmation observation and archives them to a unique
  `user://city_save/archive/checkpoint-*/` directory. Existing files are moved,
  not deleted. Partial move failure attempts rollback without overwriting newly
  appeared files. A changed file requires a new user choice. No save is written
  merely for starting; sleep still creates the next checkpoint.
- CitySave receives a small observation-reset method so a new slot is read again
  before its first sleep write. Snapshot validation, application, schema and the
  normal disk replacement/recovery rules remain unchanged.
- Removed the map's debug-first-day merchant override. Its normal schedule now
  applies in editor runs too; the explicit Inspector override remains available.
- Updated the current save/startup sections of ROADMAP and ARCHITECTURE.

## Changed files

Created: `scenes/ui/start_menu/start_menu.gd`, `start_menu.tscn`,
`checkpoint_archive.gd`, their two script UID files;
`scenes/test_scenes/test_scene_start_menu.gd`, its UID and scene; this report.

Modified: `project.godot` (main scene only),
`scenes/content_scene/content_scene.tscn` (merchant override only),
`scenes/new_scenes/save_game/city_save_store.gd` (observation reset only),
`scenes/test_scenes/test_scene_traveling_merchant_access.gd` (now tests normal map
defaults), `ROADMAP.md`, `ARCHITECTURE.md`.

No deleted/renamed repository files. No addons, autoload registrations, display
settings, gameplay resources or unrelated authored map cells changed. The four
known editor metadata changes were backed up, checked and restored, retaining the
intended main-scene edit.

## Validation

Godot 4.5.2; Linux/Xorg native runs at 1200x675 with the unchanged 400x225 logical
viewport. Configured main-entry smoke test also passed headless. New startup tests
use isolated test slots/XDG storage, never the developer's gameplay checkpoint.

Nine main scenarios passed:
1. Empty-slot startup: paused menu, disabled Continue, new city, no forced merchant,
   normal player needs and no premature checkpoint write.
2. Invalid-slot startup: preserved bytes, friendly error, cancellation, rejection of
   files changed after confirmation, preserved primary/backup archives, subsequent
   fresh checkpoint save. Final archive/error rerun passed headless.
3. Continue a city checkpoint in a fresh process, preserving the full snapshot and
   original file bytes.
4. Continue a home/sleep checkpoint in a fresh process, preserving the full snapshot,
   saved location/time and original file bytes, without repeating sleep.
5. Existing City Sleep Save roundtrip (real bed, workers, cargo and return to city).
6. Traveling Merchant Access, now without a fixture override of map defaults.
7. Raid Playtest.
8. Inventory Modal Pause.
9. Main Map Hauler Start (actual applicants/hiring/jobs).

Separate City Save and City Sleep Save write-mode runs produced the known test
checkpoints. Initial Continue snapshot assertions compared JSON text and failed
because schema integers serialize as `2` before decoding and `2.0` afterward.
Inspection found identical data. Assertions now compare recursive values, with
only the existing one-ULP float allowance; encoded integer counts and RNG strings
remain exact. Both corrected native Continue runs passed.

Screenshots inspected: initial menu, missing/valid slot, invalid-save feedback,
New Game confirmation, continued city and continued home. Evidence:
`/workspace/scratch/content-ready/` (logs and `captures/`). Expected warnings:
dummy-display VSync and deliberate corrupt/external-change rejection in negative
tests. No final script errors. `git diff --check` passed.

Windows and Android are unverified. This prepares content editing; it does not
claim release readiness or completion of the game's authored content. There is
still one active checkpoint slot; old New Game archives are file backups, not a
new multi-slot selection UI. Human visual/gameplay acceptance remains pending.
