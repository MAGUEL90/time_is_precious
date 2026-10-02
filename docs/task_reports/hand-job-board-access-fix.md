# Hand-job Board access fix

2026-09-28, feature/process-workshop/main-map-access. Authorized targeted fix;
existing uncommitted work preserved. No commit/merge.

The hand prompt used Area2D body overlap, but has_player_access additionally
required the Player origin inside the Board rectangle. At the lower edge the
Player collision circle overlapped while its origin was outside, showing the
prompt yet rejecting E. Reproduced with Player at Board + (0, 12): the target
was active but WorkshopClearingTest failed to open the clearing menu.

Access now checks the actual Board/player collision shapes, using current global
transforms as well as the overlap list. This agrees with prompt eligibility while
still detecting departure during a paused menu, when physics lists can be stale.
No interaction range, clearing duration, material cost or worker rule changed.

After the fix, WorkshopClearingTest, WorkshopPlotAccessTest and
WorkshopConstructionUITest passed in native Godot 4.5.1 Compatibility, 1200x675.
Verified edge-position E access, player assignment and 180-minute clearing,
worker assignment/clearing, transition to build, out-of-range/modal guards and
construction menu access. Rendered clearing assignment panel inspected.
git diff --check passed. Existing ObjectDB/15-resource shutdown diagnostics remain.
Status: PASSED - NEEDS HUMAN REVIEW.
