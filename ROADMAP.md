# ROADMAP - Time is Precious

Last updated: 2026-07-06

## Development Principle
Build a small playable prototype first.

Do not expand into large systems before the core loop is stable.

The game should also avoid becoming too deterministic. Long-term, player progression should vary between playthroughs through controlled randomness and system-driven variation.

## Current Main Priority - Playable Core Loop
Status: The project has moved beyond concept planning and is now in the technical prototype stage.

The current priority is **not** to add more large systems yet. The main goal is to turn the existing technical systems into one complete, repeatable, playable loop.

Merged milestone history through PR #66:
- PR #57: Applicant offers shown on the Job Board.
- PR #58: Game Dev HQ planning docs added.
- PR #59: Asset control docs v0.1 added.
- PR #61: Modular worker visual added.
- PR #62: Palette guide updated to v0.2.
- PR #63: Roadmap updated around the playable core loop.
- PR #64: Variable progression design pillar added.
- PR #65: Resolution and platform display direction documented.
- PR #66: Modular citizens and immigration flow added.

Current local milestone after PR #66:
- Workshop menu is player-facing.
- Workshop storage can receive and return items.
- Item transfer UI supports selected quantities.
- Item movement popup gives deposit/withdraw feedback.
- Prototype worker assignment can attach an available worker to the workshop.
- Mudbrick job can start from workshop storage.
- NPC mudbrick output enters claimable workshop escrow.

Known implemented or partially implemented systems:
- ItemDatabase
- Inventory with weight handling
- WorkshopStorage
- WorkManager
- ProcessManager
- Mudbrick production smoke test
- Drying process path
- Job Board applicant-offer direction
- Asset guide, palette guide, and asset registry docs
- Shared modular character visual assets
- PlayerVisual and BaseWorkerVisual modular setup
- CitizenData and VisualProfile resources
- CitizenManager runtime registry
- CitizenGenerator prototype random citizen creation
- ImmigrationManager prototype immigration pressure/chance flow
- CitySpawner and CitizenActor prototype city population display
- Immigration request UI with accept/reject batch decision
- Workshop menu UI
- Workshop storage menu UI
- Reusable item transfer UI
- Item change popup feedback

## Target Playable Loop
The first complete loop should be:

```text
Clay / straw / water
-> Player Inventory
-> Inventory weight / capacity check
-> WorkshopStorage deposit
-> Assign worker
-> Start mudbrick job
-> Wet mudbrick claimable output
-> Drying process
-> Sun-dried mudbrick
-> Visible output / usable item
```

Current status:
- Done: inventory to workshop deposit.
- Done: workshop to inventory withdraw.
- Done: assigned prototype worker can start mudbrick job.
- Done: mudbrick job consumes workshop storage.
- Done: NPC output enters claimable escrow as `wet_mudbrick`.
- Pending: player-facing claim/continue-process pass after `wet_mudbrick` is ready.
- Pending: drying process UI/feedback from `wet_mudbrick` to `sun_dried_mudbrick`.
- Pending: final output use for visible progression.

## Current Risk
The systems may exist technically, but the game is not yet validated as a fun playable slice.

The next development work should focus on clarity, feedback, repeatability, and player-facing usability.

## Design Risk: Too Predictable
Time is Precious should not become a game where every player can easily predict the same best route.

Future systems should support controlled variation, such as:
- Migrant count variation.
- Applicant quality variation.
- Different resident traits.
- Different opportunity timing.
- Small production or needs-pressure variation.

This should be added carefully after the core loop works. The early prototype may use fixed values for stability, but the architecture should not lock the game into fixed outcomes forever.

## Do Not Prioritize Yet
Avoid expanding into these areas until the playable loop above feels stable:
- Large NPC behavior expansion
- Complex economy balancing
- More resource chains
- Advanced AI Advisor NPC
- Large content expansion
- Full public demo expansion before the core loop is stable

