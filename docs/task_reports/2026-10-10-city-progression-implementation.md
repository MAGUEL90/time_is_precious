# City progression MVP implementation

Branch: feature/time-world/city-progression
Baseline: 3f5dd50; working tree clean before implementation.
Authorization: user reviewed the scoring proposal, confirmed the separate branch, then instructed “oke anda bisa lanjutkan progres city”. Scoped gameplay integration; no other balance changes.

## Behavior

- Session city ledger under WorkStateRuntime: level 1, progress 0–100.
- Daily settled resident cohort earns +5 each for all food fulfilled, all clothing fulfilled, average satisfaction >=70%. Zero settled residents earn no bonuses. Linked employed residents are included; standalone workers are not residents. Applicants admitted after settlement join the following day's cohort.
- Missing/unbuilt wall costs 5 daily, independent of positive bonuses. Destroying a standing wall costs 10 once per raid; attackers entering existing ruins cannot apply another destruction penalty. Progress never goes below zero and level never drops.
- Manual Level Up at 100 increments level, resets progress to zero, selects Early/Developing/Advanced for levels 1/2/3+. Departed parties keep their strength, members and arrival. Existing Debug stage override remains until the next level change.
- City Hub shows a shared level/progress row in both tabs and Level Up at 100. Supply displays the last daily components and a short event line. Wall construction/upgrades still belong to Iddin-Sin.
- Ledger survives map changes within the running session. Disk save/load is not implemented.

## Files / ownership

New scenes/city_progression/city_progression_state.gd owns scoring, event deduplication and level changes. RaidBootstrap creates/binds it once; RaidState only adds a standing-wall breach signal. RaidUI observes the ledger and owns presentation. No new autoload, settings, plugin, external dependency or persistence schema.
New core and main-map test scene pairs cover progression and UI. Architecture/roadmap and the approved proposal were updated.

## Validation

Godot 4.5.2:
- Editor import/parser: passed, no script errors. Editor-generated project/addon import noise restored.
- CityProgressionTest: PASS; includes actual process_daily_needs consuming exactly sufficient food, all-or-nothing cohort bonuses, satisfaction threshold, empty cohort, duplicate days/breach IDs, progress floor, manual levels and departed-party preservation.
- CityProgressionHubTest: PASS under native GL Compatibility at 400x225 logical / 1200x675 window; actual material construction, both tabs, Level Up/repeated click, map reload/reused ledger/no duplicate subscription, existing party preservation, exact 15→5 breach loss, dense attack/paused-construction bounds and visible penalty feedback.
- RaidUITest, RaidExpeditionTest, RaidLootingTest, RaidRecoveryRegressionTest and RaidCompositionRegressionTest: PASS.
- Screenshots reviewed: city-progress-ready.png, city-progress-supply.png, city-progress-under-attack.png, city-progress-breach.png in /workspace/scratch. These use controlled test settlements, not a natural multi-day balance playthrough.
- git diff --check passed. Native virtual display emits its existing unsupported V-Sync warning.

An initial dense-layout assertion checked a hidden panel (raid onset intentionally closes it); the fixture now reopens the panel before measuring. The final visible panel fits. Header spacing was compacted while retaining font sizes 6/12 and the existing pixel settings.

Status: PASSED — NEEDS HUMAN REVIEW. Remaining: human balance/visual playtest; actual long-term city progression tuning and save/load remain separate work.
