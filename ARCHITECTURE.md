# ARCHITECTURE — Time is Precious

Last updated: 2026-05-16

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
