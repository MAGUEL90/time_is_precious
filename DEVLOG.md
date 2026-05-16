# DEVLOG — Time is Precious

Last updated: 2026-05-17

## Project Identity
**Time is Precious** is a 2D top-down management RPG with a Mesopotamian theme, built in Godot Engine 4 / 4.5.

Core pillars:
- Time as the main strategic pressure.
- Resource management.
- Worker / NPC delegation.
- Production chains.
- City and player home progression.

## Current Development Focus
The current focus is not adding big features. The focus is stabilizing the playable core loop.

Priority order:
1. Resource gathering.
2. Resource storage.
3. Work / process execution.
4. NPC delegation.
5. Production output.
6. Basic progression impact.
7. Minimum playable prototype.

## Current Design Issue: Worker vs Resident
A key issue has been identified: the code/design must not treat `worker` and `resident` as the same concept.

Important decision:
- Food consumption should depend on **resident/citizen status**.
- Food consumption should not depend on whether an NPC has been hired as a worker.

Correct flow:
```text
Migrant arrives
↓
Player accepts or rejects
↓
Accepted migrant becomes Resident / Citizen
↓
Resident starts consuming city stock
↓
Eligible resident can appear on Job Board
↓
Player hires applicant
↓
Hired worker can be assigned to work/process
```

## Working Design Decision
Separate NPC state into two layers:

### Population Status
Examples:
- `migrant`
- `resident`
- `rejected`
- `left_city`

### Employment Status
Examples:
- `unemployed`
- `applicant`
- `hired`
- `assigned`

This avoids the mistake of using only one boolean such as `is_hired` for all NPC logic.

## Important Rule for Codex
Do not change scripts automatically without clear explanation.

When code changes are proposed, show them as diff:
```diff
- old code
+ new code
```

Do not make food consumption depend on `is_hired`.

## Development Log

### 2026-05-17 — Basic Applicant Hiring Flow

What changed:
- Added worker-side hiring helpers for applicant eligibility and status transition.
- Updated Job Board interaction so the first available applicant can be hired for the MVP flow.

Why it changed:
- The prototype needs a clear transition from `resident + applicant` to `hired worker`.
- Job Board should prove the population/employment split without requiring the full future hiring UI yet.

Files touched:
- `resources/worker_data/worker_data.gd`
- `scenes/job_board/job_board.gd`

Test result:
- Manual gameplay test passed: first Job Board interaction hired `Laborer`; second interaction showed no applicant offers.
- Worker appeared in Worker Hub after being hired.

Known risks:
- Job Board currently hires the first applicant automatically.
- There is no applicant selection UI yet.
- Hiring has no wage payment or contract duration logic yet.

Next recommended task:
- Add a small applicant selection/confirm flow before hiring, or keep moving toward assigned-worker flow if MVP speed is more important.
