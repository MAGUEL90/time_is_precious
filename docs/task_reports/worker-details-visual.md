# Worker details visual presentation — 2026-09-24

User approved replacing the dense worker details text with need indicators and separate
Satisfaction/Reliability bars. Local presentation-only integration on the existing
`feature/workers/city-storage-supply` branch; prior dirty work preserved.

Changed `worker_control.tscn`, `worker_control.gd`, and the existing
`test_scene_worker_control.gd` regression. The scene contains editable Visuals nodes
inside DetailsWindow/Margin/MainVBox/DetailsScroll. It reuses bread, clothes, house,
empty-bar and filled-bar assets. Popup size is 208x202 logical pixels.

Food/Clothing/Shelter each show an icon and Met/Missing/Pending text. Clothing hover
includes remaining days. Separate metric bars show current percentage and the existing
daily delta; unevaluated needs remain neutral and show current metrics when known.
Level, wage and location remain compact text; productive days sits at the bottom.
The original formatted summary is retained as the overview tooltip and compatibility
data; the old full text block is hidden. No calculations or need allocation changed.

WorkerControlTest passed, including added checks on visible bars, percentages, need
status and bounds, plus existing open/close, live refresh and long-name checks. Rendered
met, missing and pending states were inspected. Main GL launch passed. Existing
certificate-store and shutdown-resource diagnostics remain; mobile/other sizes untested.

Evidence: `%TEMP%/tip-centered-headers-20260923/qa/worker-visual-final/` and
`worker-visual-main/`. Pre-edit UI copies: `%TEMP%/tip-worker-detail-visual/`.
Incremental script and scene changes reviewed; diff whitespace check passed.
No protected settings, economy or save changes. No commit/merge.
Status: PASSED — NEEDS HUMAN REVIEW.

## Player-facing polish

Follow-up direction: use small_shekel_8x8 for wage, prefix location, center a plain
Daily needs heading, replace unevaluated statuses with '-', use butcher's cut and
trimmed robe assets, retain shelter pending a new asset, and reduce bottom whitespace.
Implemented in the same scene/script; popup minimum height reduced from 202 to 180.
Removed '(current)' from visible metrics and the technical full-summary overview
tooltip. Existing internal formatted summary remains for compatibility checks.

WorkerControlTest passed and the pending-state capture was inspected. Initial scene
edit failed on PowerShell's handling of the curly apostrophe in the asset path, causing
a temporary missing-node test failure; corrected the quoting and completed the scene
edit before the successful rerun. Whitespace check passed. Evidence:
`%TEMP%/tip-centered-headers-20260923/qa/worker-polish-fixed/`.
No gameplay or calculation changes. Human visual approval remains pending.

### Wage row and native Food icon

Moved wage beneath Level as `Wage: [small Shekel icon] value / day`, before Location.
Food now uses its native 16x16 texture centered in the icon area, avoiding fractional
scaling to 18 pixels. Increased popup height to 192 to accommodate the added wage row
without clipping Productive days. Initial visual inspection caught a scrollbar and
left-aligned icon; final centered/native texture and height corrections were rerun.
WorkerControlTest passed; final pending-state render inspected. Existing certificate
and shutdown warnings remain. Scene/script changes only, plus this report.
Evidence: `qa/wage-food-final/` under the same temporary QA root.

### Centered details and robe pixels

DetailsWindow now keeps viewport-centered placement instead of following its source
button. Level, Wage row and Location are centered, with symmetric content margins.
Trimmed robe uses native centered pixels with nearest filtering. Popup height reduced
from 192 to 186 to reduce empty space below Productive days. Existing worker regression
passed with an added viewport-center assertion; final render inspected and incremental
scene/script diff reviewed. Whitespace check passed. Evidence: `qa/details-centered-final/`;
pre-edit UI copies: `%TEMP%/tip-details-center/`. Existing engine diagnostics unchanged.
No gameplay or calculation changes; same branch, no commit/merge.

### Clothing playtest alignment recheck

User showed Level/Wage/Location still left aligned. Current disk scene inspection found
all three center properties absent; their removal source was not established. Restored
only those three properties, preserving other scene edits. A temporary smoke loaded the
actual city clothing playtest, opened its worker details, checked both label alignments
and the wage group's rendered center, and captured the result. ClothingDetailsCenter
passed. Evidence: `qa/clothing-details-center/temp/clothing-details-centered.png`.

### Checklist and compact supply

Preserved the user's tweaked scene files without editing either scene. Located the
existing gold check in `assets/ui/ui_icon/icon_24.06.2026.png`, region (84,68,8,8).
Worker rendering adds a native-size checklist icon for met needs; unevaluated '-'
and missing states remain distinct. Existing card layout and settings are retained.
City access rendering pairs the existing Food/Clothing assets with compact point/day,
coverage/reserve and shortage values. Full summary details moved to hover tooltips.
No need evaluation, stock or allocation behavior changed.

Updated existing worker and supply UI assertions for icon/tooltip presentation.
WorkerControlTest, CityFoodUITest and CityStorageSupplyFlowTest passed with GL;
rendered met and compact supply captures inspected. Existing certificate/shutdown
warnings remain. Evidence: `qa/needs-check-final/`, `qa/supply-icons/`,
`qa/supply-icons-flow/`. Incremental implementation diffs reviewed; pre-edit scripts
are in `%TEMP%/tip-supply-icons/`. No scene files or gameplay changes in this follow-up.

City Supply icon-frame follow-up: added a 24x24 backing frame using the first tile of
the existing `brown_panel_24x24.png` atlas; native-size Food/Clothing icons remain
centered. Only the access UI script and this report changed. CityFoodUITest passed,
including long values and refresh states; rendered capture inspected at
`qa/supply-icon-frames/city-food-available.png`. Whitespace check passed; existing
engine diagnostics unchanged. User-authored scene layout remains untouched.

Corrected icon-frame atlas origin from (0,0) to (1,1), matching the existing gameplay
theme's 24x24 normal panel tile. Both frame and summary now use vertical shrink-center
so icon panels align with adjacent multiline text, including wrapped large values.
Added regression assertions for native 24x24 frame size and vertical center alignment.
Rendered capture reviewed under `qa/supply-frame-aligned/`; no scene edits.

## Hub reopen and removal of native tooltips — 2026-09-26

The Hub close method already hid Details, but the clothing playtest T shortcut
explicitly reopened Details on every use. T now toggles the Hub only; Hub.open also
clears stale manage/details/equipment popups before refreshing. The user opens Details
through Manage as usual. Preserved user-authored scene changes.

Removed all nonempty native tooltip assignments found under scenes/scripts, including
worker needs/name/equipment, City Supply, deposit guidance and worksite title. Custom
item info panels remain. Removed tooltip-only summary formatting and updated UI tests
to check the actual compact visible text instead of removed tooltip content.

WorkerControlTest and CityFoodUITest passed, including close/reopen and empty-tooltip
assertions. A temporary smoke loaded the actual clothing playtest, invoked T, opened
Details, pressed Hub Close, then invoked T again: ClothingHubReopen PASSED with Details
hidden. Evidence under `qa/close-no-tooltip-worker/`, `qa/no-tooltip-supply/` and
`qa/clothing-hub-reopen/`. Existing engine certificate/shutdown diagnostics remain.
No gameplay/need calculations, scene layout or project settings changed. No commit/merge.
