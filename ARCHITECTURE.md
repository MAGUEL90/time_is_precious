# ARCHITECTURE - Time is Precious

Last updated: 2026-06-09

## Purpose
This document is the architectural source of truth for **Time is Precious**.

The goal is to keep systems clean, scalable, and aligned with the game vision while the project moves toward a small playable prototype.

## Core Game Identity
Time is Precious is a 2D top-down management RPG focused on:
- Time pressure.
- Resource management.
- Work delegation.
- Production chains.
- City growth.
- Player home / settlement progression.
- Variable progression between players.

## Current Priority
Do not expand into large systems too early.

Stabilize this core loop first:

```text
Gather resource
-> Store resource
-> Assign worker
-> Start work/job
-> Produce output
-> Claim or continue processing output
-> Use output for progression
```

Current local prototype status:
- Inventory-to-workshop transfer is player-facing.
- Workshop storage supports deposit and withdraw.
- Workshop can assign a prototype worker.
- Workshop can start the mudbrick job from stored materials.
- NPC job output enters `WorkShopStorage.claimable_outputs`.
- Popup feedback shows item gain/loss for deposit and withdraw.

## Design Pillar: Variable Progression
Time is Precious should not be easily predictable from one playthrough to another.

The game should avoid becoming a fixed spreadsheet where every player follows the same optimal path, uses the same exact numbers, and reaches the same progression pattern.

The intended experience:
- Player A and Player B may develop differently.
- City growth should have controlled randomness.
- Migrant arrival, applicant availability, needs pressure, and opportunity timing can vary.
- The player should adapt to circumstances instead of memorizing one perfect route.
- Randomness should create strategic variation, not chaos.

Important rule:

```text
Use controlled randomness to create variation.
Do not use randomness to remove player agency.
```

## Important Architecture Rule
Do not mix **population logic** with **employment logic**.

An NPC can be a resident without being a worker.
An NPC can be hired but not assigned.
An NPC consumes food because they are a resident, not because they are hired.

## NPC State Model
NPC state should be split into at least two conceptual layers.

### Population / Citizenship Layer
This controls whether an NPC belongs to the city and consumes city stock.

Possible statuses:
- `migrant`
- `resident`
- `rejected`
- `left_city`

Rules:
- `migrant`: has arrived but has not yet been accepted by the player.
- `resident`: accepted into the city and counts as population.
- `resident` starts consuming food / city stock.
- `rejected` or `left_city` should not consume city stock.

### Employment / Worker Layer
This controls whether an NPC can be assigned to work.

Possible statuses:
- `unemployed`
- `applicant`
- `hired`
- `assigned`
- `working`

Rules:
- `unemployed`: resident without job.
- `applicant`: resident eligible and visible on Job Board.
- `hired`: selected by player and added to worker pool.
- `assigned`: attached to a workstation/site, but not necessarily working right now.
- `working`: currently executing a job/order.

## Current Implementation Snapshot
This architecture reflects the planning, asset, worker visual, variable progression, citizen/immigration, and workshop core-loop milestones up to the current local work.

Implemented pieces:
- Documentation defines the project direction, asset workflow, palette rules, roadmap priority, and resolution/platform direction.
- Job Board has a first applicant-offer direction, but the full resident-to-applicant conversion still needs future work.
- Modular worker/player/citizen visuals use layered body, head, clothes, hands, hair, and accessories.
- `CitizenData` stores runtime citizen identity, basic need flags, satisfaction/reliability values, status, profession, and optional visual profile.
- `VisualProfile` stores presentation data for modular character appearance.
- `CitizenManager` keeps the runtime citizen registry and emits `citizen_added`.
- `CitizenGenerator` creates randomized prototype citizens.
- `ImmigrationManager` evaluates immigration chance, keeps pending immigrant batches, and accepts or rejects the full batch.
- `CitySpawner` and `CitizenActor` turn accepted citizen data into visible city actors.
- `Inventory` and `WorkShopStorage` both support item capacity/weight checks.
- `ItemTransferUI` supports reusable quantity-based transfer.
- `WorkshopMenuUI` opens player-facing workshop actions.
- `WorkshopStorageMenuUI` separates deposit/withdraw from the main workshop menu.
- `WorkShop` can deposit items, withdraw stored items, assign a prototype worker, and start the mudbrick job from workshop storage.
- `WorkManager` can consume source storage inputs and send NPC output to claimable workshop escrow.

