# Clay worksite Add Worker selection

Superseded for execution/default selection by [team production](clay-worksite-team-production.md)
on 2026-09-08. The selection-only limitations below describe the earlier checkpoint.

2026-09-07 — PASSED — NEEDS HUMAN REVIEW (team-selection checkpoint).
Branch: feature/process-workshop/clay-worksites.
Scope: existing isolated test fixture and its sandbox UI; local font edits preserved.

Add Worker appears left of Start Work. It opens a scrolling card list with Player / You
and existing WorkerDatabase entries showing their resolved names and professions.
Selection is immediate, allows removal, persists per site and counts Player toward the
Small Worksite capacity of two. Back returns to the unchanged duration selection; X closes
the modal, Escape/E returns from the list before closing the main form.

Cards and session validation reject adding a third participant, missing workers, busy
workers and linked citizens unavailable for assignment. Selected workers can be removed.
This is a local team choice, not a hire/assignment mutation or reservation in WorkerDatabase.
Other profession cards remain selectable for reviewing team UI; gathering profession
eligibility is not introduced as a new gameplay rule in this step.

Player-only execution remains enabled. Empty teams and teams containing NPCs are blocked
in both preview and execution with an explanation. NPC/mixed output and personal costs
are not presented as if implemented. Storage routing, worker fees, shared production,
background execution and workshop Player assignment remain unresolved integration work.
An optional scope question was asked; implementation proceeded with the independent
selection work while NPC execution stayed gated.

Files changed: clay_worksite_session.gd, test_scene_clay_worksite.gd,
clay_worksite_inspector.gd/.tscn. New: test_scene_clay_worksite_team.gd/.tscn and this report.
No production autoload, resource, global hiring, worker status, settings or balancing edits.

Verification: graphical team test at 1200x675 passed; screenshot reviewed. Selection of
Player+NPC and NPC+NPC, deselection, two-slot cap, busy rejection, reopening, independent
site teams, no inventory/time mutation, NPC execution guard and Player-only restoration
are covered. Inspection, gathering and full Nightmare round-trip regressions passed.
git diff --check clean. Existing certificate/shutdown warnings persist.
No commit, push or merge performed.
