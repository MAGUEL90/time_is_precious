# Multi-worker worksite navigation

Status: **PASSED — NEEDS HUMAN REVIEW** for the scenarios below. Branch
`fix/worker/multi-worker-resilience-20261104` starts at
`13a6c0725a08c91bfcbc2606646e8ebf0f668968` on
`feature/gameplay/character-needs-20261101`. The new checkout was clean. The
work is limited to resource-worker navigation and its tests; no gameplay rates,
stock capacities, player construction materials, delivery routes, save fields,
project settings, plugins, or assets were changed.

## Findings and changes

A fresh two-worker assignment at the actual Wood Site reached both entries on
the baseline, so two simultaneous workers alone did not reproduce a stuck
worker. Another reproducible sequence did expose an overlapping-entry defect:
assign two workers, remove the first, and add a replacement. The survivor
keeps the second entry, but its list index becomes zero; the replacement then
receives the same second entry. The game gives both workers independent output,
but their visuals travel to and work at the same point. The current request did
not include a precise reproduction or save for the reported stuck worker, so
this overlap is a confirmed defect, not proof that it was the only cause of
that report.

Entry selection now retains a worker's existing authored entry and gives a new
worker the free one. The existing two-entry save contract is unchanged. A
synthetic checkpoint with the old overlapping state remains readable without
rewriting its in-progress journey; on the next shift the two workers select
different entries in assignment order.

A separate fixture reproduced an indefinitely cached failed route: a worker's
entry is temporarily obstructed, the search fails, and the obstruction is then
removed through the navigation snapshot API. The cached empty path was reused.
Site route caches now include the navigation geometry revision, so a geometry
change permits a new search; an unchanged obstruction is still cached, does not
send a worker through solids, and does not create arrival or production. Normal
map refreshes also clear these transient caches. The test's obstruction is
synthetic; it is not a claim that a particular building caused the original
report.

## Validation

Godot **4.5.2** on Linux, headless, isolated XDG profiles. The new
`test_scene_multi_worker_navigation.tscn` was run with `--navigation-phase=write`
and then `read` in separate processes sharing a fresh profile. The phases
passed 347 and 340 assertions respectively. The separate `hire` phase passed
435 assertions, using both starting residents, the actual hiring backend and a
third fixture applicant. These scenarios exercise actual Wood Site
geometry and physical travel, no remote work during clock skips or obstruction,
no movement during transition/unpaid travel, replacement in both removal orders,
replanning after geometry changes, final-unit stock contention, the 15:00 shift
boundary, next-day resumption, actual disk save/load, repeated load, and a
synthetic older overlapping checkpoint. The tests check individual production
and shared stock conservation without fixing where output is delivered.

The project imported and launched headlessly without a reported script error.
`test_scene_review_resource_paths.tscn` passed routes to both entries at all
five current resource sites and walked to fixture pickups on this pre-logistics
baseline; `test_scene_city_residents.tscn` passed resident lifecycle and
save/load. `test_scene_workshop_arrival_schema8.tscn` and
`workshop_shift_resignation_test.tscn` also passed.

Four older tests did not pass. Each was rerun on a separate checkout of
`13a6c07` with the same engine and reproduced the same result:

- `test_scene_content_actual_arrival.tscn` fails its final evening snapshot
  validation because the workshop time cursor differs from its test clock.
- `clay_worksite_test/test_scene_clay_worksite_team.tscn` fails two combined
  player/worker output assertions.
- `test_scene_worksite_midnight_continue.tscn` passes `write` but its `read`
  rejects the legacy fixture checkpoint as unsupported and then reports an
  invalid WoodSite lookup.
- `resource_worksites_test.tscn` attempts a retired worksite Hauler assignment,
  then errors on the absent route and fails to quit. The modified run was
  stopped after its error and the baseline run hit its 30-second timeout.

These are controlled fixtures, not a manual playthrough or Windows validation.
The blocked geometry and worker funding/positions are test setup. The logistics
branch must integrate the director's newer rule—direct worksite output to City
Storage, player-supplied construction materials, and haulers between storage
locations—then run combined end-to-end tests before the game is updated.
