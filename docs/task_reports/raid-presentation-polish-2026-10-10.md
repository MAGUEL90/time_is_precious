# Raid presentation polish — 2026-10-10

Status: PASSED — NEEDS HUMAN REVIEW
Branch: feature/time-world/raid-mvp
Baseline: 84a67b8
Starting working tree: clean; remote matches baseline
Risk: LEVEL 2 limited presentation integration

## Scope and authorization

The Director requested an English opening greeting for Iddin-Sin, removal of the world name caption, wall/watchtower icon progress bars in City Management and the world, removal of routine City Management feedback (attack warnings only), and a gentle in/out heartbeat on the red emergency notification. The dialogue edit is explicitly authorized. Balance, schedules, resource costs, city progression, project settings, addons, autoloads and unrelated gameplay remain outside scope.

Acceptance: native greeting advances to the existing quote/choices; work indicators match actual work progress, retain wall HP separately and disappear at completion; the world indicator follows the relevant structure; warnings display only during attack/looting; detected/active threat pulses without resetting on refresh and returns to normal when over; keyboard and Inspect/report flows remain intact.

## Validation plan

Parse/import, existing UI and native main-map expedition/dialogue/playtest regressions, visual capture at the project's 400x225 logical / 1200x675 development resolution, and targeted paused/recovery/map-exit presentation checks. Verify actual current city menu names from source. Root owns final diff review; narrow greeting/test adaptation delegated to the project-prescribed Luna XHigh helper.

## Implementation and menu audit

- The native English opener advances into the existing cost quote and choices. Warning and attack openers retain their urgency and the work page still revalidates raid state. Only the world Caption is hidden; Iddin-Sin's dialogue identity and blank portrait remain.
- A shared `DefenseWorkProgress` control reuses the existing empty/filled progress-bar textures, with small wall/tower silhouettes. City Management shows construction separately from wall HP and marks interrupted work as paused. The world indicator uses the relevant construction location, switches to HP during a raid, and disappears on completion. Build, repair, upgrade and watchtower read the same work ledger.
- City Management's routine phase sentences are hidden. `Wall under attack` appears only in attacking phase; looting shows `City Storage under attack`. Travel ETA and reports remain in their existing UI.
- The emergency ! button uses a gentle sine pulse (scale 1.00–1.08, opacity 0.78–1.00 over 1.8 seconds). Warning/attacking/looting drive it; refreshes do not restart it, pause freezes it, recovery/map exit resets it. The existing screen-edge effect is unchanged.
- The actual primary city panels are **City Supply** (City Storage access plus food/clothing supply summaries) and **City Management**. There is no standalone scene/menu titled City Needs. Inspect and Last Raid are subordinate views; worker/workshop UIs are separate.
- `Next party` remains a Debug-only threat-stage selector for the next departure. Its existing mechanics are unchanged.

## Validation

Godot 4.5.2 editor import/parse passed. Four focused scenes passed: `RaidUITest`, `RaidExpeditionTest`, `RaidPlaytestTest` and the graphical `DefenseDialogueTest`. Coverage includes both work icon types and progress parity, separate HP, paused work, completion visibility, attack-only feedback, pulse round trip/refresh/pause/recovery, native greeting/quotes/options, warning urgency, map reload and Inspect navigation. The native scene captured the actual greeting, city/world wall construction, city/world watchtower construction, and notification pulse.

The only graphical warning was unsupported VSync in the virtual display driver. No script errors were observed. Editor-generated changes to project settings and three addon imports were inspected and restored. Diff review found no balance, cost, schedule, raid composition, storage or progression changes. Windows/Godot 4.5.1 and Android were not run; human playtest and merge remain with the Director.

## Files

Created: `scenes/raid/defense_work_progress.gd`, `.gd.uid`, `.tscn`, and this report.

Modified: `dialogue/game_dialogue_conversations/wall_caretaker.dialogue` (explicitly authorized), `scenes/raid/wall_management_spot.tscn`, `raid_bootstrap.gd`, `raid_ui.gd`, `wall_world_indicator.gd/.tscn`; the four related test scripts `test_scene_raid_ui`, `test_scene_raid_expedition`, `test_scene_raid_playtest`, `test_scene_defense_dialogue`; `ROADMAP.md` and `ARCHITECTURE.md`.

No files deleted or renamed. No settings, addons or dependencies changed.
