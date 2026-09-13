# Clay worksite inspection checkpoint

Date: 2026-09-07
Branch: `feature/process-workshop/clay-worksites`
Baseline: `0f971ab330b83e2c8502ef943ddd04e94019565a`
Risk: LEVEL 1 for the isolated inspection fixture; explicitly authorized image removal.
Status: PASSED — NEEDS HUMAN REVIEW (inspection only, not gathering).

Follow-up: the two-stage UI checkpoint in `clay-worksite-ui-two-stages.md` supersedes this
initial panel's styling and no-pause behavior. The current panel uses workshop styling,
pauses the scene tree and includes Overview -> Work Plan navigation. This report retains
the original checkpoint history.

## Completed scope

The Game Director approved removal of the two candidates from the one-month asset audit and
requested the next clay step. Rechecked references, backed up and verified the exact files,
then removed `gabbi_hair_walk.png`, its `.png.import`, and `Bitmask references gif.gif`.
See `unused-assets-one-month.md` for paths, age evidence and recovery-copy location.

The next step implements inspection interaction in the existing fixture, independently of
the pending balancing decisions. Player-owned filenames, root node name and existing UIDs
were retained: `test_scene_clay_worksite.tscn` / `.gd`, root `TestSceneClayWorksite`.

- Approach either site and press E to inspect its name.
- Stock, recovery, work, tool and EXP fields explicitly show TBD.
- Work is disabled; there is no stock, output, EXP, or construction implementation.
- The inspector locks movement and blocks inventory/work-progress shortcuts while open.
- Close, Escape or E closes the panel and restores the prior movement permission.
- Opening the inspector does not change the world clock pause flag or scene-tree pause.
- Existing fixture-only disabled needs remain unchanged; this is not a condition-drain test.
- The 32-pixel interaction reach is a fixture UI distance, not production gathering tuning.

The new UI is isolated under `scenes/test_scenes/ui_sandbox/clay_worksite_inspector/` and is
instanced only by the test fixture. No production Player, inventory, clock, autoload, settings,
governance or gameplay-balancing file was edited in this checkpoint.

## Files

- Modified fixture scene/script in `scenes/test_scenes/clay_worksite_test/`.
- Added paired `clay_worksite_inspector.tscn` / `.gd` in the UI sandbox above.
- Added paired `test_scene_clay_worksite_inspection.tscn` / `.gd` in the fixture directory.
- Updated the one-month asset audit deletion record; added this report.
- Deleted exactly the two approved assets and one import sidecar.

Pre-existing dirty production files, naming migration, game-concept edits and the user's
fixture naming were preserved. No commit, push or merge was performed.

## Verification

`ClayWorksiteInspectionTest PASSED`, exit 0, using actual input events for:

- no inspection from outside fixture reach;
- both site names and repeated A -> B -> A opening/closing;
- movement lock and restoration;
- disabled unconfigured work;
- inventory shortcut blocked during inspection and restored afterward;
- unchanged inventory, EXP and clock pause flag.

Ran headless and GL Compatibility, with visual review at 400x225 logical / 1200x675 window.
Main project launch after deletion passed (12-frame smoke, exit 0). `git diff --check` clean.
No new parser or missing-resource errors were observed. The previously observed certificate
store error and shutdown resource/ObjectDB warnings remain in the logs.

Logs and screenshot: `C:/Users/Hendro/AppData/Local/Temp/tip-clay-prep-20260907/`.
Manual F6 review, actual gathering, regeneration, equipment, EXP rewards, cancellation during
work and collapse/Nightmare behavior remain untested/unimplemented at this checkpoint.

## Next design gate

The start brief still requires explicit agreement on capacities, recovery cycles, primary
input, duration/rounding, tool effects, work fatigue, EXP, payout and interruption semantics.
Inspection does not settle those choices. The current decision table is in
`unused-assets-one-month.md`; no numerical gameplay defaults were introduced.
