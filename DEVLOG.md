# DEVLOG - Time is Precious

Last updated: 2026-10-18

Repository snapshot: merged implementation through PR #115 (`d6ea244`). The dated
milestone entries preserve what each checkpoint introduced; the current playable
status and open validation gates are summarized separately below.

## Project Identity

**Time is Precious** is a 2D top-down management RPG with a Mesopotamian-inspired setting, built in Godot Engine 4.5.x.

Core pillars:
- Time as the main strategic pressure.
- Resource and inventory management.
- Player condition management.
- Worker and NPC delegation.
- Production chains.
- City and player-home progression.
- Variable progression shaped by player decisions and controlled system variation.

## Current Development Phase

The project is in **Technical Prototype -> Playable Loop Integration**.

The immediate goal is not to add many unrelated systems. The goal is to connect the systems that already exist into a clear and repeatable daily loop:

```text
Wake at home
-> Enter the city
-> Gather or manage items
-> Maintain player conditions
-> Review / hire workers when relevant
-> Assign work and process resources
-> Advance time
-> Return home and sleep
-> Face consequences when needs are ignored
```

Current priorities are maintained in `ROADMAP.md`. The mudbrick claim and drying
chain is integrated and its authored main-map test completes two cycles with
fixture-owned resources, worker and Shekel. The normal fresh-start route and a
complete daily/production journey have separate 2026-10-18 normal-start automated
evidence below; fixture success itself is not a from-zero playthrough pass.

## Current Playable / Implemented Snapshot

### World, Citizens, and Character Presentation
- Modular player, worker, and citizen visuals use layered body, head, clothes, hair, hands, and accessories.
- Citizens can use configurable visual profiles.
- Citizens can idle and wander independently.
- Character facing updates during horizontal and diagonal movement.
- Player, citizens, pickups, and world objects participate in the Y-sort setup.
- Immigration requests can generate citizens and allow batch accept/reject decisions.

### Population and Employment Lifecycle
- `CitizenData` separates population status from employment status.
- Accepted residents can be evaluated for applicant eligibility.
- Eligible residents can become Job Board applicants.
- Job Board hiring creates linked WorkerData and moves the citizen to `HIRED`.
- Workshop assignment/unassignment updates the linked citizen state between `HIRED` and `ASSIGNED`.
- Integration coverage exists for population/employment lifecycle behavior.
- Legacy workers without linked CitizenData retain compatibility paths where required.

### Items and Inventory
- Pickups have interaction prompts, highlighting, pickup animation, and item-change popup feedback.
- Inventory supports item categories, pages, item details, option panels, quantity selection, and confirmation flows.
- Inventory uses a stable 5x3 slot layout with visible empty placeholders.
- Items can be used, sent to city stock, or dropped depending on item/action rules.
- Items can be dragged out, dropped near the player, and collected again.
- Inventory weight and capacity rules remain part of the item flow.

### Display and Gameplay HUD
- Current logical viewport is `400 x 225`.
- Current development window override is `1200 x 675`.
- Viewport stretch, integer scaling, GL Compatibility, and 2D transform pixel snapping are active.
- Compact Top HUD and Bottom HUD components display live gameplay information.
- The Top HUD can collapse.
- Holding `Tab` reveals the player status drawer.
- Current HUD values include Fatigue, Hunger, Focus, Experience, time, weather, day, and population.

### Player Conditions, Sleep, and Consequences
- Fatigue, Hunger, Focus, and Experience are active player values.
- Conditions change as in-game time passes.
- Sleep is the intended early recovery system and is limited to once per in-game day.
- Sleep restores Fatigue/Focus according to current rules but does not function as free Hunger recovery.
- Critical conditions can trigger Collapse.
- Collapse sends the player into the Nightmare World.
- Nightmare gameplay includes tier-based penalties, escape/timeout outcomes, shrinking vision near timeout, result feedback, and return-to-world consequences.

