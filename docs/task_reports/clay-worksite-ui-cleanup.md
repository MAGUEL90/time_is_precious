# Worksite UI cleanup

2026-09-09 — PASSED — NEEDS HUMAN REVIEW.
Scope: local worksite inspector, Daily assignment adapter, and dependent tests.
Existing local edits, fonts, assets, and unrelated gameplay code preserved.

Removed the unused OutputLabel and AddWorkerButton nodes, references, signal connection,
hidden-output formatting, obsolete TBD text, and overwritten bag-full fallback. Removed
the Daily adapter's unreachable synthetic Player card and Player-only info/tooltip branches.

The scene now stores its actual initial appearance: question above Hourly/Daily, no
confirmation/status/Start feedback until configured. Confirmation is a named node group.
HourlySetup is a separate sibling panel with its existing simple atlas texture, duration
buttons, Back and dedicated Next. Start Work is no longer reused as Next. Runtime texture,
margin switching and child reordering were removed; those properties/order live in the scene.
Page visibility still changes at runtime, as required for navigation, but removed controls
no longer exist and the editor defaults do not depend on _ready hiding them.

Files: clay_worksite_inspector.gd/.tscn; clay_worksite_assignment_ui.gd; inspection, team,
gathering and Nightmare regression scripts; this report. No assets or gameplay rules changed.

Validation: graphical inspection at 1200x675 passed; initial/picker/confirmation captures
reviewed. The regression checks saved scene visibility before _ready, obsolete-node absence,
Back/Next, cancellation and unchanged condition previews. Daily, gathering/overflow,
Nightmare round trips and nearby workshop UI tests passed. Main project launch smoke and
git diff --check passed. Existing certificate-store/shutdown resource warnings persist.
No commit, push or merge.
