# ROADMAP — Time is Precious

Last updated: 2026-05-17

## Development Principle
Build a small playable prototype first.

Do not expand into large systems before the core loop is stable.

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
Assign worker
↓
Produce output
↓
Use output for progression
```

Minimum success criteria:
- Player can collect at least one resource.
- Resource enters storage.
- Player can start one process.
- Worker can be assigned.
- Process produces output.
- Output can be used for a visible progression step.

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
- Player can hire applicant. (basic MVP flow implemented)
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
- Time display.
- Worker status display.
- Process status display.
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
1. Audit current worker code.
2. Identify where `is_hired` or equivalent logic is used.
3. Check whether consumption is tied to worker status.
4. Propose separation between population status and employment status.
5. Keep code changes small and explain them before implementation.

## Codex Instruction
When updating this project, Codex should maintain these files:
- `DEVLOG.md`
- `ARCHITECTURE.md`
- `ASSET_GUIDE.md`
- `ROADMAP.md`

Future files may be added as needed.

Do not overwrite design direction without explaining the reason.
