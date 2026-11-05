# Authored map presentation review — 2026-11-05

Branch: `feature/gameplay/authored-map-visible-20261105`, based on `bdf5dd9fbdd8b428b615a5cfde37c8cd996bff25` with a clean starting tree. Risk is high because the layout touches navigation and saved world positions. The session could not raise its reasoning tier as requested by the repository's escalation policy; this was reported before choosing the approach. Human review is required.

The authored map itself and its assets were not edited. The scene file's SHA-256 remains `014795f39528cd5b7ab3b244c352707d47e42f3b8462a632bbf9b16cd700bdfd`.

## Presentation and retained behavior

- New Game starts on the authored road, so the vertical road, two branches and four property markers are visible together. The home and its return spawn move north; all six date palms move to the sides while keeping their pickup-source identities and depletion state.
- The old wall artwork is hidden, but its node, tile data, raid state and management access remain. The old City Storage building artwork and its solid building shape are hidden/disabled; its labeled board, interaction, stock and delivery endpoint remain at the original coordinates.
- Workshop plots, the citizen-house plot, worksite origins, storage endpoints and their IDs stay in place, preserving targets in saves with workers or cargo in motion. The forced detour through the former visual gate is removed; routes still avoid actual collision geometry.
- The Resource Respawn Lab uses the same city scene. Its controls start collapsed behind **Open Lab Controls**, and can be reopened and closed without resetting the test state.

## Verification

All tests used disposable XDG profiles and Godot `4.6.3` in this cloud environment; no laptop or player save was modified. The repository baseline targets Godot 4.5.x, which was not available here.

- Rendered the actual New Game city, the authored map comparison and the Lab with controls both closed and open. Captures: `/workspace/tip-authored-map-review-20261105/after/`; baseline comparison: `/workspace/map_visual_audit_capture_20261105/`.
- New Game walk: reached and opened City Storage, gathered dates from a moved palm and entered the moved home using normal movement and interaction (`AuthoredLayoutAccessTest: PASS`, approximately 617 world units walked).
- Walked to ground pickups at all nine initial sites and checked worker routes to both slots (`ReviewResourcePathsTest: PASS`, approximately 1,166 world units). Authored house binding, built-house navigation, initial site catalog and defense dialogue also passed.
- City save round trip, older baseline city save read by this branch, actual sleep/save and return, scene transition, and workshop keeper lifecycle passed. A baseline workshop save with a worker travelling and a baseline home save with a loaded storage-to-storage hauler both continued on this branch.
- Lab write/read/arrival and all four resource-type tests passed. A pending timer and worker saved by the baseline were continued on this branch; the worker physically reached the relocated test point. These test slots include a sentinel verifying the normal player slot remains untouched.
- Three existing fixtures failed on the unchanged baseline. Their checks were retained and updated: wait for deferred navigation before home handoff, use the configured wood capacity in the conservation assertion, and broadcast a fixture's explicit clock time. Their corresponding sleep/save, workshop and site-arrival tests then passed on this branch.

## Review limitations

- Only the first of the four authored property markers currently has a citizen-house gameplay binding; the other three remain visual markers. Existing workshop plots remain north of the authored lots to preserve in-flight save targets.
- The raid/wall system is still active even though the old wall is invisible; its progress indicator or a built watchtower may appear at the old wall location. A new wall layout and final resource relocation locations need a separate design decision.
- The city storage is temporarily represented by its board and label, and the moved home is north of the initial camera view. The placement should be reviewed for discoverability. Straw's existing compatibility site is unchanged; farming and final site placement are separate decisions.
- Existing saves retain the player's saved world position and ground drops. Moved palms retain their slots and timers but appear at their new positions. A save at any newly occupied doorway deserves human playtesting; the original player files were not inspected or altered.
