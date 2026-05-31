# ARCHITECTURE — Time is Precious

Last updated: 2026-06-01

## Purpose
This document is the architectural source of truth for **Time is Precious**.

The goal is to keep systems clean, scalable, and aligned with the game vision.

## Core Game Identity
Time is Precious is a 2D top-down management RPG focused on:
- Time pressure.
- Resource management.
- Work delegation.
- Production chains.
- City growth.
- Player home / settlement progression.
- Variable progression between players.

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

Good randomness examples:
- Random migrant count within a controlled range when city prosperity is good.
- Different applicant quality or traits from the resident pool.
- Varying production opportunities or small efficiency modifiers.
- Different timing for city events.
- Slight variation in needs pressure or resource opportunity.

Bad randomness examples:
- Fully random outcomes that ignore player decisions.
- Sudden punishment with no warning or counterplay.
- Random systems that make planning impossible.
- Hidden dice rolls that feel unfair.

The game should feel alive, not arbitrary.

## Current Priority
Do not expand into large systems too early.

Stabilize this core loop first:
```text
Gather resource
↓
Store resource
↓
Start work/process
↓
Assign worker/NPC
↓
Produce output
↓
Use output for progression
```

## Important Architecture Rule
Do not mix **population logic** with **employment logic**.

An NPC can be a resident without being a worker.
An NPC can be hired but not assigned.
An NPC consumes food because they are a resident, not because they are hired.

## NPC State Model
NPC state should be split into at least two conceptual layers.

### 1. Population / Citizenship Layer
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

### 2. Employment / Worker Layer
This controls whether an NPC can be assigned to work.

Possible statuses:
- `unemployed`
- `applicant`
- `hired`
- `assigned`

Rules:
- `unemployed`: resident without job.
- `applicant`: resident eligible and visible on Job Board.
- `hired`: selected by player and added to worker pool.
- `assigned`: actively assigned to a workstation, task, or process.

## Job Board Concept
For the current prototype, Job Board applicants should come from accepted residents.

Recommended flow:
```text
Resident
↓
Needs are good enough
↓
Eligible for work
↓
Appears on Job Board
↓
Player hires
↓
Added to Worker Hub / worker pool
```

Do not spawn unrelated external applicants for now unless the design intentionally changes later.

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
↓
System state check
↓
Controlled random variation
↓
Result with readable feedback
```

Example:
```text
If city prosperity is above threshold:
    migrant_count = random value within a small range
    migrant quality/traits may vary
    player chooses accept/reject
```

The player should still understand why something happened.

Do not hardcode every outcome into fixed numbers unless needed for early prototype stability.
Use tunable ranges where appropriate.

## Existing/Expected Core Systems
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

When proposing code changes, use diff format:
```diff
- old code
+ new code
```

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

Use explicit state separation instead.

Another major risk is making the game too deterministic.

If every system uses fixed numbers, fixed timing, fixed applicants, and fixed outcomes, the gameplay will become too easy to solve. The design should preserve controlled variation so each player's city develops differently.
