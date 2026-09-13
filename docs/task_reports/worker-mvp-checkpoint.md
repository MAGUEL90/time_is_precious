# Worker/worksite MVP commit checkpoint

Date: 2026-09-13
Branch: feature/process-workshop/clay-worksites
Baseline: 0f971ab330b83e2c8502ef943ddd04e94019565a
Status: PASSED — NEEDS HUMAN REVIEW

## Scope

The Director confirmed the latest playtest works and requested a local commit checkpoint. This records the existing approved worker/worksite MVP: manual and Daily work, common commute speed, Laborer/Hauler animation, exclusive tools, Worker Hub/City Storage, accepted-item delivery targets, contribution XP/productive days, prototype disk persistence and F for tomorrow 06:45. No new mechanics are introduced in this checkpoint.

The working tree contains the entire feature plus earlier workshop path migration and unrelated changes. Include the already-approved workshop rename and its required path references so the committed project is self-contained; include the new work-reservation guards in workshop/job selection. Stage only the workshop reference hunk in the content scene. Preserve the separate apple-pickup edit, design/content drafts, generic work-progress scene tweaks, old unused-asset deletions and obsolete storage-view prototype outside the commit.

Risk: LEVEL 1 for selective Git staging/local commit; the recorded feature includes previously authorized LEVEL 2/3 changes. No push, PR creation or merge is requested. Protected governance remains unchanged. No save files, QA data, generated `.godot` cache or unrelated cleanup enter Git.

## Commit gates

Review selected file/dependency inventory and staged diff; export the staged tree into an isolated temporary directory; import from scratch and run current worker/Hauler/storage/save and nearby employment/workshop checks there. Compare untouched working files against pre-stage hashes. Commit only after required checks pass; retain known pre-existing shutdown diagnostics in the report.

## Validation result

The selected staged project was exported to a clean temporary checkout and imported with Godot 4.5.1 from scratch. Import passed without new parse errors or missing resources. All 15 checks passed: delivery setup, Worker Control, Tools layout, Daily scheduling, Hauler loop, commute, cart animation, work animation, storage destination, employment integration, mudbrick production, workshop UI, main-scene launch, and separate-process save write/read.

A graphical delivery-setup run also passed. Its captured commute and delivery images were inspected: the commuting worker has no cart, while the active delivery uses the supplied cart. The checks use isolated save directories and do not read or overwrite the Director's gameplay saves.

Known diagnostics remain: the local certificate-store error and Godot exit-time ObjectDB/resource warnings (15 resources in runtime checks; 16 on editor import). Deliberately invalid save fixtures also emit expected validation warnings. These are recorded separately from the passing assertions; this is not a warning-free build claim.

`git diff --cached --check` passed after removing extra EOF blank lines in five files and trailing spaces in two empty Details preview labels. No runtime layout or mechanics were changed during commit preparation. Pre-stage SHA-256 comparison found no unexpected changes to the other local files.

Local verification artifacts: `C:/Users/Hendro/AppData/Local/Temp/tip-worker-checkpoint-20260913-121738/` contains the selected path list, clean project, import/test logs, JSON results and preservation hashes. Captures: `C:/Users/Hendro/AppData/Local/Temp/hauler-commuting-without-cart.png` and `C:/Users/Hendro/AppData/Local/Temp/hauler-delivery-pushing.png`.

## Remaining MVP boundary

This is a checkpoint of the approved prototype, not full-map integration. City Storage currently receives its tool units from the test fixture; the useful next step is the player-facing Inventory-to-City-Storage supply flow. After that, integrate the reusable worksite/storage and Worker Hub into the main map and its production save lifecycle. Satisfaction/reliability and further balance remain later design work.

No feature blocker remains for the requested local commit. Human review and any future merge remain the Director's decision.

Work split: Astra Medium reviews, verifies and commits. Luna XHigh is not delegated.
