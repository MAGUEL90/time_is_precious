# Worker progress, assignment drafts and daily roaming

2026-09-10. User-authorized worksite UI and behavior changes; preserves existing local edits.

## Main menu and assignment

- Worker main menu hides names, Start work day text and active-status feedback. Confirmed jobs have no redundant Start Work button. Worker Progress appears after confirmation, including scheduled jobs with zero work so far.
- Worker button is disabled when two workers are reserved. Assignment opens with an empty draft and only remaining capacity. Existing jobs are never loaded into removable draft slots.
- Names appear below assignment slots. The total Workers count/separator are hidden. Reserved/unavailable workers sort behind available workers in the selection grid.
- Confirmed workers can only be withdrawn through Worker Progress. Draft selection may still be edited before Start. Closing/reopening assignment resets only the draft, preserving Daily jobs.
- Worker Progress reuses the worksite panel texture/theme and shared close button, with Back, per-worker name, Days worked, Output, and Remove. Days count distinct dates with productive minutes; output counts generated clay during the current assignment, including output awaiting ground settlement. Withdrawal settles complete output and clears that assignment's counters.

## Daily movement

- Next-day start remains. Spawn/depart at 06:00, arrive at 07:00, gather until stock runs out or 15:00. Journey speed is derived from distance over the fixed 60 game-minute interval, replacing the old editable travel-speed rule that delayed production after 07:00.
- After work the worker remains visible and roams away, keeping the standing Daily reservation. At 06:00 next day the actor travels from its current position and reaches its site at 07:00.
- Withdrawn visible actors continue roaming but have no Daily reservation. They are not deleted as an effect of removal. Fixture scene cleanup still removes its actors normally.
- Idle durations are sampled independently per phase/worker between 0.4 and 1.8 seconds. Local work routes choose random points 4-10 pixels from the slot center. Offsite roaming uses bounded fixture positions. Seven-frame base-work / opposite-facing cycle preserved; random visuals do not generate production.

## Changed files

- clay_worksite_daily.gd: draft ownership, withdrawal, per-worker counters, fixed arrival schedule.
- test_scene_clay_worksite.gd: providers, removal hook and obsolete travel-speed cleanup.
- clay_worksite_assignment_ui.gd: empty remaining-capacity slots, names, hidden total and ordering.
- clay_worksite_inspector.gd/.tscn: main menu visibility and Worker Progress panel.
- clay_worksite_worker_visuals.gd: 06:00 departure, persistent roaming, randomized work loop.
- test_scene_clay_worksite_team.gd and test_scene_clay_worksite_commute.gd: updated behavior coverage.

## Validation and limits

Graphical Daily test passed, including progress totals (two productive days, individual output), full-capacity guard, removal, empty remaining slot, and reserved workers sorted last. Main/progress/assignment screenshots inspected. Commute regression covers 05:58 hidden, 06:00 travel, 07:00 arrival, no travel production, random durations/routes, post-work persistence, next-day return and withdrawal persistence. Gathering, Inspection and Workshop UI regressions run for nearby behavior. Known certificate-store and exit-resource diagnostics remain.

Scene-local prototype only: no home pathfinding, obstacles, persistence, XP, profession-rate or stock-range changes. Generated output still goes to the site ground pile. Standing reservations remain globally protected while actors roam.
