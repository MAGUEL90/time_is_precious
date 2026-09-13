# Worker Daily starts next calendar day

Date: 2026-09-09. Scope: authorized scene-local scheduling and UI feedback.
Supersedes the immediate-start Daily rule in clay-worksite-worker-activity.md.

- Every newly confirmed worker starts at `(current_day + 1), 07:00`, including confirmations at 00:01. Player Hourly remains immediate.
- Start reserves the worker immediately, with Resting activity until the scheduled start. No time skip and no production or active site capacity consumed before eligibility.
- Start timestamps are stored per worker; adding a new member does not restart an existing member. Withdrawal/reassignment schedules a new next-day start.
- Worker confirmation displays `Start work: Day N` below shift hours, derived from the preview provider. Confirmed dates remain stable on reopening after midnight. Mixed start dates are listed when adding a new member to an existing team.
- Existing recurrence, finite stock, output routing and 07:00-15:00 shifts continue after the first eligible day.
- Walking from home, travel duration, departure at 06:00 and arrival animation are future work; no invented travel rules were implemented.

Changed: clay_worksite_daily.gd, test_scene_clay_worksite.gd, test_scene_clay_worksite_team.gd. Existing local edits preserved.

Validation: Daily regression PASSED at 1200x675; screenshot inspected for label fit. Tests cover no same-day production, 00:01 scheduling, next-day 06:59/07:00 boundary, stable confirmed date, and delayed new member alongside an already active member. Inspection and Gathering regressions PASSED. Main launch exit 0; git diff --check clean. Existing certificate store and exit resource diagnostics remain; no new blocking errors observed.
