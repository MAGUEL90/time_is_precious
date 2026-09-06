# TIME IS PRECIOUS — QA & TEST GATES

Status: ACTIVE

Purpose: code written is not the same as a feature proven to work.

## Universal gate
For every implementation task, verify as applicable:
- Project parses.
- Game/project launches.
- Target scene loads.
- No new blocking debugger errors exist.
- Requested behavior works.
- Nearby existing behavior still works.
- No unexpected files changed.
- Diff was reviewed.
- Limitations and untested areas are reported.

## Baseline test environment
Current repository direction:
- Godot `4.5.x`.
- GL Compatibility renderer.
- Logical viewport: `400 x 225`.
- Current development window override: `1200 x 675`.
- Presentation target: 16:9, PC first.
- Android landscape compatibility is a target, but Android-specific validation is required before claiming mobile readiness.

For ordinary desktop UI implementation, test at minimum in the current development window (`1200 x 675`) using the project's normal logical viewport and integer scaling.

When a change affects scaling, anchors, layout responsiveness, touch/input, export settings or platform-specific behavior, also validate the relevant target presentation(s) explicitly. Do not claim Android compatibility from desktop testing alone.

## UI gate
For UI work verify open/close behavior, input/focus behavior, text clipping, empty state, long-value state, dynamic refresh, signal duplication after repeated open/close, no unintended gameplay data mutation merely from opening UI, and correct rendering under the current logical viewport/integer scale setup.

Sandbox prototypes must not replace production gameplay scenes.
First pilot sandbox:
`res://scenes/test_scenes/ui_sandbox/`

## Gameplay-system gate
Check happy path, failure/empty path, repeated use, scene reload behavior, relevant day/time transitions, inventory/resource edge cases, cancellation paths where relevant, and that no economy/balance values changed outside approved scope.

For population/worker changes, run or extend the existing population/employment integration coverage when relevant.
For work/production state changes, run or extend the existing work-state smoke coverage when relevant.

## Save/load gate
Real save/load is currently pending. Once persistence exists, verify save, load, repeated save/load, behavior for missing/corrupt/old data, save compatibility or explicitly documented incompatibility, and schema-change documentation.
Until then, an agent must not report save/load compatibility as tested unless the task actually implements and validates it.

## Regression radius
Identify and test the nearest dependent systems, not just the edited function.

Examples:
- Worker UI change → hiring/assignment state display and reopen behavior.
- Workshop change → storage, assignment, job start, time advancement and claimable output.
- Player condition change → sleep, collapse/nightmare and scene transitions.
- Display change → inventory, HUD, dialogue, workshop and player-home presentation.

## Evidence
Record what was tested, how, result, what could not be tested, and any new warnings/errors. Untested behavior must not be marked passed.

## Activation baseline validation
Date: `2026-09-05`
Tested commit: `fcb5dc24a74c3b5b2c23af9ad10676752e7532a1`
Permanent checkpoint tag: `agent-baseline-2026-09-05`
Game Director result: `PASSED`
Tag verification: `PASSED`

The Game Director reported that the game was run locally and worked correctly after PR #95 was merged. The permanent tag was later verified to point to that exact tested commit. This satisfies the activation baseline gate.

This is a baseline smoke test, not a claim that every game feature is complete.

## Status vocabulary
- `FAILED`
- `PARTIAL`
- `PASSED — NEEDS HUMAN REVIEW`
- `APPROVED — MERGE` (human only)
