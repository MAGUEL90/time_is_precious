# ARCHITECTURE - Time is Precious

Last updated: 2026-09-05

## Purpose

This document is the architectural source of truth for **Time is Precious**.

It defines technical responsibilities, ownership boundaries, state separation, and integration rules. It does not replace `docs/game-concept.md` for design intent or `ROADMAP.md` for current priority.

## Core Game Identity

Time is Precious is a 2D top-down management RPG focused on:
- Time pressure.
- Resource management.
- Work delegation.
- Production chains.
- City growth.
- Player home / settlement progression.
- Variable progression between players.
- Long-term AI-assisted unique NPCs that stay controlled by game systems.

## Current Architectural Priority

Do not expand into large systems too early.

Stabilize this core loop first:

```text
Gather resource
-> Store resource
-> Hire / assign suitable worker when needed
-> Start work/job
-> Produce output
-> Claim or continue processing output
-> Use output for progression
```

Current player-facing workshop foundation includes:
- Inventory-to-workshop transfer.
- Workshop deposit and withdraw.
- Worker assignment UI.
- Profession/resource validation.
- Mudbrick job start from workshop storage.
- World-time-driven work progression.
- NPC-produced output entering `WorkShopStorage.claimable_outputs`.

The current production architecture blocker is not job start. It is the player-facing continuation after `wet_mudbrick`: claim/route -> drying -> `sun_dried_mudbrick` -> visible progression.

## Source-of-truth roles

- `docs/game-concept.md` = intended game design.
- `ROADMAP.md` = current progress and priority.
- `ARCHITECTURE.md` = system responsibilities and boundaries.
- `DEVLOG.md` = merged implementation history.
- `docs/root-branch-map.md` = technical domain and branch taxonomy.
- Current source/scenes = implementation truth.

## Important Architecture Rule: Population != Employment

Do not mix population logic with employment logic.

An NPC can be a resident without being a worker.
An NPC can be hired but not assigned.
An assigned worker may not currently be executing a job.
An NPC consumes city needs because they are a resident, not because they are hired.

### Population / Citizenship Layer

Conceptual statuses:
- `migrant`
- `resident`
- `rejected`
- `left_city`

Responsibilities:
- whether the NPC belongs to the city
- whether the NPC counts toward population
- whether the NPC consumes city stock / resident needs

### Employment / Worker Layer

Conceptual statuses:
- `unemployed`
- `applicant`
- `hired`
- `assigned`
- `working`

Responsibilities:
- employment eligibility
- Job Board applicant visibility
- hiring
- workplace assignment
- active work execution

### Current lifecycle implementation

Merged prototype implementation now supports the main lifecycle:

```text
Accepted resident
-> daily applicant eligibility evaluation
-> APPLICANT
-> Job Board hire
-> linked WorkerData
-> HIRED
-> workshop assignment
-> ASSIGNED
-> job execution / worker runtime state
```

Key responsibilities:
- `CitizenData` owns population and employment status.
- `CitizenManager` owns the runtime citizen registry and applicant-state transitions.
- `WorkerDatabase` owns WorkerData lookup/creation plus hire/assign/unassign integration.
- `WorkerData` represents worker-specific work data while resolving linked citizen information where appropriate.
- Workshop assignment must update the linked citizen employment state rather than keeping an unrelated parallel flag.

Legacy worker compatibility may exist, but new work should not create additional disconnected employment authorities.

## Citizen / Immigration Layer

- `CitizenGenerator` creates prototype citizen data.
- `CitizenManager` stores the runtime citizen registry.
- `ImmigrationManager` evaluates immigration and manages pending batches.
- Accepted immigrants become residents/citizens.
- Rejected/left citizens must not consume city resources.
- `CitySpawner` / `CitizenActor` represent resident data in the world.
- Visual presentation should stay separate from gameplay authority unless an approved trait system intentionally connects them.

Current immigration approval remains batch-based unless design explicitly changes it.

## Applicant / Job Board Layer

For the current prototype, applicants originate from accepted residents.

```text
Resident
-> needs / eligibility check
-> Applicant
-> Job Board
-> Player hires
-> WorkerData linked to citizen identity
```

Do not spawn unrelated external applicants unless design explicitly introduces a separate applicant source.

Applicant evaluation is a gameplay-system responsibility, not a UI responsibility. Job Board UI displays and triggers approved actions; it must not invent eligibility rules.

## Worker Assignment Layer

Assignment is separate from hiring and separate from active job execution.

```text
HIRED
-> player assigns to workplace
-> ASSIGNED
-> job starts
-> active work runtime
```

Removing a worker from the workplace should return the linked employment state to the appropriate hired/idle state rather than deleting citizen identity.

Workshop UI must not become the authoritative storage location for worker employment state.

## City Needs Layer

Food/basic need consumption depends on population state.

Correct conceptual rule:

```text
if population_status == resident:
    consume_city_stock()
```

Incorrect:

```text
if is_hired:
    consume_city_stock()
```

Current daily needs/satisfaction/reliability behavior exists at prototype level, but balance remains unfinished.

## Workshop / Production Responsibilities

