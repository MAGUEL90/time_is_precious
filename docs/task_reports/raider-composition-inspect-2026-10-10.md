# Raider composition and Inspect cards — 2026-10-10

Status: PASSED — NEEDS HUMAN REVIEW
Branch: feature/time-world/raid-mvp
Baseline: 6671af6
Starting working tree: clean
Risk: LEVEL 3 scoped raid/state/UI integration; the Director explicitly approved the new composition balance below.

## Scope and approval

The Director requested counted Light/Normal/Heavy parties, small initial raids with rare Heavy members, more numerous/varied parties at later city progress, and a separate Inspect panel with one icon card and quantity per type. Icon assets are not yet supplied, so local replaceable pixel placeholders are used. Effect/status mechanics remain future work.

Approved playtest values:

| Type | Strength per member | Travel days |
| --- | ---: | ---: |
| Light | 1 | 2 |
| Normal | 2 | 3 |
| Heavy | 4 | 4 |

| Stage | Members | Total strength | Chance of at least one Heavy | Maximum Heavy |
| --- | --- | --- | --- | --- |
| Early | 3–5 | 5–7 | 10% | 1 |
| Developing | 4–7 | 8–11 | 25% | 2 |
| Advanced | 6–10 | 12–16 | 45% | 3 |

City progression is not implemented. The Director approved keeping normal gameplay at Early, with Developing/Advanced selectable through Debug until a future city progression owner supplies the stage. No wall upgrade or passage of days automatically increases it.

## Implementation contract

- Generate composition at departure, after recovery if applicable. Snapshot the quantities, per-member stats, total strength and slowest-member travel duration. Opening Inspect, repairing/upgrading the wall, map reload and stage selection cannot reroll a travelling party.
- A separate Heavy-presence roll chooses the Heavy/no-Heavy pool; all combinations in each pool satisfy the count, strength and Heavy bounds. Choose a valid combination from that pool. Infeasible or malformed profiles fail validation.
- Total hit strength is the sum of quantity times each member's strength. Wall Defend is deducted once per five-second group hit; combat still lasts at most 60 active seconds. Existing looting capacity/rate, satisfaction loss and recovery duration are unchanged.
- Detection remains one day ahead, or two with the completed watchtower. Inspect returns no composition without that tower and a detected/active party. UI is read-only and uses a copy of the same party that attacks.
- The new panel renders only present types, with a replaceable icon and x quantity. It closes/clears stale data on losing access, changing party, changing map or ending the raid. Font sizes remain 6/12 in the existing logical viewport.
- Existing normal-party resources remain available to isolated regression fixtures. No project settings, plugins, autoloads, new save format or city progression changes are included.

## Verification

Godot 4.5.2 editor import/parse and ten applicable regression scenes passed:

- `test_scene_raid_composition`: 7,500 seeded parties across three stages; count/strength/Heavy limits and frequency; derived attack and slowest-member travel; deterministic snapshot; invalid profile rejection; hidden intelligence; immutable Inspect copies; five-second damage; next-party selection; cooldown, time skips and clock rewind.
- `test_scene_raid_expedition`: actual main-map construction, repair, journey/warning/arrival, Debug dispatch, storage conservation and effective combat speed.
- `test_scene_defense_improvements`: retained level/tower, upgrade/refund, watchtower gating and legacy profile compatibility.
- `test_scene_raid_ui`: card quantities, unknown composition, Back/Escape/C, stable card refresh, party-ID replacement, access revocation, combat/looting phase, notifications and stale-data clearing on map/rebind/end.
- `test_scene_defense_dialogue`: native Iddin-Sin upgrade/tower dialogue; real Debug stage cycling before/after departure; unchanged party after main-map reload; real Inspect cards match the departing party.
- Existing `test_scene_raid_playtest`, `test_scene_wall_work`, `test_scene_raid`, `test_scene_raid_recovery`, and `test_scene_raid_looting`: all passed.

Root visually reviewed `/workspace/scratch/raider-inspect-live.png`, captured from the real map using a seeded valid Early draw containing Light, Normal and Heavy. All three cards fit the panel and display their real counts. No actual raider icon textures are installed yet; the displayed icons are replaceable placeholders.

There were no new script errors. The graphical run emitted only the virtual display driver's unsupported VSync warning. Editor import-generated changes to `project.godot` and three addon `.import` files were inspected and restored; none are part of this change. `git diff --check` passed. No protected files, autoloads, plugins or settings were changed.

## Changed files

- `scenes/raid/raid_unit_config.gd` and `raid_composition_stage.gd`, with `.gd.uid` files: new per-member and stage resources.
- `scenes/raid/light_raider.tres`, `normal_raider.tres`, `heavy_raider.tres`, `raid_stage_early.tres`, `raid_stage_developing.tres`, `raid_stage_advanced.tres`, `mixed_raider_party.tres`: approved data.
- `scenes/raid/raid_party_config.gd`, `raid_config.gd`, `raid_state.gd`, `wall_playtest.tres`: validation, generation, frozen party scheduling and combat integration.
- `scenes/debug/time_debug_overlay.gd`: next-party stage selector and departure countdown.
- `scenes/raid/raider_inspection_panel.gd/.tscn`, `raider_type_icon.gd`, their `.gd.uid` files and `raid_ui.gd/.tscn`: card panel, replaceable icons and navigation/cleanup.
- `scenes/test_scenes/test_scene_raid_composition.gd/.tscn/.gd.uid`: new composition regression.
- `scenes/test_scenes/test_scene_raid_expedition.gd`, `test_scene_defense_improvements.gd`, `test_scene_defense_dialogue.gd`, `test_scene_raid_ui.gd`: updated integration coverage.
- `ROADMAP.md`, `ARCHITECTURE.md`, this report: current behavior, boundaries and validation.

No deleted or renamed files.

## Remaining limits / playtest

Open City Management with C, then Inspect once a completed watchtower detects a party. Debug's **Next party** selector changes only a future departure; an existing expedition keeps its counts, strength and arrival time. Gameplay starts at Early on a fresh session. City progression, additional statuses/effects, unit casualties and real icon art remain future work. This remains session persistence only, with no new disk-save support. Human Windows/Godot 4.5.1 playtest and merge approval remain with the Director.