## Immediate Execution Checklist
- [x] Lock the MVP scope around one production chain.
- [x] Make inventory-to-workshop deposit player-facing.
- [x] Add workshop storage withdraw.
- [x] Add basic item movement popup feedback.
- [x] Confirm WorkshopStorage receives and spends materials correctly.
- [x] Start mudbrick job from workshop storage with an assigned prototype worker.
- [x] Confirm NPC mudbrick output enters claimable escrow.
- [ ] Separate `Assign Worker` and `Start Job` into clearer player-facing actions.
- [ ] Add workshop job selection UI, even if only `Mudbrick Making` exists at first.
- [ ] Verify claim / continue process path after `wet_mudbrick` is ready.
- [ ] Verify drying process path and final `sun_dried_mudbrick` output.
- [ ] Confirm the final item can be seen, stored, and used as a real output.
- [ ] Improve failure feedback for storage full / inventory full / missing materials.
- [ ] Create a small internal playtest checklist.

## Current Phase
### Phase 0 - Foundation Review
Goal: understand and stabilize the existing systems.

Focus:
- WorkManager
- ProcessManager
- WorkshopStorage
- Resource / Item system
- NPC delegation
- Worker Hub
- Job Board

Deliverable:
- Clear understanding of how resources, work, processing, storage, and workers connect.

Status:
- Mostly complete for the mudbrick prototype path.

### Phase 0.5 - Playable Loop Stabilization
Goal: connect the existing systems into one player-facing loop before expanding scope.

Focus:
- Inventory -> WorkshopStorage transfer
- WorkshopStorage -> WorkManager input spending
- WorkManager -> claimable output generation
- Claimable wet mudbrick -> drying process
- Drying process -> sun-dried mudbrick
- Basic UI feedback for each step
- Player clarity: what happened, what is missing, what finished

Minimum success criteria:
- Player can start with or collect clay/mud.
- Player can carry it with weight/capacity respected.
- Player can deposit it into WorkshopStorage.
- Player can withdraw stored workshop items.
- Player can assign a worker.
- Player can start the mudbrick job.
- The job spends the correct input.
- NPC job output becomes claimable.
- The drying process produces dried mudbrick.
- The final output is visible to the player.
- The loop can be repeated without manual debugging.

Status:
- In progress.
- Deposit, withdraw, assign worker, and mudbrick job start are working in manual runtime tests.
- Claim/continue process and drying still need player-facing verification.

## Phase 1 - Core Loop Prototype
Goal: make the game playable in a small loop.

Core loop:

```text
Gather resource
-> Store resource
-> Assign worker
-> Process resource
-> Produce output
-> Use output for progression
```

Minimum success criteria:
- Player can collect at least one resource.
- Resource enters inventory and/or storage correctly.
- Player can start one process/job.
- Process/job produces output.
- Output can be used for a visible progression step.

## Phase 2 - Population and Worker Separation
Goal: separate resident/citizen logic from worker/employment logic.

Design decision:
- Residents consume food.
- Workers are residents with employment status.
- Hiring does not start consumption.
- Accepting a migrant as resident starts consumption.

Required model:

```text
Population Status:
- migrant
- resident
- rejected
- left_city

Employment Status:
- unemployed
- applicant
- hired
- assigned
- working
```

Minimum success criteria:
- New migrant can arrive.
- Player can accept/reject migrant.
- Accepted migrant becomes resident.
- Resident consumes food.
- Eligible resident can appear on Job Board.
- Player can hire applicant.
- Hired worker can be assigned.

Prototype status after PR #66:
- Done: immigrant/citizen candidates can be generated.
- Done: player can accept or reject the full pending immigrant batch.
- Done: accepted immigrants enter `CitizenManager` as citizens.
- Done: accepted citizens can spawn as visible city actors.
- Done: HUD need counts can read from the citizen runtime registry.
- Pending: daily food/clothing/shelter consumption and balance.
- Pending: citizen persistence through save/load.
- Pending: applicant conversion from citizens into Job Board offers.
- Pending: hiring accepted citizens into workers and assigning them to jobs.

