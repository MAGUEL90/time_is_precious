# DEVLOG - Time is Precious

Last updated: 2026-08-01

Repository snapshot: merged work through PR #85.

## Project Identity

**Time is Precious** is a 2D top-down management RPG with a Mesopotamian-inspired setting, built in Godot Engine 4 / 4.5.

Core pillars:
- Time as the main strategic pressure.
- Resource and inventory management.
- Player condition management.
- Worker and NPC delegation.
- Production chains.
- City and player-home progression.
- Variable progression shaped by player decisions and controlled system variation.

## Current Development Phase

The project is in the technical prototype and playable-loop integration phase.

The immediate goal is not to add many unrelated systems. The goal is to connect the systems that already exist into a clear and repeatable daily loop:

```text
Wake at home
-> Enter the city
-> Gather or manage items
-> Maintain player conditions
-> Assign work and process resources
-> Advance time
-> Return home and sleep
-> Face consequences when needs are ignored
```

Current priorities:
1. Connect the home, item, condition, citizen, and workshop systems into one stable loop.
2. Improve player-facing clarity, feedback, and visual consistency.
3. Finish incomplete parts of the mudbrick production loop.
4. Tune sleep, condition drain, recovery, and Nightmare consequences.
5. Add real save/load persistence after the runtime loop is stable.

## Current Playable Snapshot

### World, Citizens, and Character Presentation
- Modular player, worker, and citizen visuals use layered body, head, clothes, hair, hands, and accessories.
- Citizens can use configurable visual profiles.
- Citizens can idle and wander independently.
- Character facing updates during horizontal and diagonal movement.
- Player, citizens, pickups, and world objects participate in the current Y-sort setup.
- Immigration requests can generate citizens and allow batch accept/reject decisions.

### Items and Inventory
- Pickups have interaction prompts, highlighting, pickup animation, and item-change popup feedback.
- Inventory supports item categories, pages, item details, option panels, quantity selection, and confirmation flows.
- Inventory uses a stable 5x3 slot layout with visible empty placeholders.
- Items can be used, sent to city stock, or dropped depending on item/action rules.
- Items can be dragged out of the inventory, dropped near the player, and collected again.
- Inventory weight and capacity rules remain part of the item flow.

### Pixel Resolution and Gameplay HUD
- Logical viewport is 320x180 while the game window remains 1280x720.
- Pixel snapping is enabled for consistent pixel rendering.
- Previous camera scaling that caused inconsistent world/UI scale was removed.
- Pickup and item feedback avoid scale effects that distort pixel art.
- Compact Top HUD and Bottom HUD components display live gameplay information.
- The Top HUD can collapse.
- Holding `Tab` reveals the player status drawer.
- Current HUD values include Fatigue, Hunger, Focus, Experience, time, weather, day, and population.

### Player Conditions, Sleep, and Consequences
- Fatigue, Hunger, Focus, and Experience are active player values.
- Conditions change as in-game time passes.
- Valid sleep interactions advance time by seven hours.
- Sleep recovery is affected by the player's nourishment.
- Sleep is limited to once per in-game day.
- Critical conditions can trigger Collapse.
- Collapse sends the player into the Nightmare World.
- Nightmare gameplay includes limited vision, tier-based duration/penalties, exit or timeout completion, and a result screen.
- Nightmare time and penalties are converted back into normal-world consequences.

### Player Home and Scene Flow
- The player home interior is the current main starting scene.
- Reusable doors and spawn-point routing connect the home and city.
- Player conditions, Experience, sleep usage, and Collapse state persist across scene changes during the current runtime session.
- World time continues while the player is inside the home.

### Workshop and Worker Loop
- The player can deposit and withdraw selected item quantities between inventory and workshop storage.
- Workshop item movement uses popup feedback.
- Workers can be assigned through the workshop flow.
- Workshop jobs validate worker profession and resource requirements.
- Mudbrick production can consume workshop materials and produce claimable `wet_mudbrick` output.
- Worker daily needs affect satisfaction and reliability, which can influence output.
- Service fees can be deducted in Shekel when the work flow completes.

## Milestone History

### PR #66 - Modular Citizens and Immigration
Added runtime citizen identity, visual profiles, citizen generation/registry, city spawning, and immigration accept/reject flow.

### PR #67 - Gabbi Character Bible
Documented Gabbi as a Unique NPC, childhood friend, early guide, social bridge, and story-support character.

### PR #68 - Playable Workshop Storage and Mudbrick Flow
Added player-facing workshop actions, storage deposit/withdraw, item transfer UI, worker assignment prototype, mudbrick job start, and claimable output.

### PR #69-#72 - Dialogue Stability Pass
Fixed dialogue naming, intro triggering, NPC dialogue locking, pause/facing behavior, and invalid interaction prompts.

