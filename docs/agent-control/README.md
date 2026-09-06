# Time is Precious — Agent Control Pack

Status: ACTIVE

This folder contains the active governance rules for coding-agent work in Time is Precious.

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
- First pilot sandbox: `res://scenes/test_scenes/ui_sandbox/`.

## Activation record
- Human-tested baseline commit: `fcb5dc24a74c3b5b2c23af9ad10676752e7532a1`.
- Human baseline smoke test: `PASSED`.
- Permanent known-good tag: `agent-baseline-2026-09-05`.
- Tag target verification: `PASSED`.
- Source-of-truth drift found during audit was reconciled before activation.
- Protected paths, branch taxonomy, QA baseline and sandbox path were reviewed before activation.

## Default permission
All agents begin at:
`LEVEL 1 — ISOLATED / LOW-RISK`

Higher-risk work requires task-specific authorization according to the control pack.

## First pilot
Create an isolated Time is Precious UI sandbox under:
`res://scenes/test_scenes/ui_sandbox/`

The pilot may build reusable UI components, but must not integrate them into production gameplay scenes during the same first-run task.

## Required entrypoint
Agents must start with:
`00 - AGENT - READ ME FIRST.md`

The Game Director retains final design and merge authority.
