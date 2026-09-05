# Time is Precious — Agent Control Pack

Status: TEMPLATE — NOT ACTIVE

This folder stages governance rules for future coding-agent use. It is intentionally inactive for now.

## Verified repository facts

- Design source of truth: `docs/game-concept.md`.
- Progress / priority source of truth: `ROADMAP.md`.
- Architecture source of truth: `ARCHITECTURE.md`.
- Merged implementation history: `DEVLOG.md`.
- Technical domain / branch map: `docs/root-branch-map.md`.
- Engine family: Godot `4.5.x`.
- Protected release branch: `main`.
- Current logical viewport: `400 x 225`.
- Current development window override: `1200 x 675`.
- First pilot sandbox after activation: `res://scenes/test_scenes/ui_sandbox/`.

## Remaining activation gates

1. Synchronize stale progress/architecture documentation with merged implementation.
2. Review this activation-preparation branch and merge only after human approval.
3. Pull the chosen `main` commit locally.
4. Run the baseline human smoke test from `05 - QA & TEST GATES.md`.
5. Confirm the exact tested commit hash.
6. Create a permanent known-good tag/checkpoint on that exact commit.
7. Replace `PENDING HUMAN RUNTIME VALIDATION` with the actual approved tag.
8. Game Director explicitly approves activation.
9. In a separate activation change, mark the control files `ACTIVE`.
10. Run the first pilot at `LEVEL 1 — ISOLATED / LOW-RISK`.

Suggested baseline tag after successful validation:

`agent-baseline-2026-09-05`

This is only a suggested name until the Game Director confirms the tested commit.

## First pilot

Create an isolated Time is Precious UI sandbox under:

`res://scenes/test_scenes/ui_sandbox/`

The pilot may build reusable UI components, but must not integrate them into production gameplay scenes during the same first-run task.

## Important

Do not mark this pack ACTIVE merely because repository-specific `TBD` values were filled. Activation also requires a human-tested baseline and explicit Game Director approval.