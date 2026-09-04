# TIME IS PRECIOUS — QA & TEST GATES

Status: TEMPLATE — NOT ACTIVE

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

## UI gate
For UI work verify open/close behavior, input/focus, text clipping at tested resolution, empty/long-value states, dynamic refresh, signal duplication on reopen, and that opening UI does not alter gameplay data. Sandbox prototypes must not replace production gameplay scenes.

Target resolutions/devices: `TBD`

## Gameplay-system gate
Check happy path, failure/empty path, repeated use, scene reload behavior, relevant day/time transitions, inventory/resource edge cases, cancellation paths where relevant, and that no economy/balance values changed outside approved scope.

## Save/load gate
Verify save, load, repeated save/load, behavior for missing/corrupt/old data, save compatibility or explicitly documented incompatibility, and schema-change documentation.

## Regression radius
Identify and test the nearest dependent systems, not just the edited function.

## Evidence
Record what was tested, how, result, what could not be tested, and any new warnings/errors. Untested behavior must not be marked passed.

## Status vocabulary
- `FAILED`
- `PARTIAL`
- `PASSED — NEEDS HUMAN REVIEW`
- `APPROVED — MERGE` (human only)
