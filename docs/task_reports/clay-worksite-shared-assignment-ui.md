# Shared Assign Workers presentation

2026-09-08 — PASSED — NEEDS HUMAN REVIEW.

Add Worker now instantiates the existing workshop_worker_assignment_ui.tscn rather than
showing a separate list in the work form. A fixture-only subclass reuses its actual slot,
portrait, plus, lock, card/info builders, Back/Next controls and theme. Two slots are active;
the third is locked. Player is represented by a local card, never inserted into WorkerDatabase.
Right-click removes an occupied slot, matching the existing workshop interaction.

The adapter delegates selection to the existing worksite session. Back/Next returns to the
work form without releasing its pause; X closes the whole worksite modal. Escape/E backs out
of info/selection/overview. No assignment lifecycle or production workshop implementation changed.

Team output estimates are still deliberately unavailable for NPC/mixed teams; this task
changes presentation, not throughput, NPC output ownership/storage, wages or background work.
Player-only estimates and production remain operational.

Files: new clay_worksite_assignment_ui.gd; inspector script/scene replace the old roster;
team and inspection tests updated to use the shared slots.
Graphical team test passed at 1200x675 and screenshot reviewed. Inspection, gathering and
WorkshopUIRegressionTest passed. Existing certificate/shutdown warnings remain.
git diff --check clean. Existing local fonts/layout edits preserved; no commit/push/merge.
