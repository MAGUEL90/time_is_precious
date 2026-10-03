# Branch acceptance — 2026-10-03

Branch: feature/process-workshop/main-map-access.
Baseline: c7d0a4e plus the existing uncommitted debug controls and production-audit work.
Scope: tests and reporting. No gameplay, balance, assets, or map layout were changed in this audit.

## Verdict

Functional branch scope passes with the explicitly enabled testing debug controls.
The ordinary economy loop is still PARTIAL: no normal Shekel access, and normal worker
needs/yield affect batch completion. The branch is not certified free of runtime issues:
two native shutdown crashes occurred once each, then passed unchanged in isolated reruns.

## One continuous current-map session

BranchAcceptanceFlowTest PASS, process exit 0:

1. Start current ContentScene with empty personal Inventory and no hired worker.
2. Hire Laborer and Hauler through Job Board.
3. Equip the one normal city Cart through Worker Hub.
4. Assign Wood Daily work, wait for the next shift, deliver 3 logs to WoodStorage,
   and withdraw them through E. Production and delivery conservation are checked.
5. Remove both workers from the worksite using its confirmation action; verify the
   Laborer is available again. The 3 hauled logs remain and contribute to construction.
6. Explicitly activate debug worker/player guards, top up Shekel and construction kit.
7. Clear the selected plot, build it with the hired Laborer, advance the real clock.
8. Supply and deposit the debug production kit through the existing storage UI.
9. Shape, pay wet-output fee, build Drying Yard, dry, pay drying fee.
10. Upgrade the yard using finished bricks, repeat the production/drying/payment cycle,
    and withdraw one finished brick.

Final accounting: 40 sun-dried bricks produced, 10 consumed by upgrade, 1 withdrawn,
29 in workshop Free Stock. 100 initial debug Shekel minus 14 fees = 86.
No reset between hauling, building and production. Extra construction/production materials
and currency came from Debug; this is not an all-resources-earned economy run.
The inventory-capacity edge probe briefly adds then removes test-owned wood before hires;
that probe supplies no materials to the subsequent gameplay sequence.

## Dedicated regressions

| Suite | Final result |
| --- | --- |
| WorkshopClearingTest | PASS: player or worker, exactly three hours, interruption, state retention |
| WorkshopConstructionTest | PASS: resource transactions, worker eligibility, team deadlines, reload |
| WorkshopConstructionUITest | PASS: real E and assignment/build UI |
| WorkshopPlotIndependenceTest | PASS: separate progress, worker reservations, staggered completion, reload |
| WorkshopPlotAccessTest | PASS on isolated rerun; initial run crashed during shutdown after PASS |
| WorkshopHiringRosterAudit | PASS: hired/dismissed roster synchronization |
| WorkshopTableIconLayoutTest | PASS on isolated rerun; initial run crashed during shutdown after PASS |
| ContentDepthTimeDebugTest | PASS: rendered depth ordering, clock controls, pause guards and debug supply |
| MainMapWorksitesTest | PASS: all five resources, overflow, stockpile withdrawal, simultaneous test-worker hauling |
| MainMapWorkerHubTest | PASS: K/J modal open/close and pause behavior |
| MainMapHaulerStartTest | PASS: Cart allocation, delivery, return on firing, reload |
| NormalStartProductionAudit | PASS as a diagnostic of the expected Shekel blocker, not completion of normal economy |

Normal start independently reaches a built workshop and 17 held wet bricks with no money
or material grants. Payment rejects zero currency. One 17-brick lot is short of the required
20-brick drying batch. Worker yield remains governed by the existing satisfaction/reliability
rules; no rule was changed to force the test to pass.

## Stability observations

The initial batch run had 10 exit-0 results and two exits with code 3221225477 / signal 11.
Both problematic tests printed their assertion PASS before native shutdown crashed.
Each was rerun unchanged in a separate invocation and passed with exit 0.
These first failures remain recorded; the reruns do not prove the crash cause is fixed.
No new GDScript errors were reported in these runs. Existing ObjectDB leak warnings and
15 retained resources at normal exit remain present.

Initial per-test logs and summary:
C:/Users/Hendro/.codex/visualizations/2026/09/26/01a0dc60-e89d-7533-abe7-945885d9db59/branch-acceptance-logs

Isolated reruns and the continuous run are recorded in this conversation's tool results.
Rendered output and debug-panel screenshots were inspected in the same evidence folder.

## Limits and next gate

- Native Godot 4.5.1 Compatibility at 1200x675, logical 400x225.
- E events/UI signals and teleports are automated; continuous manual walking,
  pathfinding around every authored obstacle, and a human UX review are not proven.
- Production RNG is fixed for repeatable assertions, while normal gameplay RNG is unchanged.
- Debug guards and clock advancement are explicit. Food/clothing balance and ordinary
  Shekel income remain outside this passing result.
