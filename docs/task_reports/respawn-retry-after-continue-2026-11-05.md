# Respawn retry after Continue — 2026-11-05

Based on `b97b02e2d1afe91d0050459577929ed1a9224194`. This follow-up is local for review; it has not been pushed to the shared branch.

A transient retry throttle stored the last failed or successful respawn attempt only in the live worksite runtime. Loading an older checkpoint restored the game clock and deposit deadline but retained that later attempt. The empty deposit could then wait until 60 minutes after an attempt belonging to the discarded future, even if its saved deadline had passed and a safe test point was free. No inventory or City Storage amount was lost or duplicated by this particular issue. An isolated probe confirmed the condition using a fixture timestamp seven days beyond the saved deadline; the deposit stayed empty at its deadline although the candidate was clear.

The fix clears the transient retry cache when resource offsets are restored. The checkpoint's stock, saved random deadline, assignments and earned output remain unchanged. A subsequent relocation still performs the usual safe-point and route checks; if a point remains blocked, the ordinary 60-minute retry rule continues to apply.

`FiniteResourceSitesTest` now includes a saved waiting deposit, a simulated later attempt, Continue, the unchanged deadline, and an actual relocation when the deadline is reached. The older commit failed the isolated stale-retry probe; the fixed branch passes the expanded finite-site test. Additional save migration, full city save and city/home Continue regressions were run using isolated data and Godot 4.6.3. Laptop testing with the project's Godot 4.5.x target remains open.
