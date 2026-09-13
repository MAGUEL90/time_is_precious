# Worker Hub compact status and management

Date: 2026-09-12
Scope: existing clay worksite test fixture and its Worker Control UI; preserve existing local changes.

## Result

- Status rows now show name, role and Work/Idle with existing separator artwork, vertically centered, followed by Manage.
- Removed the main footer Close, status feedback and per-row Remove. The animated top close remains. Scrollbars are four logical pixels wide.
- Manage opens Fire, Go to and Details. Details shows Level (existing profession star), Wage, Location and Productive days.
- Fire is actual workforce dismissal, confirmed with Yes/No, available only while idle. It cancels the local Daily assignment, returns equipped units to City Storage, removes draft selections and changes a linked citizen to Unemployed. Earned progression is retained in a runtime archive for subsequent rehire.
- Active travel, gathering and unfinished hauling routes block Fire. External workshop assignments must be released through their owning system first.
- Go to is available for an active worker with a known worksite. It closes the Hub, teleports Player beside that site, clears velocity and resets camera smoothing.
- Tools remain managed through the Tools tab. Manage does not redirect there.

## Validation

- WorkerControlTest: PASS, including idle/work action gates, confirmation cancellation, teleport, employment removal, returned equipment, retained XP on rehire, tool ownership and four-pixel scrollbar width.
- PopulationEmploymentIntegrationTest: PASS.
- ClayWorksiteDailyTest: PASS.
- ClayWorksiteHaulerTest: PASS.
- Main-scene headless launch: exit 0. Git diff whitespace check: PASS.
- Inspected rendered Status, Manage, Details, Tools and Fire confirmation captures.
- Existing environment warnings remain: root certificate store, ObjectDB leak and 15 resources at exit.

## Manual check

Run `scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite_hauler.tscn` using F6, then press K for Worker Hub. F7 advances thirty game minutes. During work, Manage enables Go to; after the shift and final hauling trip, it enables Fire. Fire permanently removes the worker from the current runtime workforce after confirmation.

## Boundaries

Worker Control is still integrated with the worksite test fixture. No cross-scene travel or save/load persistence was added; the dismissal archive is runtime-only. Wage is displayed from existing worker data and does not introduce a worksite fee.

Work split: Astra Medium implemented employment/teleport integration, regression coverage and final visual verification; Luna XHigh implemented the compact UI and its Manage/Details panels.

## Follow-up revision

The latest direction replaces player teleportation with camera inspection: Go to centers the camera on the assigned worksite without changing Player position. Movement or Escape restores the normal camera offset. Status uses natural text widths and equal gaps around its separators, leaving flexible space only before Manage. Manage becomes a compact popup beside its row, with the Status panel still visible. Details uses a smaller panel and font sizes in multiples of six.

Follow-up validation: WorkerControlTest passed with camera-only navigation, unchanged player position, restored camera offset, natural text width, compact popup dimensions and outside-click dismissal. Main launch exited 0; whitespace check passed. Rendered Status, Manage and Details were inspected. Manage is 88 x 68 and Details is 150 x 90 logical pixels; UI text uses 6 or 12. Existing shutdown/certificate warnings remain unchanged.

Latest visual adjustment: Manage now uses the simple panel atlas from `assets/ui/ui_base_1/base_1_24.06.2026.png` (region 116, 7, 52, 40), with four-pixel nine-patch borders. Its panel is 56 x 64 and each action button is 44 x 16, matching Details' Back button. WorkerControlTest passed and the rendered popup was inspected. The source asset is referenced instead of the generated `.godot/imported` cache.
