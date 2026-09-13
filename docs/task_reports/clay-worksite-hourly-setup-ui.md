# Worksite setup and confirmation UI

2026-09-08 — PASSED — NEEDS HUMAN REVIEW.
Scope: existing sandbox inspector and dependent fixture tests. Existing local edits preserved.

- Initial overview shows How long will you work? above Hourly / Daily. Empty worker/status
  feedback and Start remain hidden until a setup exists.
- Hourly opens a compact picker using the existing ActionChoicePanel atlas region
  (ui_base_1/base_1_24.06.2026.png, 116,7,52,40). No new image assets.
- Picker hides the site title, mode buttons, question, conditions and tool/status feedback.
  It contains 3h/6h/9h, Back and Next. Back/Escape/E cancel the draft and restore the
  previous confirmed mode/duration without closing the modal or advancing time.
- Next returns to the main worksite panel; it does not start work. The main panel shows
  Energy, Satiety, Tool Effect and any blocking status for Hourly, plus Start Work.
- Daily keeps the existing NPC assignment and main-panel worker feedback. Returning with
  no workers restores the clean initial overview. Active assignments retain their feedback.

Changed: clay_worksite_inspector.gd/.tscn; inspection, gathering and Nightmare test scripts;
this report. No gathering rates, stock, scheduling, assets or global gameplay code changed.

Validation: inspection regression passed graphically at 1200x675; initial, picker and final
screenshots inspected. Headless checks cover draft cancellation, Next without execution,
confirmed 3/6/9-hour previews, focus/pause, inventory blocking and cleanup. Daily, gathering,
Nightmare escape/timeout and nearby workshop UI regressions passed. git diff --check clean.
Existing certificate-store and shutdown resource warnings persist. No commit/push/merge.
