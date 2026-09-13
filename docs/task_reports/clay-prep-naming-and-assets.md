# Clay preparation: test fixture, workshop naming, and old image cleanup

Date: 2026-09-07
Status: PASSED — NEEDS HUMAN REVIEW
Branch: `feature/process-workshop/clay-worksites`
Baseline: `0f971ab330b83e2c8502ef943ddd04e94019565a`
Risk: LEVEL 3 — file-path migration across scenes and an existing autoload; asset deletion.

## Scope and authorization

The Game Director requested a new test scene, consistent scene/script filenames, and removal
of unused images. The age rule was explicitly clarified: unused images last updated before
2026-06-07, not images updated within the last three months. This is preparation for the clay
task on the existing branch. No gathering, construction, EXP, tool, or balance rules were added.
No commit, push, merge, new autoload, or governance-file change was performed.

## Test fixture

Open `res://scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.tscn` and run with F6.

Follow-up: the Game Director renamed the pair to `test_scene_clay_worksite.tscn` /
`test_scene_clay_worksite.gd` and the root node to `TestSceneClayWorksite`. Those edits were
preserved; the movement/marker/inventory fixture check passed again with the new path.
The original creation names are recorded below for history.

- New paired scene/script: `clay_worksite_test.tscn` / `clay_worksite_test.gd`, plus script UID.
- Reuses Player, InventoryUI, BottomHUD and the gameplay theme.
- Two labeled Marker2D locations are layout placeholders, not functioning resource nodes.
- Uses drawn ground/markers; no new image asset or dependency.
- Player needs are disabled only on this fixture's player instance to support layout testing.
  This fixture does not test condition drain, collapse, harvesting, or rewards yet.
- Site spacing is fixture layout, not approved production-world placement.

## Filename migration

| Previous | Current |
| --- | --- |
| `scenes/work_shop/work_shop.tscn` | `scenes/workshop/workshop.tscn` |
| `scenes/work_shop/work_shop.gd` | `scenes/workshop/workshop.gd` |
| `scenes/work_shop/work_shop.gd.uid` | `scenes/workshop/workshop.gd.uid` |
| `scenes/work_shop/work_shop_claim_area.gd` | `scenes/workshop/workshop_claim_area.gd` |
| `scenes/work_shop/work_shop_claim_area.gd.uid` | `scenes/workshop/workshop_claim_area.gd.uid` |
| `scripts/autoload/work_shop_storage/work_shop_storage.gd` | `scripts/autoload/workshop_storage/workshop_storage.gd` |
| `scripts/autoload/work_shop_storage/work_shop_storage.gd.uid` | `scripts/autoload/workshop_storage/workshop_storage.gd.uid` |

Updated path references in `project.godot`, the renamed workshop scene, `content_scene.tscn`,
`test_scene_worker.tscn`, and `work_state_smoke_test.tscn`. Updated `docs/root-branch-map.md`
with current paths and the snake_case/paired-basename convention.

The existing public names `WorkShop`, `WorkShopStorage`, node paths and method names remain
compatible. This task standardizes filenames, not public APIs. All seven moved files were
compared with baseline content: scripts and UIDs match; the scene differs only in file paths.
The project setting change is only the existing storage autoload's script path.

## Removed images

Audited 209 project PNG/JPG/JPEG files outside addons; retained 188 and removed 21 PNGs,
plus their 21 `.import` sidecars. Removed image payload: 31,518 bytes. No JPG/JPEG was removed.
Six unreferenced but recent images were retained. Uncertain or untracked history was not
eligible for deletion.

See `clay-prep-removed-assets.json` for the exact paths, sizes, filesystem modification dates,
and latest Git commit dates at audit time. Its `candidate: true` records the pre-deletion
eligibility decision; all listed images and their sidecars were then removed.

Eligibility required BOTH filesystem modification time and latest Git change before
2026-06-07 00:00 Asia/Jakarta, and no references by path, filename or import UID in project
source/resource/document files. The scan included test scenes and resource files, not just
the main-scene dependency tree. Dynamic loaders were inspected: item/worker/applicant loaders
read resources whose texture references were included in the scan. Import self-references,
Git internals and generated `.godot` cache were excluded as evidence of usage. Addon assets
and non-image source artwork were retained.

Before removal, the exact targets were checked to be inside this repository's assets folder.
Byte-verified recovery copies were made under
`C:/Users/Hendro/AppData/Local/Temp/tip-clay-prep-20260907/removed-assets/`.
These temporary copies are not a permanent backup; original tracked assets also remain in Git.

## Existing local changes preserved

- `docs/CONTENT_LOG.md`: byte-identical to the start of this task.
- `docs/game-concept.md`: prior v0.11 edits preserved byte-for-byte.
- `docs/task_reports/clay-worksites-start-brief.md`: untracked brief preserved byte-for-byte.
- `scenes/content_scene/content_scene.tscn`: previous apple pickup retained; comparison against
  the task-start snapshot confirms the only additional change is the workshop resource path.

## Validation

Godot 4.5.1, GL Compatibility; fixture visually inspected at logical 400x225 with a 1200x675
window. Test logs and the fixture screenshot are under the temporary task directory above.

| Check | Result |
| --- | --- |
| Editor import and script-class refresh after migration | Exit 0; no parser or missing-resource errors |
| Clay fixture: two markers, actual movement, inventory open/close pause restoration | PASSED, exit 0 |
| Fixture screenshot | Reviewed; player, two labels/markers and existing bottom UI visible |
| ConditionHUDRegressionTest | PASSED, exit 0 |
| WorkshopUIRegressionTest | PASSED, exit 0 |
| MudbrickProductionChainIntegrationTest | PASSED, exit 0 |
| PopulationEmploymentIntegrationTest | PASSED, exit 0 |
| Main content scene launch, 12 frames | Exit 0; no parser or missing-resource errors |
| Worker test scene and work-state smoke scene launch, 12 frames each | Exit 0; launch checks only |
| Seven moved-file contents and four pre-existing local files | Verified |
| Retained images still present / removed images and sidecars absent | Verified |
| Live resource references to the old workshop file paths | None found |
| `git diff --check` | Clean |

The sandbox initially denied Godot's normal editor configuration/cache directories. Tests used
temporary APPDATA/LOCALAPPDATA paths instead. The engine's root-certificate-store error and
shutdown resource/ObjectDB warnings also appeared in the pre-migration editor baseline; they
remain reported, not suppressed. Runtime tests exit 0 and report their assertions passing.

Manual F6 review remains the human gate. Full gameplay, sleep/Nightmare sequences, mobile
testing, save compatibility and the future gathering loop were not tested by this preparation.
