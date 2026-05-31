# ROADMAP — Time is Precious

Last updated: 2026-05-31

## Development Principle
Build a small playable prototype first.

Do not expand into large systems before the core loop is stable.

## Current Main Priority — Playable Core Loop
Status: The project has moved beyond concept planning and is now in the technical prototype stage.

The current priority is **not** to add more large systems yet. The main goal is to turn the existing technical systems into one complete, repeatable, playable loop.

Known implemented or partially implemented systems:
- ItemDatabase
- Inventory with weight handling
- WorkshopStorage
- WorkManager
- ProcessManager
- Mudbrick production smoke test
- Drying process path

### Target Playable Loop
The first complete loop should be:

```text
Clay/Mud
↓
Player Inventory
↓
Inventory weight / capacity check
↓
WorkshopStorage deposit
↓
Mudbrick process
↓
Drying process
↓
Dried Mudbrick
↓
Visible output / usable item
```

### Current Risk
The systems may exist technically, but the game is not yet validated as a fun playable slice.

The next development work should focus on clarity, feedback, repeatability, and player-facing usability.

### Do Not Prioritize Yet
Avoid expanding into these areas until the playable loop above feels stable:
- Large NPC behavior expansion
- Complex economy balancing
- More resource chains
- Advanced AI Advisor NPC
- Large content expansion
- Steam/demo planning

### Immediate Execution Checklist
- [ ] Lock the MVP scope around one production chain.
- [ ] Make the mudbrick loop playable from start to finish.
- [ ] Add simple UI feedback for inventory, storage, process status, and output.
- [ ] Confirm inventory weight affects the player meaningfully.
- [ ] Confirm WorkshopStorage receives and spends materials correctly.
- [ ] Confirm WorkManager and ProcessManager can run the full process without manual debugging.
- [ ] Confirm the final item can be seen, stored, and used as a real output.
- [ ] Create a small internal playtest checklist.

## Current Phase
### Phase 0 — Foundation Review
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

### Phase 0.5 — Playable Loop Stabilization
Goal: connect the existing systems into one player-facing loop before expanding scope.

Focus:
- Inventory → WorkshopStorage transfer
- WorkshopStorage → ProcessManager input spending
- ProcessManager → output generation
- Mudbrick → drying → dried mudbrick chain
- Basic UI feedback for each step
- Player clarity: what happened, what is missing, what finished

Minimum success criteria:
- Player can start with or collect clay/mud.
- Player can carry it with weight/capacity respected.
- Player can deposit it into WorkshopStorage.
- Player can start the mudbrick process.
- The process spends the correct input.
- The drying process produces dried mudbrick.
- The final output is visible to the player.
- The loop can be repeated without manual debugging.

## Phase 1 — Core Loop Prototype
Goal: make the game playable in a small loop.

Core loop:
```text
Gather resource
↓
Store resource
↓
Process resource
↓
Produce output
↓
Use output for progression
```

Minimum success criteria:
- Player can collect at least one resource.
- Resource enters inventory and/or storage correctly.
- Player can start one process.
- Process produces output.
- Output can be used for a visible progression step.
- Worker assignment can be added after the manual player loop is stable.

## Phase 2 — Population and Worker Separation
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
```

Minimum success criteria:
- New migrant can arrive.
- Player can accept/reject migrant.
- Accepted migrant becomes resident.
- Resident consumes food.
- Eligible resident can appear on Job Board.
- Player can hire applicant.
- Hired worker can be assigned.

## Phase 3 — Prototype Asset Pass
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

## Phase 4 — Basic UI Pass
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

## Phase 5 — Save/Load Preparation
Only start after the prototype loop is stable.

Do not prioritize this too early unless the current architecture requires preparation.

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
1. Verify the current mudbrick production path from input to output.
2. Verify the drying process path and final dried mudbrick output.
3. Verify inventory weight/capacity affects the loop meaningfully.
4. Verify WorkshopStorage receives, stores, and spends materials correctly.
5. Add or improve basic UI feedback for inventory, storage, process status, and output.
6. Keep worker/NPC delegation secondary until the manual playable loop is stable.
7. Keep code changes small and explain them before implementation.

## Codex Instruction
When updating this project, Codex should maintain these files:
- `DEVLOG.md`
- `ARCHITECTURE.md`
- `ASSET_GUIDE.md`
- `ROADMAP.md`

Future files may be added as needed.

Do not overwrite design direction without explaining the reason.

Codex should prioritize the playable core loop before expanding into new major systems.
