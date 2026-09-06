# TIME IS PRECIOUS — AGENT READ ME FIRST

Status: ACTIVE

Purpose: mandatory entrypoint for any AI/coding agent working on this repository.

## Authority
1. Latest explicit instruction from the Game Director.
2. Approved game-design/canon source of truth.
3. This control pack.
4. Existing approved project architecture and conventions.
5. Current implementation.
6. Agent assumptions — never authoritative.

## Mandatory reading order
1. `00 - AGENT - READ ME FIRST.md`
2. `01 - PROJECT CONTROL.md`
3. `02 - GAMEPLAY AUTHORITY MAP.md`
4. `03 - TECHNICAL RULES.md`
5. `04 - GIT & CHANGE CONTROL.md`
6. `05 - QA & TEST GATES.md`
7. Relevant latest entries in `06 - AGENT RUN LOG.md`
8. Task-specific source files and design documents.

## Activation baseline
- Human-tested commit: `fcb5dc24a74c3b5b2c23af9ad10676752e7532a1`
- Permanent checkpoint tag: `agent-baseline-2026-09-05`
- Human baseline smoke test: `PASSED`

## Hard guards
The agent must not:
- Work directly on `main` or another protected release branch.
- Merge its own work into `main`.
- Force-push or rewrite Git history.
- Overwrite unrelated uncommitted human work.
- Delete, move, or rename existing scenes, scripts, assets, resources, save data, or folders unless explicitly required.
- Perform a broad refactor while solving a narrow task.
- Change story, lore, character identity, quests, core mechanics, economy rules, balancing, progression, win/lose conditions, or the Time ↔ Shekel design without explicit human approval.
- Add/remove/upgrade plugins, addons, autoloads, engine settings, render settings, export settings, or project-wide dependencies without approval.
- Replace a working system merely because it prefers another architecture.
- Invent missing facts; unknowns remain `TBD`, `N/A`, or `unverified`.
- Declare a task complete merely because code was written.
- Hide failed tests, regressions, assumptions, or unresolved risks.

## Default permission
`LEVEL 1 — ISOLATED / LOW-RISK`

Risk levels:
- `LEVEL 0` Read only.
- `LEVEL 1` Isolated/low-risk.
- `LEVEL 2` Limited integration.
- `LEVEL 3` System change.
- `LEVEL 4` Protected game design.

If risk is uncertain, use the higher level.

## Completion rule
A task is not `PASSED` until requested behavior exists, the project still launches, relevant scenes load, no new blocking errors exist, target behavior is tested, nearby regression checks pass, `git diff` is reviewed, changed files are listed, and remaining risks are reported.

Only the human Game Director can mark a change `APPROVED — MERGE`.

## First principle
If a task determines why Time is Precious is fun, the human stays involved.
If a task mainly implements or presents already-approved behavior, the agent may do more of the work within these controls.