The workshop production family is currently earth/clay/construction-material work.

Current intended flow:

```text
Manage Storage
-> Deposit raw materials
-> Assign worker
-> Choose/start relevant job
-> Validate profession and resources
-> Job consumes workshop storage
-> World time advances work
-> NPC output enters claimable escrow
-> Player claims output or routes it forward
-> Further process where relevant
```

### Storage separation

`WorkShopStorage.items` and `claimable_outputs` are different concepts.

- Stored items = normal workshop inventory available for actions/processes.
- Claimable output = NPC-produced output awaiting player claim/routing.

Withdraw must not silently bypass claimable escrow.

### WorkManager

`WorkManager` is responsible for work orders, input consumption, timing, worker execution state, and routing output according to the work flow.

It must not become the authority for unrelated city population, UI layout, quest logic, or global economy design.

### ProcessManager

`ProcessManager` handles process/batch-style transformation logic. Future drying integration should reuse this responsibility where appropriate rather than embedding a second process engine inside UI scripts.

### WorkStateRuntime

Current project setup includes a runtime work-state bootstrap/autoload path so work/process systems can remain synchronized with world-time changes across the player-facing flow.

Do not add duplicate scene-local bootstrap instances without a specific architectural reason.

## Player Runtime / Scene Transition Responsibilities

The current prototype keeps selected player/runtime state across scene transitions.

- Player home is the main start flow.
- Home <-> city transitions use reusable scene/spawn routing.
- `PlayerRuntimeState` supports runtime persistence across scene changes.
- `SceneTransition` owns transition/routing behavior.

Runtime persistence is not the same as save/load to disk.

## Save / Persistence Boundary

Real save/load is not yet complete.

Future persistence should serialize authoritative data/state rather than spawned visual nodes.

Likely persisted domains will include:
- player conditions and progression
- day/sleep usage
- inventory
- citizens and employment states
- workshop/work/process state as required
- city resources

Before implementing persistence, define schema ownership and migration rules. Do not infer a stable schema from runtime objects alone.

## Display / UI Boundary

Current implementation uses a low logical viewport for pixel-art rendering and integer scaling. Project-wide viewport/stretch settings are configuration authority, not per-UI preferences.

UI scripts/scenes may adapt layout, but they must not change `project.godot` display configuration as a local fix.

Experimental UI should be isolated under the approved sandbox after agent activation:

`res://scenes/test_scenes/ui_sandbox/`

Production UI remains under established `res://scenes/ui/` conventions.

## Design Pillar: Variable Progression

The game should avoid becoming a fixed spreadsheet where every playthrough follows one solved route.

Use controlled variation:

```text
Player decision
-> System state check
-> Controlled random variation
-> Readable result
```

Randomness should create strategic variation, not remove player agency.

Possible later variation layers include migrant timing, applicant availability/quality, resident traits, opportunity timing, and limited production/needs variation.

Do not introduce broad randomness before the deterministic prototype loop is stable and readable.

## AI NPC / Quest Integration Architecture

AI-powered unique NPCs are a long-term layer. They must not replace authoritative game systems.

Responsibility split:

```text
AI NPC = character voice, personality, intent, contextual dialogue
Quest System = rules, validation, objective tracking, reward approval
Game State = inventory, city state, trust, progress, economy authority
```

AI may suggest quest intent, but the game must validate item, quantity, timing, requirements, reward and completion.

AI must not directly create money/items, modify authoritative inventory, mark quests complete, distribute rewards, change trust/progression flags, or override economy rules.

Recommended order:
1. Stable dialogue.
2. Stable inventory/resource rules.
3. Normal quest system.
4. Trust/relationship state.
5. Quest templates and reward ranges.
6. AI dialogue layer for selected unique NPCs.
7. AI-assisted quest offering behind validation.

## Existing Core Systems to Preserve

Implementation agents should inspect and preserve the intent of existing systems including:
- ItemDatabase
- Inventory
- WorkShopStorage
- WorkManager
- ProcessManager
- TimeComponentManager
- CitizenManager
- CitizenGenerator
- ImmigrationManager
- CitizenNeedsManager
- WorkerDatabase
- Applicant/Job Board flow
- PlayerRuntimeState
- SceneTransition
- WorkStateRuntime
- gameplay UI scenes

Do not add another manager simply because a feature could be implemented that way. First determine which existing system already owns the responsibility.

## Main architecture risks

### Duplicate authority
Avoid multiple places owning the same state, especially:
- citizen/employment state
- worker assignment
- workshop storage/output
- world time
- player runtime state

### UI owning gameplay
UI should display state and request actions. It should not become the hidden owner of economy, employment, production, condition, or progression rules.

### Global-manager sprawl
The project already has many autoloads. Adding another autoload is a high-impact architecture change and requires explicit justification/approval.

### Save schema churn
Do not lock persistence around unstable node structures before the daily loop is stable.

### AI becoming game authority
Future AI NPC systems must remain expressive layers over deterministic validated game rules.

## Code Change Policy

Prefer small isolated changes over broad rewrites.

When implementation evidence shows this document is stale, update the relevant snapshot/boundary; do not silently rewrite game design while doing so.