### Player Home and Scene Flow
- Startup New Game opens the city; the home interior provides sleep and autosave.
- Reusable doors and spawn-point routing connect home and city.
- Selected player state persists across scene changes during the runtime session.
- World time continues across the relevant scene flow.
- City/home checkpoints, sleep autosave and startup Continue are implemented.
- Continue restores the saved checkpoint without offline production.
- The Game Director reported a Windows sleep-checkpoint/Continue round trip
  with harvested palm stock restored; the new cloud normal-start evidence is separate.

### Workshop and Worker Loop
- The player can deposit and withdraw selected quantities between inventory and workshop storage.
- Workshop item movement uses player-facing feedback.
- Workers can be assigned through the workshop flow.
- Assignment is connected to citizen employment state.
- Workshop jobs validate worker profession and resource requirements.
- WorkStateRuntime keeps work/process systems synchronized with world-time changes.
- Mudbrick production can consume workshop materials and produce claimable `wet_mudbrick` output.
- The player-facing claim, drying, and finished-brick path is integrated. The
  main-map test completes two cycles, but uses fixture-owned starting resources,
  worker and Shekel.
- Worker daily needs can affect satisfaction/reliability and work output.
- Service-fee support exists in the work flow.

The 2026-10-18 branch audit demonstrates normal-start access to repeated drying,
paid output, yard level 2 and merchant brick sales. Human readability and broader
city progression remain open; details and limitations are in the audit report.

### City, Merchant, and Persistence Integration
- The current main map combines the six date palms with the city wall/raid and
  warehouse layout. Palm pickup views remain owned by their source state and are
  not restored as personal dropped items.
- PR #114 includes the city progression, raid and startup checkpoint flow, with
  city/home state saved through the existing checkpoint system.
- The common traveling merchant MVP from PR #110 is merged. Its configured
  prices, stock and quotas remain provisional playtest values; broader visitor
  tiers and city-stat-driven rules remain deferred.
- PR #115 persists registered city pickup-source stock, remaining refill time
  and RNG under schema v4. Date palms are compatibility wrappers. Source IDs and
  authored configuration are part of the save contract; content changes need
  explicit migration. v1/v2 and v3 have explicit readers/migration behavior.
- The Game Director reported `PickupSourcesTest: PASS` on Windows. This is scoped
  fixture evidence, not a claim that all cloud regression suites were rerun there.

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
Added Gabbi's intro flow, updated dialogue presentation, delayed response choices, NPC-relative dialogue positioning, and an early gameplay HUD.

### PR #76 - Workshop Worker Assignment and Job Start
Added worker slots, available-worker selection, navigation/confirmation behavior, profession checks, missing-requirement feedback, and job start flow.

### PR #77 - Item Description Writing Guide
Defined the readable, earthy, lightly humorous English style for Mesopotamian-inspired item descriptions.

### PR #78 - Pickup and Inventory Item Flow
Improved pickup interaction and inventory UI, added item details/action panels, and use/send/remove feedback flows.

### PR #79 - Inventory Drop and Drag Flow
Added drag-out dropping, quantity confirmation, drop spawn animation, randomized player-relative placement, and re-pickup support.

### PR #80 - Demo Distribution Plan
Defined the One Percent Studio website as the future primary demo hub, with staged expansion to itch.io, Steam, Game Jolt, and CrazyGames.

### PR #81 - Player Sleep Condition Foundation
Added Fatigue, Hunger, Focus, sleep limits, time advancement, nourishment-based recovery, Collapse preparation, and Focus utility methods.

### PR #82 - Sleep and Nightmare Collapse MVP
Completed the then-current sleep, Collapse, Nightmare World, limited-vision, consequence, result-screen, and return-to-world MVP loop.

### PR #83 - Pixel Resolution, Inventory, and HUD Polish
Established the low logical-viewport pixel-art foundation, pixel snapping, stable inventory layout, compact HUD, and player status drawer. Later merged work adjusted the internal viewport again; current `project.godot` is authoritative for the active value.