## Phase 2.5 - Controlled Variation Layer
Goal: prepare the game to create different progression paths between players without breaking player agency.

This phase should come after the basic population/worker flow is stable.

Possible controlled variation systems:
- Migrant arrival count range based on city prosperity.
- Randomized resident/applicant traits within clear limits.
- Slight differences in productivity, loyalty, or needs pressure.
- Varying opportunity timing.
- Small modifiers to production or city events.

Minimum success criteria:
- Variation is visible between playthroughs.
- Player still understands why things happen.
- Randomness does not feel unfair.
- No important result is fully disconnected from player decisions.

## Phase 3 - Prototype Asset Pass
Goal: replace rough placeholders with consistent minimum assets.

Minimum asset list:
- Player sprite.
- Worker/NPC sprite.
- Migrant/resident variation.
- Resource nodes: clay/mud, wood, stone, grass/reed.
- Storage object.
- Workstation.
- Job Board.
- Worker Hub.
- House stage 0-3.
- Basic item/resource icons.

## Phase 4 - Basic UI Pass
Goal: make the prototype readable.

Minimum UI:
- Resource stock display.
- Inventory weight/capacity display.
- Time display.
- Worker status display.
- Process status display.
- WorkshopStorage status display.
- Job Board interface.
- Basic population/needs display.

## Phase 5 - Save/Load Preparation
Only start after the prototype loop is stable.

Do not prioritize this too early unless the current architecture requires preparation.

## Phase 6 - Demo Distribution and Playtesting
Only start execution after the playable loop is stable, readable, and testable without developer help.

Primary demo hub:
- One Percent Studio website.

Secondary distribution / test channels:
- itch.io for early public or limited-access web testing.
- Steam Playtest after a vertical slice exists and store-facing testing makes sense.
- Steam Demo when the build represents the intended quality direction.
- Game Jolt as an optional community mirror after presentation is clear.
- CrazyGames as a later browser discovery channel, not an early prototype target.

Reference document:
- See `DEMO_DISTRIBUTION.md` for rollout stages, platform roles, and demo readiness checklist.

Minimum success criteria:
- The demo has one approved current build.
- The One Percent Studio website clearly points to the current demo.
- The demo has a version number, known issues, controls, and a feedback path.
- External platforms are added gradually, not all at once.

## Not Yet Priority
Delay these until the core loop is stable:
- Large city simulation.
- Complex economy.
- Advanced NPC personality.
- Advisor NPC with memory.
- Large quest system.
- Advanced combat.
- Advanced VFX/SFX.
- Large asset library.
- Marketing trailer.

## Immediate Next Tasks
1. Separate `Assign Worker` and `Start Job` in the workshop UI.
2. Add a small job selection step for workshop jobs.
3. Verify the current claimable wet mudbrick path.
4. Verify the drying process path and final dried mudbrick output.
5. Improve UI feedback for missing materials, full storage, full inventory, and active jobs.
6. Keep worker/citizen conversion secondary until the workshop loop is stable.
7. Keep code changes small and explain them before implementation.

## Codex Instruction
When updating this project, Codex should maintain these files:
- `DEVLOG.md`
- `ARCHITECTURE.md`
- `ASSET_GUIDE.md`
- `ROADMAP.md`
- `DEMO_DISTRIBUTION.md`

Future files may be added as needed.

Do not overwrite design direction without explaining the reason.

Codex should prioritize the playable core loop before expanding into new major systems.

Codex should also avoid designing systems that are permanently fixed, fully predictable, or easy to solve. Use fixed values during early prototype only when needed for stability, then prepare the architecture for controlled variation later.

Codex should treat the One Percent Studio website as the primary demo hub unless the project direction is explicitly changed.
