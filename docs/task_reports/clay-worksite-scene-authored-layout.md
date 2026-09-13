# Scene-authored worksite layout

2026-09-09. Scope: adapt inspector code to the user's latest scene edits.

Preserved the scene file unchanged: Who will work?, Player/Worker captions, compact
108x60 picker base, the added question label, centered controls, smaller buttons, and
removed picker spacer. Internal Hourly/Daily routing still connects the appropriate buttons.

Removed hardcoded 240x120 / 240x150 / 240x165 runtime panel sizes. The inspector now
captures each panel's authored minimum and fits its current content with existing margins.
The authored size remains the lower bound; the panel grows only if labels/buttons require
more space. Deferred fitting responds to minimum-size changes and coalesces queued updates.
No caption text, palette, font size, gameplay rule or scene-authored layout was overwritten.

Graphical inspection regression passed at 1200x675; initial, compact picker and confirmation
captures reviewed. Added checks for unchanged button captions and content-based sizing/footer
fit. An initial exact-width assertion was corrected because the contract deliberately allows
expansion for content. Existing certificate-store/shutdown warnings remain.

Files changed in this step: clay_worksite_inspector.gd, test_scene_clay_worksite_inspection.gd,
and this report. User .tscn changes remain untouched. No commit/push/merge.