### PR #84 - Character Animation and Citizen Visual Polish
Updated layered idle/walk animation assets and playback, citizen wandering/facing, pickup prompt feedback, and world Y-sorting.

### PR #85 - Player Home Daily Loop
Added the player home starting scene, home/city transitions, runtime state preservation, and world-time continuity inside the home.

### PR #86 - Devlog and Content Log Refresh
Refreshed project documentation through PR #85 and added content-production tracking.

### PR #87 - Population / Employment State Integration
Established CitizenData as population/employment authority, linked workers to citizens, preserved legacy-worker compatibility, and added integration coverage.

### PR #88 - Citizen Applicant Hiring Flow
Added satisfaction-based applicant eligibility, daily application evaluation, Job Board hiring, linked WorkerData creation, and lifecycle integration tests.

### PR #89 - Citizen Worker Assignment Lifecycle
Connected workshop assignment/unassignment to citizen employment state, made assignment changes persistent within runtime UI flow, and expanded integration coverage.

### PR #90 - Collapse / Nightmare Consequences and Content
Expanded Collapse/Nightmare behavior with repeatable collapse, five nightmare tiers, tier-based penalties, escape/timeout results, shrinking vision near timeout, HUD/control handling, and updated internal presentation.

### PR #91 - Workshop Content Integration
Integrated the Workshop into the main content scene, added player-facing storage/assignment/job flow, profession/resource validation, WorkStateRuntime, and world-time work synchronization. Validation included the population/employment integration test and Godot 4.5.1 project scan.

### PR #92 - Sleep and Focus Design Update
Updated the design source for Sleep, Focus, Hunger/Fatigue relationship, once-per-day sleep rules, Collapse cost, and the Player-vs-Worker role distinction. This was a design-document update, not a new gameplay implementation claim.

### PR #93 - Project Progress Hierarchy
Made `ROADMAP.md` the single source of truth for current position/priority and clarified the separate roles of DEVLOG, ARCHITECTURE, game concept, and root/branch map.

### PR #94 - Agent Control Pack Staging
Added `AGENTS.md` and `docs/agent-control/` governance templates. At this
checkpoint the control pack remained `TEMPLATE — NOT ACTIVE` and did not change
gameplay or project configuration; later PRs activated it.

### PR #110 - Traveling Merchant MVP
Merged the common traveling merchant with finite stock and funds, buy/sell
transactions, randomized per-visit requests and a stable request ledger. The
Game Director closed this MVP scope with additional goods, Rare visitors,
city-stat-driven visitor rules and quest dialogue deferred. Request and price
configuration remains provisional. See
`docs/task_reports/merchant-mvp-closure-2026-10-04.md`.

### PR #111 - Food MVP: Six Date Palms
Merged the six-palm food loop and walking-playtest checkpoint. At merge, stock
and refill state were session-only; PR #115 later made authored source state
persistent. The 72-hour route evidence covers the earlier map positions and is
not a balance approval for the current layout. See
`docs/task_reports/food-walking-playtest-2026-10-05.md`.

### PR #113 - Warehouse and City Storage Integration
Merged the warehouse visuals and the city-storage hauling integration on the
gameplay branch. See the warehouse and hauling evidence referenced from
`ROADMAP.md`.

### PR #114 - Gameplay/Main Integration
Merged the current gameplay city layout with the warehouse, six relocated date
palms, raid/city progression, startup menu and sleep checkpoint flow, plus the
UI consistency updates. The previous 72-hour walking results apply to the old
map positions. The integration report records 29 passing suites and scoped
startup/checkpoint modes on cloud Linux; it does not claim a new full survival
playthrough or Windows/Android acceptance. See
`docs/task_reports/gameplay-main-integration-2026-10-17.md`.