Current rules:
- Population/citizen status and employment/worker status must remain separate.
- Immigration approval is batch-based for now: accept all pending immigrants or reject all pending immigrants.
- Accepted immigrants become citizens and are added to the runtime registry.
- Visual data should stay separate from gameplay rules unless a future trait system intentionally connects them.
- Save/load should eventually persist data resources or serialized citizen data, not spawned scene nodes.
- Workshop stored items are separate from `claimable_outputs`.
- Withdraw should only pull from `WorkShopStorage.items`, not from claimable escrow.
- NPC-produced output should stay in `claimable_outputs` until the player claims or routes it forward.

Current boundaries:
- Applicant/job-board conversion from citizen to worker is not finished.
- Worker assignment is still a prototype path and not yet connected cleanly to accepted citizens.
- Workshop job selection is not final; current flow starts mudbrick through the prototype assign/start action.
- Long-term citizen and workshop persistence are not finished.
- Needs display/counting exists, but deeper daily consumption/balancing still needs future work.
- Drying process integration still needs player-facing verification after wet mudbrick is claimable.

## Job Board Concept
For the current prototype, Job Board applicants should come from accepted residents.

Recommended flow:

```text
Resident
-> Needs are good enough
-> Eligible for work
-> Appears on Job Board
-> Player hires
-> Added to Worker Hub / worker pool
```

Do not spawn unrelated external applicants for now unless the design intentionally changes later.

## Workshop Concept
Workshop actions should stay focused on a coherent production family.

For the current workshop, the production family is earth/clay/construction material work:
- Mudbrick making.
- Clay mix refinement.
- Mudbrick reinforcement.
- Cracked mudbrick repair.
- Drying preparation.

Avoid making one workshop handle unrelated work such as clothing, cooking, fishing, or broad general crafting.

Recommended workshop flow:

```text
Manage Storage
-> Deposit raw materials
-> Assign worker
-> Choose/start relevant job
-> Job consumes workshop storage
-> NPC output enters claimable escrow
-> Player claims output or continues processing
```

## Consumption Rule
Food and need consumption should be based on population status.

Correct:

```text
if population_status == resident:
    consume_city_stock()
```

Incorrect:

```text
if is_hired:
    consume_city_stock()
```

## Randomness / System Variation Rule
Randomness should be implemented as a support layer over clear systems.

Recommended structure:

```text
Player decision
-> System state check
-> Controlled random variation
-> Result with readable feedback
```

Example:

```text
If city prosperity is above threshold:
    migrant_count = random value within a small range
    migrant quality/traits may vary
    player chooses accept/reject
```

The player should still understand why something happened.

Do not hardcode every outcome into fixed numbers unless needed for early prototype stability. Use tunable ranges where appropriate.

## Existing / Expected Core Systems
Codex should analyze and preserve the intent of these systems:
- WorkManager
- ProcessManager
- WorkshopStorage
- Resource / Item system
- NPC delegation / contract system
- Worker Hub
- Job Board
- Basic UI
- Save/load later, after core loop is stable

## Code Change Policy
Do not directly rewrite systems without explaining why.

Prefer small, isolated changes over large rewrites.

## Current Architecture Risk
The biggest current risk is coupling too many responsibilities into one NPC/worker flag.

Avoid relying only on:

```gdscript
is_hired = true
```

A single boolean cannot represent:
- outsider/migrant
- accepted resident
- unemployed citizen
- job applicant
- hired but idle worker
- assigned active worker
- currently working worker

Use explicit state separation instead.

Another major risk is making the game too deterministic.

If every system uses fixed numbers, fixed timing, fixed applicants, and fixed outcomes, the gameplay will become too easy to solve. The design should preserve controlled variation so each player's city develops differently.
