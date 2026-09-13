# Clay worksite team production

Superseded by [Hourly / Daily](clay-worksite-hourly-daily.md) on 2026-09-08.
Mixed session selection and one-shot NPC jobs below describe the prior checkpoint.

2026-09-08 — PASSED — NEEDS HUMAN REVIEW.
Branch: feature/process-workshop/clay-worksites. Scope: existing test fixture and sandbox UI.

## Approved behavior

- Both sites start with empty assignments. Player must be chosen explicitly.
- Small worksite capacity remains two, including Player; durations are 3/6/9 hours.
- Each participant contributes the existing 6 clay/hour baseline to the same finite stock.
  Two participants preview 36 clay in 3 hours; 72 stock caps a 9-hour choice at 6 hours.
- Wilderness worksites have no fee. They do not use workshop escrow or fee payment.
- Teams including Player use the existing time skip and transition. Output enters personal
  inventory, with excess in a ground pickup. Normal minute signals apply Player needs once.
- NPC-only teams run on world minutes while Player remains free. Completion produces one
  quantity-labelled pickup at the originating site, independent of Player position/inventory.
  World-minute advancement also processes these jobs during other activities' time skips.
- Workers are reserved through existing WorkerData start_work/finish_work. Busy workers
  cannot start another site job; active teams cannot be edited. Completion, interruption,
  and fixture teardown release reservations. Preview rechecks availability at Start.
- Player collapse stops the mixed session and delivers completed work only, before the
  existing Nightmare handoff. The minute that initiates collapse earns no additional output.

## Validation

Headless team, inspection, gathering, and full Nightmare escape/timeout tests passed.
Team regression also passed graphically at 1200x675; empty assignment and mixed preview
screenshots reviewed. Coverage includes empty Start guard, capacity, unavailable workers,
36-clay mixed output with 2 bag / 34 ground, single Player condition drain, NPC-only Start
without a time skip, 179/180-minute completion, site-positioned 36-clay pickup, no duplicate
payout, stock cap, mixed collapse output, and worker release on fixture removal.

Workshop UI, condition HUD, and population/employment regressions passed. Main scene and
work-state scene load smoke passed. Work-state is an interactive fixture, so its load check
does not claim a full manual workshop production run. The first unbounded launch was stopped
and rerun with --quit-after 12. Concurrent Player/NPC site time advancement also passed.
Existing certificate-store and shutdown resource warnings remain; no new blocking errors.
Existing local assets, renames, scene edits, and unrelated documents were preserved.
git diff --check passed. Existing untracked fixture files were reviewed directly.

## Files changed in this step

- scenes/test_scenes/clay_worksite_test/clay_worksite_session.gd
- scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.gd
- scenes/test_scenes/ui_sandbox/clay_worksite_inspector/clay_worksite_inspector.gd
- scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite_team.gd
- scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite_inspection.gd
- scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite_gathering.gd
- scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite_nightmare.gd
- This report and a supersession note on the earlier selection-only report.

## Manual test

1. F6 test_scene_clay_worksite.tscn; approach Site A and press E. Workers is 0/2,
   Start disabled. Add Worker shows two empty slots.
2. Assign Player and one idle worker, Next, choose 3h. Preview: 36 clay, Energy -9%,
   Satiety -18%. Start. Existing overflow fixture starts with room for two clay;
   expect 2 in the bag and a 34-clay ground pickup after the transition.
3. Relaunch F6. Assign two NPCs at Site A and Start 3h. Player can immediately move.
   Return after three game hours: 36 clay lies at Site A. At the current clock speed
   this takes about three real minutes with no menu pause.
4. For a faster background test, assign Player alone to Site B and work 3h while
   Site A's NPC job runs. Those elapsed world minutes advance both sites.

## Limits

This remains a scene-local prototype: leaving/reloading the fixture discards its jobs,
stock and ground items, and releases workers. Cross-scene job persistence, worker actor
animations, hauling, daily schedules, profession/tool bonuses, and EXP remain future work.
NPC-only Energy/Satiety show -- because no Player work time skip is performed; ordinary
Player condition drain still occurs as world time passes. Current eligible professions
retain the same baseline rate; no profession multiplier or new hiring rule was added.
No commit, push, or merge performed.