- Disk saves, release export and mobile were not tested.
- Both built plots still share the existing workshop production/storage services;
  independent construction does not establish separate workshop inventories.
- Resolve/characterize the intermittent native shutdown crashes before claiming a clean
  stability gate. Define normal Shekel access before calling the normal MVP loop complete.

## Changes made for repeatable testing

- main_map_hauler_start_test.gd: optional automatic-run flag so its UI sequence can be reused.
- debug_production_flow_test.gd: optional continuous hauling stage before construction.
- branch_acceptance_flow_test.tscn: selects that continuous scenario.
- This report. Existing dirty work was preserved. No commit, push or merge.

## Follow-up: user-reported worker presentation and abandoned setup

The passing flow above does not establish complete worker presentation or cross-menu
assignment cancellation. The user subsequently reported roaming during construction/
production, a Hauler losing the visible Cart/clothing, and an Idle worker unavailable
at another site after leaving an unfinished workshop assignment.

Source inspection confirms:
- `clay_worksite_worker_visuals.gd` follows Daily worksite jobs only; actors outside
  that schedule roam without checking workshop construction/production activity.
- Cart poses are requested by the hauling branch only. Ordinary roaming hides the
  Cart; this is not evidence that the city-owned equipment was unequipped.
- Initial applicants have no visual profile. The visual scene's fallback sets
  clothing to `default`, which hides the clothing layer. Cart poses also explicitly
  hide unmatched clothing/hair layers because matching assets are not supplied.
- Workshop selection immediately marks the linked citizen ASSIGNED, while the
  activity can remain Idle. Exit handlers lacked draft assignment cleanup.

WorkerCartAnimationTest and MainMapHaulerStartTest passed again under native Godot
4.5.1 Compatibility (both exit 0).
That test validates animation playback, not the missing workshop activity binding.
The existing ObjectDB/15-resource shutdown diagnostics remain present.

Production assignment cancellation is now repaired: the shared selector opts into
the existing-style discard dialog only for production. X, Back to production,
Escape and close_menu guard unfinished selections. Stay keeps the setup; Discard
clears it and releases unstarted citizen reservations. Closing job details also
releases drafts while preserving workers with active orders. Cleaning/build picker
Back behavior is unchanged.

Verification after the fix:
- WorkshopAssignmentDiscardTest: PASSED, exit 0. Covers linked citizen reservation,
  Stay/Discard, selector exit routes, unstarted job-details cancellation, the actual
  Daily Worksite availability check, and active-worker preservation in a mixed team.
- WorkshopConstructionUITest: PASS, exit 0; shared cleaning/build flow retained.
- BranchAcceptanceFlowTest: PASS, exit 0; hiring/hauling, clearing/building and two
  paid shaping/drying cycles still complete.
- Native 1200x675 launch and rendered confirmation checked; git diff --check passed.
- An initial run against the incomplete patch found missing-helper and inherited
  member-name parse errors. Those were corrected before the passing reruns above.

Worker workplace/animation binding and Hauler visual continuity remain diagnosed,
not implemented by this cancellation fix. Recommendation for the next MVP step:
show active workers at their assigned plot/table; make Cart visibility consistent
with carrying/parking it, with compatible clothing art rather than mismatched layers.
No pathfinding, economy, equipment ownership, or animation assets were changed here.

## Follow-up: approved MVP plot entry and optional dust

The subsequent user decision replaces visible workshop work poses with entering the
plot and hiding until work completes. The existing world actor renderer now follows
cleaning/building and plot-originated production orders before applying idle roaming.
Workers walk directly to the editor-adjustable `WorkerEntrance`, disappear, and
reappear there after completion. Map reload restores active workers hidden inside.
This is a cosmetic transition; work duration and outputs are unchanged. Worksite
work animations remain visible. Existing actors are reused rather than duplicated.

`WorkshopPlot.worker_dust_enabled` defaults to true and independently disables the
short pixel dust puff. The effect uses no textures or global RNG, cleans itself up,
and is throttled per plot so simultaneous arrivals do not multiply the burst.
Workers without a citizen appearance use the existing default VisualProfile instead
of the bare-body visual scene fallback. Cart-specific clothing/parking remains out
of scope; no equipment rules or supplied cart art were changed.

Native Godot 4.5.1 Compatibility checks, all exit 0:
- WorkshopWorkerPresenceTest: PASS; cleaning, eight builders, no idle roaming while
  assigned, dust toggle/cleanup, neighboring plot isolation, production and map reload.
- WorkshopConstructionUITest: PASS.
- BranchAcceptanceFlowTest: PASS (the full hiring/hauling/build/production sequence).
- Dust render inspected at TEMP/tip-worker-entry-dust.png; git diff --check passed.

