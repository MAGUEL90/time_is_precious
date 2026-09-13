# Clay worksite — single-panel checkpoint

Follow-up: [playable gathering checkpoint](clay-worksite-gathering-checkpoint.md).
The disabled Start/TBD output described below records the earlier UI-only state.

Date: 2026-09-07
Status: UI IMPLEMENTED — HUMAN AUDIT PENDING; gathering execution not implemented
Branch: `feature/process-workshop/clay-worksites`
Scope: isolated test fixture; prior local edits, cleanup and user scene/script naming preserved.

The requested flow replaces Overview -> Work Plan: approach a site, press E, and
immediately see duration, estimated output, Energy used, Satiety decrease and Start Work.
No Back/Next navigation or second confirmation popup remains.

The centered 220x140 panel reuses the workshop NinePatch atlas, gameplay theme and
shared Close icon with normal/hover/pressed states. Closing remains immediate, matching
the inspected workshop pattern. X, Escape and E restore movement and the prior pause state.
World time pauses while editing; inventory/work-progress shortcuts are blocked in the modal.

Duration uses whole game minutes, starts at the clock's smallest unit (1 minute), and
accepts typed values with Enter or spinner arrows. It is a UI input, not approved work tuning.
Energy/Satiety previews use the existing player's normal awake per-minute condition rates,
clamped to remaining condition range. They do not apply costs or advance time. The fixture
still disables live player needs; these are normal-clock forecasts only, not a validated
gathering cost. Additional work fatigue, Focus effects and collapse interruption are not modeled.

Estimated output remains TBD and Start Work remains disabled because gathering rate and
site stock have no approved configuration/backend. No yield, stock, equipment bonus or EXP
reward was invented. A full bag displays a capacity reason instead. Once execution exists,
Start Work is intended to confirm directly in this panel.

## Validation

- ClayWorksiteInspectionTest passed headless and graphical (exit 0).
- WorkshopUIRegressionTest and ConditionHUDRegressionTest passed (exit 0).
- Graphical screenshots reviewed at 1200x675, including a long title clipped before Close.
- Covers typed duration, live preview updates, condition clamping, full bag, distant interaction,
  both sites, repeated open/close, no time/cost mutation, movement and inventory restoration,
  existing pause preservation, freeing an open fixture, and fixture reload.
- Synthetic Enter input was corrected to an actual Enter key event; final runs pass.
- Existing certificate-store error and shutdown ObjectDB/resource warnings persist.

## Human audit

Open `res://scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.tscn` and press F6.
Approach either site and press E. Type 60 minutes and press Enter; inspect the estimates,
spacing and Close feedback. Close using X, Escape and E and check movement afterward.
The output/Start limitation is intentional at this UI checkpoint; active gathering and
balancing remain the next design/implementation checkpoint.

Changed implementation: the inspector scene/script, fixture script passing its Player,
and dedicated inspection regression script. No production gameplay code was changed.
Logs/screenshots: `C:/Users/Hendro/AppData/Local/Temp/tip-clay-single-panel-20260907/`.
No commit, push or merge performed.
