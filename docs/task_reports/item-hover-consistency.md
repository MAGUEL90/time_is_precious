# Item hover consistency — 2026-09-23

User requested consistent hover selectors and lower-centered item info, including City
Storage Deposit. Presentation-only local UI integration on
`feature/workers/city-storage-supply`, baseline
`4de7d0521648712b277851b9b6ec90ea07772fab`; 85 pre-existing dirty paths preserved.

## Changes

- ItemSlot: inspection-only slots can display their hover selector while click/drag
  remain locked. Disabled modal slots and empty slots do not gain hover selection.
- ItemInfoPanel: shared lower-center placement above each panel's footer and common
  slot-hover binding. All tooltip descendants ignore mouse input.
- ItemTransferUI: connects item hover/unhover, clears stale info during grid refresh.
  This shared panel covers both city deposit and workshop deposit/withdraw.
- WorkshopStorageMenuUI: hover info on free stock and held output.
- InventoryUI, CityStorageAccessUI and WorkerControl equipment picker use the shared
  positioning method, preserving their existing interaction/confirmation behavior.

Modified seven scripts in their existing locations under scenes/ui,
scenes/storage_destination and scenes/test_scenes/ui_sandbox/worker_control; this
report is new. No economy, input map, autoload, save or gameplay changes.

## Evidence

- CityFoodUITest, WorkerControlTest, WorkshopUIRegressionTest and
  CityStorageSupplyFlowTest passed with GL Compatibility.
- Temporary ItemHoverSmoke passed viewport mouse-motion injection for Inventory,
  transfer, Workshop Storage free stock and physical City Storage. Verified visible
  selector/info, centered info, hover exit cleanup and city drag remaining blocked.
- Inspected rendered captures for all four hover contexts. Normal main GL launch passed.
- Initial temporary smoke had incorrect input coordinates and a typed-dictionary fixture
  assignment; fixed the fixture. Removed external-script early class typing to avoid
  compiling dependencies before autoload registration. Final run has no script errors.
- Actual seven-file incremental diffs reviewed against pre-edit copies; diff check passed.

Pre-edit copies and temporary smoke: `%TEMP%/tip-item-hover-consistency/`.
Logs/captures: `%TEMP%/tip-centered-headers-20260923/qa/hover-mouse-final/`,
`hover-city/`, `hover-worker/`, `hover-workshop/`, `hover-supply-flow/`, `hover-main/`.

Existing certificate-store and shutdown ObjectDB/resource diagnostics remain. Desktop
400x225 logical rendering tested; mobile and other display sizes untested. Automated
mouse-hover coverage does not replace human visual approval. No commit or merge.
Status: PASSED — NEEDS HUMAN REVIEW.

## Wider item info follow-up

User requested a larger info box to avoid the short wrapped lines visible for Barley
Bread. Increased the shared template width from 184 to 260 logical pixels and its
description content width from 172 to 248. Font size and lower-center placement remain
unchanged. Only the shared script/scene and this report changed in this follow-up;
88 prior dirty paths were preserved on the same branch.

CityFoodUITest and the viewport-input ItemHoverSmoke passed. Inspected the rendered
Barley Bread capture: the effect and description each fit on one line. All four hover
contexts remain centered. Existing certificate/shutdown diagnostics persist. Incremental
diffs and whitespace checks passed. Evidence: `qa/info-wide-city/` and
`qa/info-wide-hover/` under the earlier temporary QA directory. Pre-edit copies:
`%TEMP%/tip-item-info-width/`. Other resolutions/mobile remain untested.
