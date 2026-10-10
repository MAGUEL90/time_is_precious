# Raid cycle validation — 2026-10-10

Baseline: a3c9811, feature/time-world/raid-mvp; clean working tree.
Scope: validate preparation, expedition, looting, recovery and mixed composition before city progression. No gameplay changes.

Godot 4.5.2 headless scenario results:
- RaidExpeditionTest: PASS after updating its stale display-label expectation from Wood Log to Wood. Includes main-map construction/quotes, travel/warnings, pause and scene transitions.
- RaidLootingTest: PASS (capacity/rate, stock removal, breach satisfaction and result records).
- RaidRecoveryRegressionTest: PASS (repair/rebuild, scheduling and repeated outcomes).
- RaidCompositionRegressionTest: PASS (approved stage bounds, mixed-party strength/travel and departure snapshots).

The original expedition failure was a stale text assertion introduced by the previous dialogue polish. Production costs/item IDs were unchanged. Existing native visual checks remain documented in 2026-10-10-city-hub-polish.md; this pass did not repeat graphical testing.

Status: PASSED — NEEDS HUMAN REVIEW. City progression requires approval of its new scoring/penalty values before activation.