### PR #73 - Minimal Worker Loop
Connected workshop jobs to time ticks, city/worker needs, satisfaction/reliability, service fees, and claimable output testing.

### PR #74 - AI NPC Quest Architecture
Documented the long-term separation between AI character voice/intent, Quest System validation, and Game State authority. This is architecture only, not active gameplay.

### PR #75 - Intro Dialogue and Gameplay HUD
Added Gabbi's intro flow, the updated chatbox, delayed response choices, NPC-relative dialogue positioning, and an early gameplay HUD.

### PR #76 - Workshop Worker Assignment and Job Start
Added worker slots, available-worker selection, Back/Next navigation, discard confirmation, profession checks, missing-requirement feedback, and job start flow.

### PR #77 - Item Description Writing Guide
Defined the readable, earthy, lightly humorous English style for Mesopotamian-inspired item descriptions.

### PR #78 - Pickup and Inventory Item Flow
Improved pickup interaction and inventory UI, added item details and action panels, and added use/send/remove feedback flows.

### PR #79 - Inventory Drop and Drag Flow
Added drag-out dropping, quantity confirmation, drop spawn animation, randomized player-relative placement, and re-pickup support.

### PR #80 - Demo Distribution Plan
Defined the One Percent Studio website as the future primary browser-demo hub, with staged expansion to itch.io, Steam, Game Jolt, and CrazyGames.

### PR #81 - Player Sleep Condition Foundation
Added Fatigue, Hunger, Focus, sleep limits, time advancement, nourishment-based recovery, Collapse preparation, and Focus utility methods.

### PR #82 - Sleep and Nightmare Collapse MVP
Completed the current sleep, Collapse, Nightmare World, limited vision, consequence, result-screen, and return-to-world MVP loop.

### PR #83 - Pixel-Perfect Resolution, Inventory, and HUD Polish
Established the 320x180 logical viewport, pixel snapping, stable 5x3 inventory, clearer item panels, compact HUD, and live player status drawer.

### PR #84 - Character Animation and Citizen Visual Polish
Updated layered idle/walk animation assets and playback, citizen wandering/facing, pickup prompt feedback, and world Y-sorting.

### PR #85 - Player Home Daily Loop
Added the player home starting scene, home/city transitions, runtime state preservation, and world-time continuity inside the home.

## Current Known Boundaries

- Player state persists across scenes only during the current runtime session; it is not saved to disk yet.
- The local headless runtime still has a known Godot signal 11 crash in the player-home flow; the complete flow was manually validated in the editor.
- Citizen movement at low speeds can still appear pixel-stepped because of pixel-snapped transforms.
- Public-facing terminology for Hunger / Body Fuel / Satiety still needs a final decision.
- Condition drain, sleep recovery, same-day sleep rules, and Collapse penalties still need tuning.
- Final warning sprites, animation, and audio for critical conditions are not complete.
- Nightmare difficulty and presentation need further expansion and polish.
- Workshop claim/continue production and the drying path from `wet_mudbrick` to `sun_dried_mudbrick` still need a complete player-facing pass.
- AI NPC quest integration is documented only and must not be presented as an implemented feature.
- The current prototype is not yet ready for uncontrolled public demo distribution.

## Next Development Priorities

1. Validate the complete home-to-city daily loop without manual setup.
2. Finish the player-facing mudbrick claim and drying process.
3. Confirm final production output can be stored, seen, and used for visible progression.
4. Improve missing-resource, storage-full, inventory-full, and failed-action feedback.
5. Tune Fatigue, Hunger, Focus, sleep, Collapse, and Nightmare balance.
6. Add save/load persistence for player conditions, sleep state, citizens, inventory, and progression.
7. Prepare a small internal playtest checklist before wider demo work.

## Design Decisions Still in Force

### Resident and Worker Are Different States

Population status and employment status must remain separate.

```text
Migrant arrives
-> Player accepts or rejects
-> Accepted migrant becomes a resident/citizen
-> Resident consumes city resources
-> Eligible resident may become an applicant
-> Player hires the applicant
-> Hired worker can be assigned to work
```

Food and basic city needs depend on resident/citizen status, not employment status.

### Variable Progression, Not Pure Randomness

The game should support different city-development paths through controlled variation.

Correct direction:

```text
Player decision
-> System state
-> Controlled variation
-> Readable result
```

Randomness should create strategic variation, not outcomes the player cannot understand or influence.

## Related Project Documents

- `ROADMAP.md` - development phases and implementation priorities.
- `ARCHITECTURE.md` - technical responsibilities and system boundaries.
- `DEMO_DISTRIBUTION.md` - staged demo rollout strategy.
- `docs/CONTENT_LOG.md` - published content, current production, and future content backlog.
