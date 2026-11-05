# Authored-map defense and save review — 2026-11-05

Review base: `2509d63c672f7ab11fc6c6f55116eba4d4d90e67` on a clean tree. This follow-up uses `fix/raid/authored-map-defense-indicators-20261105`. Risk is high because a moved doorway affects old saved player positions. The session cannot raise its reasoning tier as requested by the repository policy; the limitation was reported before the save-related fix. Human review is required.

## Findings and changes

- Two independent read-only reviews found that the hidden `WallStone` still feeds the existing raid state and has no collision layer. Raid combat and saved defense state are separate from the old drawing. However, the old tower marker at `(136, -49)` visibly overlapped Water Site at `(120, -60)`, and world bars pointed to an invisible wall. This was a misleading presentation, not a demonstrated physical blocker or broken raid ledger.
- Wall work and labeled wall HP now appear above the existing defense caretaker when the old wall is hidden. A temporary, collision-free tower marker is at `(250, -220)`; it shows a scaffold during construction and the completed tower afterward. The point is on authored land and was checked against all currently accepted legacy site offsets. Neither the marker nor indicator is saved; no raid costs, timers, combat or save fields changed.
- A full-inventory refund can leave a cancelled tower's `_work_kind` in the ledger until its paid materials are returned. The scaffold and world progress no longer imply that this stopped work is active, and City Management says `Refund pending`. Attack/looting still shows wall HP. The existing refund transaction and saved materials remain unchanged.
- An actual old-save regression was reproduced: on `bdf5dd9`, `(0, -270)` was walkable ground; on `2509d63` it became the moved home doorway. Continuing a city save from that position entered the home without player input. The city-specific door now ignores the restored overlap until that player exits, then uses the normal entry trigger. The saved position and file bytes are unchanged; other doors and the checkpoint schema are untouched.
- Workshop plot/worker-entry and storage/delivery coordinates were retained. No access or save blocker was found in the independent static review; walking tests below exercise both workshop menus and City Storage.

## Verification

Tests used disposable XDG profiles, never the laptop or a player save. Godot `4.6.3` was available; the repository targets 4.5.x, which was not available here.

- Real-input New Game walk reached both uncleared workshop interactions, both completed workshop production menus (completed phases were fixture-set), City Storage, the tower position, a moved date palm and the home; 1,900 world units walked.
- Real menu Continue: a checkpoint written by the earlier `bdf5dd9` layout at `(0, -270)` reproduced the unintended home entry before the fix. With the fix, Continue and a repeated load stay at the exact city position without rewriting the checkpoint; walking out and back enters home normally.
- A half-built watchtower checkpoint written by `2509d63` loaded on the fix. It restored the scaffold, paid materials and timer; a simulated attack showed wall HP while construction remained paused. A real full-inventory refund failure retained its payment through save/load, showed `Refund pending`, and returned the materials once after capacity was restored. Restoring the original job and finishing it charged nothing extra; a fresh process restored the completed tower.
- Defense dialogue, raid UI, improvement/refund, raid expedition, recovery, looting, composition, wall work, city save, sleep/save, scene transition, storage transport, older in-flight hauler Continue, and resource Lab write/read/arrival passed. Independent read-only reviews covered raid and workshop/storage/save risks; root reviewed the final diff.
- Graphics captures: `/workspace/tip-raid-review-20261105/reviewed-visual/` (construction, scaffold, completed tower and attack HP); `/workspace/tip-raid-review-20261105/refund-ui/watchtower-refund-pending.png`; prior appearance under `/workspace/tip-raid-review-20261105/before/`.

## Remaining limitations

The new wall and final tower locations are not designed yet. The old wall remains invisible, so defense must be understood through the caretaker and City Management. The temporary tower is east of the initial camera view; the walking test reaches it, but human review should assess discoverability and placement. Anchors are chosen when the city scene initializes; a future runtime toggle for wall visibility would need to refresh them. Only the first of the four authored property markers is currently bound to a house. No real player save or unsaved laptop editor state was inspected.

Both cross-version tests require an isolated profile and their writer on the stated older revision. Their two fixture files were copied into detached cloud checkouts solely to produce the checkpoints; the reader ran on this branch.