### PR #115 - Persistent and Reusable Pickup Sources
Merged independent stock, refill timer and RNG persistence for registered city
pickup sources, with date palms retained as compatibility wrappers. The active
save format is v4 and includes explicit legacy readers/migration. The Game
Director reported a Windows sleep-checkpoint/Continue round trip with harvested
palm stock restored, plus `PickupSourcesTest: PASS`; the full fresh-start
playthrough remains a separate validation gate. See
`docs/task_reports/reusable-pickup-sources-2026-10-18.md` and
`docs/task_reports/date-palm-persistence-2026-10-17.md`.

## Branch audit — normal-start MVP (2026-10-18; not merged)

`test/gameplay/mvp-first-playthrough` adds a normal-start input/UI driver and fixes
an exiting merchant view retaining its persistent-ledger subscription. It records
New Game with zero personal resources/workers, natural merchant funding, hiring,
construction, active needs, repeated drying, yard upgrade, output sale and a sleep
checkpoint restored identically in a new process. No economy, resource, save
schema or City Storage policy changed. See
`docs/task_reports/mvp-first-playthrough-2026-10-18.md` for exact samples and tests.

## Current Known Boundaries

- Normal-start workshop automation passes for the recorded samples; overall MVP
  acceptance remains partial because human QA and city/defense supply gates remain.
- City/home save checkpoints, sleep autosave, Continue and PR #115 source-state
  persistence are implemented and have scoped automated plus user-reported
  checks. Multiple slots, other map types, Android and export builds remain
  unverified or out of current save scope.
- The authored main-map mudbrick integration test uses fixture-owned starting
  resources, worker and Shekel. It does not establish that a fresh normal start
  can reach the same output without test setup.
- Drying Yard upgrades and merchant sales use earned final bricks in the new
  normal-start driver; city-level progression is separate and lacks clothing,
  shelter and Stone access on the current map.
- Citizen/worker lifecycle exists at prototype level and current city/home checkpoints
  save its supported state. It still needs broader daily-loop validation, balancing,
  and later profession/content expansion.
- Condition drain, sleep recovery, Collapse/Nightmare penalties, citizen needs pressure, satisfaction/reliability effects and economy values still need tuning.
- Citizen movement at low speeds can appear pixel-stepped because of pixel-snapped transforms.
- Final warning presentation/audio for critical conditions is not complete.
- AI NPC quest integration is architecture/design direction only and must not be presented as an implemented gameplay feature.
- Android is a target platform direction, not a currently proven device-performance/UX claim.
- The prototype is not ready for uncontrolled public demo distribution.

## Next Development Priorities

See `ROADMAP.md` for the authoritative ordered list. The active gate is a
review of the recorded fresh-start journey, human clarity, merchant funding delay
and missing citizen/defense supply paths. Balance/content decisions remain with
the Game Director. Do not list city/home disk persistence as unimplemented.

## Design Decisions Still in Force

### Resident and Worker Are Different States

```text
Migrant arrives
-> Player accepts or rejects
-> Accepted migrant becomes resident/citizen
-> Resident consumes city resources
-> Eligible resident may become applicant
-> Player hires applicant
-> Hired worker may be assigned
-> Assigned worker may execute work
```

Food and basic city needs depend on resident/citizen status, not employment status.

### Variable Progression, Not Pure Randomness

```text
Player decision
-> System state
-> Controlled variation
-> Readable result
```

Randomness should create strategic variation, not outcomes the player cannot understand or influence.

## Related Project Documents

- `docs/game-concept.md` - high-level game-design source of truth.
- `ROADMAP.md` - current development position and priority.
- `ARCHITECTURE.md` - technical responsibilities and system boundaries.
- `docs/root-branch-map.md` - technical domain and branch taxonomy.
- `docs/game-concept-resolution.md` - display/presentation direction.
- `DEMO_DISTRIBUTION.md` - staged demo rollout strategy.
- `docs/CONTENT_LOG.md` - content-production tracking.
- `AGENTS.md` and `docs/agent-control/` - active agent governance and project controls.