This supersedes the earlier pending workshop animation-binding note. Straight-line
visual movement is intentional for this MVP; obstacle navigation is not implemented.
The existing ObjectDB/15-resource shutdown diagnostics remain. No commit or merge.

The user subsequently clarified that dust should continue as an activity signal.
Each active plot now emits recurring puffs at random local positions and random
0.45–1.25-second intervals (Inspector-adjustable area and interval bounds), using
its own RNG. Cleaning, building and plot-owned production enable it; completion,
the dust toggle and pause stop new emissions. Existing puffs finish their short fade.
The extended presence test validates repeated positions/intervals, area bounds,
pause, completion and per-plot ownership. No gameplay timers or output RNG changed.

Arrival-gate correction: recurring dust now additionally requires an arrived worker
for the current construction phase or production order. Starting a job or walking
toward its entrance no longer enables dust; arrival in a prior phase does not enable
the next phase. WorkshopWorkerPresenceTest passes the added before-approach,
during-approach and after-arrival checks, including production and restored inside
workers. Native run exit 0; existing shutdown diagnostics remain unchanged.

Building presentation now uses the existing filled_bar.png / empty_bar.png source
textures (matching the user-specified imported assets) instead of the world percentage
label. A building-to-built transition holds the full bar for 0.75 seconds and emits
a pixel splash colored from the filled texture, then restores the Workshop label.
Already-built map reloads do not replay completion. Clearing presentation is unchanged.
WorkshopWorkerPresenceTest passes 0/50/100 fill, splash color/single emission and
reload checks; WorkshopConstructionUITest passes. Both native runs exit 0.
Rendered progress and completion screenshots inspected; git diff --check passed.

Follow-up correction: the same asset bar now also replaces the cleaning percentage.
Cleaning uses get_clearing_preview progress and emits the gold splash only on the
clearing-to-empty completion transition (not an interrupted return to uncleared).
WorkshopWorkerPresenceTest verifies cleaning 0/50/100 and its splash alongside the
existing building checks: PASS, exit 0. The test waits for the cleaning splash to
expire before counting the building splash. Cleaning render inspected; diff check
passed. This supersedes the earlier note that cleaning presentation was unchanged.

Completion animation refinement: the intact bar is now replaced by a one-second
shatter effect. After a 0.1-second full-bar hold, actual texture slices separate with
independent velocity, rotation, gravity and fade, using a private visual RNG. Both
filled and empty textures are sliced so no intact background remains behind the
fragments. The label returns after the effect. Presence test PASS (exit 0), including
texture identity, complete fragment coverage, cleaning/building completion and no
replay on reload. Shatter render inspected; diff check passed. Shutdown diagnostics
remain the existing ObjectDB/15 resources messages.

Latest completion choice supersedes shattering: keep the full bar intact, apply a
small 0.35-second bounce with a brightness pulse, then fade from 0.45 to 1.0 seconds.
Fragment generation and visual RNG were removed from the completion effect.
Cleaning/building regression PASS, exit 0; bounce/highlight and fade renders inspected;
diff check passed. Existing arrival-gated work dust is unchanged.

Fade follow-up: completion now composites the empty/fill textures into one image before applying opacity, preventing the under-layer from bleeding through during fade. Bounce is clamped to an exact zero after 0.35 seconds to avoid floating-point pixel-boundary jitter. Local presentation-only change; authored layout and work timing unchanged. WorkshopWorkerPresenceTest PASS (native 1200x675), fade capture inspected, git diff --check passed. Existing shutdown ObjectDB/15-resource diagnostics remain.

Completion fade refinement: inspected the source 46x7 textures and identified their stepped bright glint, still prominent in the user's capture. Preserved bounce/highlight; local completion shader gradually reduces glint contrast during fade (0.35-0.65s). Opacity now fades 0.35-0.85s with fixed geometry. Source assets unchanged. Native WorkshopWorkerPresenceTest PASS; peak/fade captures inspected; diff check passed. Test also reported runtime bridge port 9877 unavailable and existing shutdown ObjectDB/15-resource diagnostics; no shader errors.

Pixel geometry correction: removed completion shader and fractional scaling; use the original bar top-left position and rounded vertical bounce. Single composite fades without recoloring. Added native render comparison against TextureProgressBar: settled frame byte-identical; opacity-only pixel comparisons pass at 0.475, 0.600, 0.725 seconds (2/255 tolerance). First test attempt used an invalid SubViewport property, corrected to World2D. Final WorkshopWorkerPresenceTest PASS with no script/shader errors; bridge-port conflict and baseline shutdown diagnostics remain. Fade capture inspected; diff check passed. This supersedes the glint-softening experiment.
