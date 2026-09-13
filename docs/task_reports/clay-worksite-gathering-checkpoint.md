# Clay worksite — playable manual gathering test

Follow-up: [playtest feedback](clay-worksite-playtest-feedback.md) supersedes this historical
checkpoint's stock, duration input, capacity blocking and instant presentation.

Date: 2026-09-07
Status: PASSED — NEEDS HUMAN REVIEW
Branch: feature/process-workshop/clay-worksites
Baseline: 0f971ab330b83e2c8502ef943ddd04e94019565a
Starting tree: dirty with authorized naming/asset cleanup, concept changes, and human edits.
Risk: LEVEL 2 integration using existing APIs; LEVEL 4 provisional balance explicitly
approved by the Game Director in this conversation. No production integration/merge approval.

## Approved scope

One Clay Lump per ten minutes; twenty units per site; no regeneration, required tool or EXP.
Normal existing clock/condition costs, independent site stock, personal-inventory output.
The objective is an F6-playable loop in the existing user-named test fixture.
Production scenes, autoload implementations, Player code, settings, canon and governance
remain outside the edits. No new global manager or persistence schema.

## Implemented behavior

- Approach A/B, press E, choose duration and Start Work in the existing single panel.
- Default input is ten minutes. Whole output cycles round down: 65 requested minutes
  previews six clay and 60 effective minutes. Stock and bag capacity cap both output and
  effective time; the panel shows that effective time before confirmation.
- Start performs a synchronous world-time skip through existing minute signals. It does
  not wait real-world minutes, add a separate progress page or a second confirmation.
- Existing Player condition handling charges hunger, fatigue and Focus once per elapsed
  minute. The fixture now enables normal needs instead of its former debug bypass.
- Each completed ten-minute cycle transfers one clay through Inventory.try_add_item.
  Stock is reserved before the inventory signal; a failed transfer restores that stock.
- Stale/double Start events and reentrant payout callbacks cannot duplicate output.
- Full bag, depleted stock, critical/sleeping/collapsing player or an active transition
  prevent starting. Capacity and interruption state are rechecked each minute.
- Collapse/owner removal stops further time advancement and payout. Only cycles completed
  before interruption pay; the partial cycle has no clay payout and does not carry over.
  Closing before Start costs nothing. There is no mid-skip manual cancellation UI.
- The panel restores its original pause and movement state; collapse retains control.
  A compact fixture note reports actual output and elapsed minutes afterward.
- Stock survives reopening but resets to twenty on fixture reload. This is not persistence.

These rounding/time-skip/interruption details are implementation choices for human review,
not claims of final production balance. Regeneration, tool effects, EXP, construction,
worker delegation, save/load and production-world placement remain out of scope.

## Changed files

Created:
- scenes/test_scenes/clay_worksite_test/clay_worksite_session.gd
- scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite_gathering.gd
- scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite_gathering.tscn
- This report.

Modified:
- scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.gd
- scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.tscn
- scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite_inspection.gd
- scenes/test_scenes/ui_sandbox/clay_worksite_inspector/clay_worksite_inspector.gd
- docs/task_reports/clay-worksite-single-panel.md (historical follow-up pointer).

No files deleted or renamed in this step. Existing names and UIDs retained.

## Verification

- ClayWorksiteGatheringTest: headless and graphical at 1200x675, exit 0.
- ClayWorksiteInspectionTest: headless, exit 0.
- WorkshopUIRegressionTest and ConditionHUDRegressionTest: exit 0.
- Main project launch: twelve-frame smoke, exit 0.
- Graphical work panel reviewed: output, effective duration, stock, costs and Start fit.
- Coverage: normal costs exactly once, unchanged EXP, rounding/capacity, separate stocks,
  depletion, midnight rollover, duplicate/reentrant Start, reopening, capacity changes
  during work, owner removal, actual Player collapse at minute eleven (one completed
  cycle paid), and reset-on-reload.
- The first Start-path test failed because it changed SpinBox.value while focused text
  still held the old input. The corrected test enters text and applies it before Start.
  Final runs pass; this failure was not a yield/time calculation failure.
- Existing certificate-store error and shutdown ObjectDB/resource warnings remain.
  No new blocking parser/resource errors observed.

Full Nightmare entry/return, sleeping, Android and save/load were not exercised here.
The test verifies work stops on actual collapse initiation, then frees the fixture before
the Nightmare transition. Full production lifecycle integration remains a later gate.

Logs and reviewed screenshot:
C:/Users/Hendro/AppData/Local/Temp/tip-clay-work-20260907/

## Human audit

Open scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.tscn and press F6.
Approach A, press E, type 60 and Enter, then Start Work. With enough capacity and healthy
conditions: six clay enters inventory, stock drops to fourteen and clock advances one hour.
Reopen A to check remaining stock; visit B to check its independent twenty-unit stock.
Try a larger duration to inspect the stock/bag-limited effective time before starting.
Close before Start to verify no cost. Needs now run normally even while walking.

No commit, push or merge performed. Human approval remains pending.
