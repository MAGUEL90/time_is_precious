# Worksite removal confirmation

Date: 2026-09-10
Status: PASSED — NEEDS HUMAN REVIEW
Risk: LEVEL 1 — isolated fixture UI.
Branch: feature/process-workshop/clay-worksites
Baseline: 0f971ab330b83e2c8502ef943ddd04e94019565a
Starting tree: dirty; existing local scene, script, documentation and asset changes preserved.

## Approved behavior

Remove opens the existing confirm-discard panel with Yes/No and the message:
“Stop this worker now? Completed clay will be kept. Unfinished progress will be lost.”
No or Escape returns to Worker Progress without releasing an assignment. Yes invokes the existing immediate withdrawal once. Closing the inspector clears pending confirmation. Initial focus is No; keyboard tab stays between the two choices.

Completed output settlement and fractional-progress removal remain owned by the existing Daily scheduler. No rate, stock, shift, worker identity or next-day removal changes.

## Files

- Modified: clay_worksite_inspector.gd (isolated UI), test_scene_clay_worksite_team.gd (confirmation regression coverage).
- Created: this report. No deletion, rename, protected-system or settings changes.

## Validation

- Graphical ClayWorksiteDailyTest at 1200x675: PASSED, including confirmation opening without mutation, No, Escape, Yes, repeated use and last-worker removal.
- Confirmation screenshot inspected: message and both buttons fit.
- Main project headless launch: exit 0.
- git diff --check: passed. Targeted changes reviewed; unrelated local work preserved.
- Existing certificate-store and ObjectDB/15-resource exit diagnostics remain. No new blocking errors observed.
- Production-world integration, persistence and Android testing are outside scope.
