# Worksite setup guards and Nightmare debug

2026-09-09 — PASSED — NEEDS HUMAN REVIEW.

Removed hover tooltips from the local worker-assignment adapter, including generated
cards/slots. Back with at least one selected worker now reuses ConfirmDiscardPanel with
Yes/No. No keeps the selection; Yes clears the unstarted draft and returns to overview.
The modal blocks pointer interaction behind it and confines keyboard Tab focus to Yes/No.

Confirmed Player setup disables Worker; a nonempty Worker setup disables Player. Guards
also reject programmatic mode changes while disabled. Closing the main menu clears the
Player mode/duration and unstarted worker selection. Existing started Daily assignments
continue until withdrawn, as in the approved recurring-job contract; reopening derives
their worker feedback from the active job. Close does not cancel a running Daily job.

The F6 fixture now enables prepare_nightmare_test and disables the prior overflow preset.
On direct launch only, Player is placed at Clay Site A with fatigue 0.89, hunger 0, focus 1.
This leaves approximately 20 game minutes before fatigue reaches the existing 0.90 threshold.
Opening E pauses world time. Choose Player, 3h, Next, Start Work to trigger collapse during
the time skip and follow the existing Nightmare entry/return. Production condition tuning
and the normal game entrypoint remain unchanged.

Tests: assignment Yes/No, tooltip removal, mode locks, Close reset and reopen, Daily
continuation, inspection, gathering/overflow, preset initialization and full Nightmare
escape/timeout passed. Assignment modal checked graphically at 1200x675. Nearby workshop UI
regression passed. Existing certificate-store/shutdown warnings remain; diff check clean.

Changed: local assignment adapter, inspector script, fixture script/.tscn, team/inspection/
gathering test scripts, and this report. Existing UI size/label edits preserved. No commit,
push, merge, or production gameplay file changes.
