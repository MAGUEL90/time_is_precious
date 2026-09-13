# Clay worksite UI — two-stage audit handoff

Superseded by [the single-panel checkpoint](clay-worksite-single-panel.md) at the
Game Director's request. The two-page flow below is retained as historical evidence only.

Date: 2026-09-07
Status: PASSED — NEEDS HUMAN REVIEW (UI stages only)
Branch: `feature/process-workshop/clay-worksites`
Baseline: `0f971ab330b83e2c8502ef943ddd04e94019565a`
Starting tree: dirty with prior authorized cleanup, naming migration, concept changes and
the Game Director's `test_scene_clay_worksite` naming. Those changes were preserved.
Risk: LEVEL 1 isolated UI; scene-tree pause is scoped to this test fixture's modal lifecycle.

The Game Director requested consistent workshop-style UI and authorized continuing two stages
before their audit. The stages announced and completed were visual/behavioral consistency,
then Overview -> Work Plan navigation. No stock, work duration, equipment bonus, condition
cost, EXP reward or production-world placement was decided or implemented.

## Stage 1 — Workshop UI consistency

- Uses the same NinePatch atlas region from `base_24.06.2026.png` as WorkshopProductionUI.
- Uses the same centered 270x155 window, 16-pixel content margins, header/footer structure,
  gameplay theme, HudLabelMain/HudLabelShortcut text and HudShortcutButton navigation style.
- Instantiates `close_icon_button.tscn` at the header's upper right, including its existing
  normal, hover and pressed atlas states. The text Close button and flat custom panel are gone.
- Uses the workshop-style dim overlay and full-viewport modal control.
- Pauses the scene tree while open, while the modal continues processing input.
- Restores the previous tree pause state on close or removal; does not toggle the separate
  TimeComponentManager pause flag. Back/Next navigation keeps the modal pause continuously.
- Retains direct panel closing, matching the inspected workshop menus. No new fade/shrink
  animation was invented; the shared Close icon's hover/pressed feedback is reused.

## Stage 2 — Overview and work-plan flow

1. Approach site A or B and press E. The selected site's overview opens.
2. Next appears at the right of the footer. No redundant Back button appears on the first page.
3. Next opens Work Plan. Back is at the left; Start Work is at the right.
4. Back returns to the same site's overview without closing or resuming gameplay.
5. Header X, Escape or E closes either page and restores player movement.
6. Reopening either site always starts at its overview.

Keyboard focus goes to Next on Overview, then Back on Work Plan while Start Work is disabled.
Enter activates the focused navigation button. Inventory and Work Progress shortcuts are
blocked only while the modal is open, and normal inventory access resumes after closing.

The one live gameplay readout is bag capacity, calculated from existing inventory capacity
and the existing Clay Lump weight. It updates on `Inventory.items_changed`, rounds down to
whole units, and clamps an overfull bag to zero. It is carrying capacity, not available site
stock or a promise of output. Both pages show the same readout.

Site stock, cycle capacity, recovery, requested quantity, work duration, equipped tool,
condition cost and EXP remain visibly TBD. Start Work is disabled with an explanation.
This checkpoint does not add a quantity selector, work execution, stock regeneration,
cancellation payout, reward, or leveling system. Those need the start brief's design agreement.

## Files changed in this task

- `scenes/test_scenes/ui_sandbox/clay_worksite_inspector/clay_worksite_inspector.tscn`
- `scenes/test_scenes/ui_sandbox/clay_worksite_inspector/clay_worksite_inspector.gd`
- `scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.gd`
- `scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite_inspection.gd`
- `docs/task_reports/clay-worksite-inspection-checkpoint.md` (historical follow-up pointer)
- This report (new).

The user-renamed fixture scene, its node name and UIDs were not changed. No production UI,
Player, inventory, clock, project settings, governance, gameplay canon or asset files were
changed in this task. A task-start hash comparison confirmed that only the five existing
files listed above changed; the other snapshotted files remain identical.

## Automated and visual verification

| Check | Result |
| --- | --- |
| ClayWorksiteInspectionTest, headless | PASSED, exit 0 |
| Same test, GL Compatibility at 1200x675 | PASSED, exit 0; overview, plan and long-title screenshots reviewed |
| Same test at 1000x675 | PASSED, exit 0; window remains centered in the expanded viewport |
| WorkshopUIRegressionTest | PASSED, exit 0 |
| ConditionHUDRegressionTest | PASSED, exit 0 |
| Main scene launch, 12-frame smoke | Exit 0, no parser/missing-resource errors |
| `git diff --check` | Clean |

Coverage includes proximity, site A/B identity, repeated opening, keyboard navigation, footer
ordering, disabled work, no world-time/condition advancement during pause, actual movement
after closing, full/overfull inventory display, capacity refresh on both pages, unchanged
inventory/EXP, preservation of an existing pause, long-title truncation without covering X,
freeing an open fixture, and loading a fresh closed fixture.

The first layout assertion ran before the newly visible footer finished Godot's deferred
container layout. The test now waits for layout before inspecting positions; final runs pass.
The pre-existing root-certificate-store error and shutdown ObjectDB/resource warnings remain
visible in logs. No new parser or missing-resource errors were observed.

Logs/screenshots: `C:/Users/Hendro/AppData/Local/Temp/tip-clay-two-stage-20260907/`.
The existing fixture still disables player needs for layout testing; this task does not
validate active gathering, balance, sleep/Nightmare, save/load, or Android behavior.

## Human audit

Open `res://scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.tscn`, then F6.

- Approach each site, press E, and compare the window/Close icon with the workshop menus.
- Check Next -> Work Plan -> Back, then repeat without closing.
- Close with X, Escape and E; verify movement and inventory access afterward.
- Confirm that Start Work is disabled and all unapproved rules remain TBD.
- Review font size, spacing, footer alignment and Close hover/pressed feedback.

No commit, push or merge was performed. Human audit remains the acceptance gate before the
next gameplay-design checkpoint.
