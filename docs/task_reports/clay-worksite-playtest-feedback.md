# Clay worksite — playtest feedback

Date: 2026-09-07
Status: PASSED — NEEDS HUMAN REVIEW
Branch: feature/process-workshop/clay-worksites
Baseline: 0f971ab330b83e2c8502ef943ddd04e94019565a
Starting tree: dirty; existing cleanup, naming, concept and human changes preserved.
Risk: LEVEL 2 existing-system integration; LEVEL 4 test balancing explicitly authorized.

## Requested and implemented

- Shared E prompt appears within the same 32-pixel reach used for site interaction.
  It hides during menus/work and yields to a focused pickup.
- Existing TopHUD scene supplies time/day/weather/population with its existing toggle.
- Start fades to black in 0.15 seconds, stays black for one second, and fades back in
  0.15 seconds. Input and normal clock processing remain paused throughout. Work runs
  through minute signals while black. A local overlay avoids blocking the existing
  collapse checks with SceneTransition.is_transitioning.
- Fixed 1h/3h/6h/12h buttons replace free minute entry. Manual Start above six hours is
  rejected in both UI and execution. The user chose a worker-required message for 12h;
  hiring/delegation remains deferred.
- The user explicitly approved 72 initial clay per site. No regeneration; reload resets
  the fixture stock. One clay still costs ten game minutes: 6/18/36 clay for 1/3/6 hours,
  provided stock and conditions allow completion. Depleted stock still caps effective time.
- The shared workshop panel is now 270x155, with larger body text, direct duration buttons,
  before/after Energy/Satiety, actual planned minutes, stock and bag/ground output split.
- Inventory capacity no longer shortens or blocks work. At completion, earned output fills
  remaining bag capacity; overflow spawns as one existing PickUpItem clay stack with the
  exact remaining quantity and a visible count. Existing spawn/pickup feedback is reused.
  The existing pickup requires room for its whole stack; no partial-pickup system added.

## Condition calculation

Preview is read-only. It estimates normal elapsed-time costs for the effective work duration;
it is not a guarantee that critical Energy/Focus will allow completion.

On Start, each game minute advances through TimeComponentManager.advance_minutes(1).
Existing Player.on_minute_changed increments Hunger/Fatigue, applies awake Focus loss,
then checks collapse. No second manual needs charge is applied at the end.

At the existing rates, one uninterrupted hour raises Fatigue by 0.03 and Hunger by 0.06:
Energy 50% -> 47%, Satiety 100% -> 94%. These are percentage-point decreases.
Focus uses its existing condition-dependent rate, so it is not a flat hourly deduction.

Example: noon + one hour normally ends at 13:00. If collapse starts after eleven minutes,
the clock stops advancing for work at 12:11 and only the first completed ten-minute clay
cycle is paid. Existing collapse/Nightmare handling then retains control. The user sees
a brief time skip, but the simulation checks every minute inside it.

## Files

Modified:
- scenes/test_scenes/clay_worksite_test/clay_worksite_session.gd
- scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.gd
- scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.tscn
- scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite_inspection.gd
- scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite_gathering.gd
- scenes/test_scenes/ui_sandbox/clay_worksite_inspector/clay_worksite_inspector.gd
- scenes/test_scenes/ui_sandbox/clay_worksite_inspector/clay_worksite_inspector.tscn
- docs/task_reports/clay-worksite-gathering-checkpoint.md (follow-up pointer).

Created: this report. No deletion/rename, new assets, global dependency, settings,
production Player/pickup/autoload/UI implementation or governance edits.

## Verification

- ClayWorksiteInspectionTest: headless and GL Compatibility, 1200x675, exit 0.
- ClayWorksiteGatheringTest: headless and GL Compatibility, 1200x675, exit 0.
- WorkshopUIRegressionTest and ConditionHUDRegressionTest: exit 0.
- Main project: twelve-frame launch smoke, exit 0.
- Panel, long-title, blackout and ground-stack screenshots reviewed.
- Coverage includes prompt range, all duration choices, worker rejection, before/after
  estimates, full bag preview, no preview mutation, modal input, closing, independent stock,
  six-hour completion, depleted stock, midnight, exactly-once condition costs, unchanged EXP,
  split/fully-overflowed output, capacity changing during work, collecting the ground stack
  through E, reentrant/duplicate work/pickup, one-second blackout, updated Top HUD,
  collapse at minute eleven, reload stock and removal during fade releasing pause.
- The E-pickup test initially pressed before physics established overlap/focus. It now
  waits for the physics update and asserts focus before pressing; final runs pass.
- Task-start hash comparison found only the seven intended implementation/test files changed.
  Existing local work remained byte-identical. git diff --check passes.
- Existing certificate-store error and shutdown ObjectDB/resource warnings persist.

No claim of full Nightmare entry/return, production-world integration, worker delegation,
save/load or Android validation. Stock/ground drops are fixture-local, not persistent.
Worker animation during transition remains a future visual step; this MVP uses blackout.

Evidence: C:/Users/Hendro/AppData/Local/Temp/tip-clay-feedback-20260907/
Manual audit: F6 test_scene_clay_worksite.tscn, approach site, E, choose 1h/3h/6h,
inspect costs/output, Start; check HUD time and inventory. 12h must explain worker requirement.
No commit, push or merge. Human approval pending.
