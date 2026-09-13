# Clay worksite Nightmare round trip

Date: 2026-09-07
Status: PASSED — NEEDS HUMAN REVIEW
Branch: feature/process-workshop/clay-worksites
Risk: LEVEL 2 fixture integration of the existing approved collapse/Nightmare systems.

The user reported the worksite panel appearing between the interrupted-work message and
the Nightmare transition. The fixture also lacked the NightmareWorld instance sought by
Player._enter_nightmare().

The fixture now closes the worksite panel while its interruption cover is still fully black.
It restores scene processing so the existing faint sequence resumes, then retains its cover
until SceneTransition's overlay is opaque. It removes the local cover at that handoff, avoiding
the visible worksite/menu flash. Normal successful work keeps its original fade.

Added the existing NightmareWorld scene at the same off-map coordinates used in content_scene.
Existing NightmareWorld captures the exact player position, transfers to its spawn, and
returns to that position after escape/timeout and Continue. Stock/output remain in the same
fixture. No Player, NightmareWorld, SceneTransition, HUD, condition tuning or production-scene
implementations changed. The user's fatigue=0.88 scene override and editor formatting remain.

Existing consequences are reused: Fatigue recovery 0.30 (Energy +30 percentage points,
clamped), Hunger cost 0.20 plus hunger accumulated during Nightmare world-time advancement,
and existing Focus recovery. No duplicate condition charge/reward added.

Modified: fixture script and scene.
Created: test_scene_clay_worksite_nightmare.gd/.tscn and this report.

Validation:
- ClayWorksiteNightmareTest passed headless and graphical at 1200x675.
- Both escape handler and actual timer expiration were exercised, including Continue.
- Per-frame checks keep interruption cover opaque until the global handoff; panel is closed.
- Nightmare spawn, exact return position, playable movement, HUD/time restoration, existing
  fatigue recovery/hunger cost, and stock survival are asserted.
- Nightmare rendered screenshot reviewed.
- Existing gathering, inspection and condition HUD regressions passed.
- git diff --check clean. Existing certificate/shutdown resource warnings persist.

Manual: F6 test_scene_clay_worksite.tscn, approach a site, E, Start Work with the retained high
Fatigue setting. After the interruption, enter Nightmare, find the exit or let time expire,
then press Continue on its result. Verify return to the original spot and restored Energy.
No save/load or Android claim. No commit, push or merge.
