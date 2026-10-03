# Workshop clearing before construction

User-approved scope (2026-09-27): initial hand prompt; no materials; choose player or one
worker; three hours; hammer/build requirements only after clearing. Existing authored
scene layout, terrain artwork, worker cards and assignment UI are preserved. The existing
glove/hand sprite supplies the native 16x16 hand prompt.

Implementation uses the existing runtime construction node. Worker clearing reserves and
releases the assignee, progresses on world time and leaves the player mobile. Player work
uses a short blackout and the normal minute signals (no duplicate needs charges), blocks
other activity during the skip, and stops if condition/range/scene access becomes invalid.
Interrupted player work retains completed minutes. No material or item output is involved.
The clearing selector reuses the authored worker assignment panel with one slot and adds
an exclusive Assign Player control. Construction keeps its existing multi-worker rules.

Verification: WorkshopClearingTest covers missing/multiple assignees, no early building,
worker reservation and exact 180-minute duration, no material mutation, manual interruption,
no unattended progress, actual E/manual flow, controls restored and map reload retention.
WorkshopConstructionUITest exercises one-slot worker clearing through the shared assignment
UI, then the existing multi-worker construction flow. Construction transaction, access,
main-map production and initial-workshop integration regressions are also run. Hand,
clearing menu and subsequent hammer captures were inspected. Existing ObjectDB shutdown
resource diagnostics persist. No commit or merge performed.
