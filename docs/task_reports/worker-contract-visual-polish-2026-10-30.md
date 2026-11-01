# Worker contract visual polish — Job Board

Status: **PASSED — NEEDS HUMAN REVIEW** for the two Job Board presentation changes below. Baseline and remote target at start: `126825ae840a153918b96ec06a10c02e11012129`; branch `feature/ui/worker-contract-polish-20261030`. The original `work` checkout contained an unrelated `project.godot` edit and generated import/UID files. Work was isolated in a clean checkout and those original files were preserved. The session runtime did not expose a model name that could independently verify the requested Terra 6.1 Max configuration.

## Scope and changes

- `scenes/ui/job_board_ui/job_board_candidate_card.tscn`: reuse the existing highlighted brown-panel atlas for candidate checkbox hover, including the checked-hover state, and make its keyboard-focus outline visible. The existing checkmark remains in place.
- `scenes/ui/job_board_ui/job_board_ui.tscn`: reuse that atlas for a visible focus outline on the contract-duration selector. The previous inherited focus style was empty. No card dimensions, control actions or contract data changed.

The E prompt and game settings were untouched. This pass does not change contract prices, 3/6/9-day options, schedules, arrivals, production, needs, satisfaction, professions, ownership, fees, save schema, storage filtering or warehouse access. The four deferred gameplay issues remain out of scope.

## Verification

All runs used Godot `4.5.1.stable.official.f62fdbde1`, isolated XDG profiles, the project's `400×225` logical viewport and a `1200×675` window. GL captures used Compatibility/llvmpipe; the saved 1200×675 evidence is nearest-neighbor scaling of the captured logical viewport, not a desktop screenshot. The standard VSync-unsupported warning occurred in graphical runs.

- Focused rendered fixture: **PASS**, including actual mouse hover for selected and unselected candidates, Tab navigation to the duration selector, long-name ellipsis with the full name retained in the selection tooltip, no overlap with role/control, empty state, four open/close cycles without duplicate toggle connections, unchanged wallet and worker list, and unchanged 3/6/9 options. This is an explicitly seeded fixture, not normal play.
- `test_scene_content_prepaid_ui.tscn`: **PASS (0 failed)** with GL rendering, including quotes, selection, atomic hire and closure.
- `test_scene_prepaid_contracts.tscn`: **PASS (0 checks failed)** headless.
- Headless normal project launch (`--quit-after 180`) and editor import: exit 0 without script/parse errors.
- Same-state logical-pixel comparisons: normal panel unchanged; hover changed 134 pixels within the checkbox; candidate focus changed 52 pixels within the checkbox; duration focus changed 164 pixels within its control. Screenshots were visually inspected. The initial focus style attempt changed no pixels and was replaced before acceptance. An early fixture incorrectly assumed duration followed the second candidate immediately in Tab order; the corrected test verifies it is reachable through the actual order. One earlier overlapping run logged an MCP listener port conflict; the accepted runs were sequential and did not contain that error.
- `git diff --check` and manual diff review: only these two production scenes and this report are intended for the commit.

Screenshot upload to Library failed before an upload began because the Library helper could not reach its hosted tool listing. The before/after images remain in the cloud workspace for this session. They require human visual review; this fixture is not evidence of a normal playthrough or Android behavior.
