# Character needs MVP — 2026-11-01

Branch: `feature/gameplay/character-needs-20261101`

Baseline: `f99b6636f7c9e0b97d3853d121ec3306745157bd`

Scope: player condition, existing HUD, negotiation access and checkpoint compatibility. The Game Director approved the gameplay change and temporary negotiation suspension.

The player keeps Hunger and Fatigue, displayed as Satiety and Energy. Existing time drain, food effects, sleep recovery, manual gathering, and Nightmare's Hunger/Energy consequences remain unchanged. Critical Fatigue is the sole condition trigger for collapse. Focus no longer affects gameplay or appears in the status displays. Galsal's negotiation choice is absent, and the former callback safely does nothing; ordinary conversation and the existing direct contract choice remain available. Citizen and worker needs, Satisfaction and work rules were not changed.

Checkpoint schema 9 excludes player Focus. Versions 1–8 validate their original Focus value before omitting it from staged runtime state. Loading does not rewrite the source file. On a later successful save, the existing primary/backup rotation keeps the previous primary as `.bak`; subsequent saves follow the existing rotation. Invalid or externally changed files continue to block overwrite. A schema-9 save is not forward-compatible with an older executable that only understands schema 8.

## Validation

Godot `4.5.1.stable.official.f62fdbde1`, Linux cloud, isolated project copy and user-data directories. The official engine archive was used only as a temporary test tool. Headless editor import and a 180-frame main-project launch exited 0 without script errors.

- Player/UI: `ConditionHUDRegressionTest`, `ClockStateBroadcastTest`, `PlayerEnergyOutputTest`, `ClayWorksiteGatheringTest`, `WorksiteIncomeTest`, `PlayerActionLocksTest`, `ClayWorksiteNightmareTest` and `PlotCollapseHandoffTest` passed. The coverage includes actual date consumption, no-effect repeat, fed/hungry sleep and repeat refusal, Energy-based output, repeated Nightmare escape/timeout and interruptions to work and movement locks. The HUD test also checks the three remaining labels align with their indicators.
- NPCs: `NegotiationNeedsTest`, `DialogueRuntimeRegressionTest` and `WorkshopKeeperIntegrationTest` passed. The negotiation test exercises the compiled Galsal choices, a normal direct contract, casual dialogue and repeated disabled-callback attempts.
- People: `PopulationEmploymentIntegrationTest`, `CityFoodDailyTest` and `CityClothingNeedsTest` passed.
- Persistence: `CitySaveFileTest`, `CitySaveValuesTest`, `CitySaveTest`, `CitySaveEconomyTest`, `CitySleepSaveTest`, `PickupSourcesTest` and `WorkshopArrivalSchema8Test` passed. These cover valid version 1–8 shapes, legacy Focus boundaries and invalid values, unchanged live state and disk on rejection, repeated loads, checkpoint rotation and new schema 9. Expected warnings were emitted for deliberately invalid/changed checkpoint cases.
- Real separate-process Continue passed for city and home checkpoints written by the unchanged baseline's schema-8 executable, and for newly written schema-9 checkpoints. The old city primary remained unchanged through Continue and was retained as the ordinary backup on the next save. The five `ContractContinue` phases (`write`, `read`, `readrenew`, `legacy-read`, `legacy-renew-read`) passed, including a schema-6 contract fixture.

Two existing interruption tests failed on the unchanged baseline: the worksite fixture expected gathered stock despite allowing too little productive time, and the plot fixture omitted the keeper greeting added since that test was authored. Their fixture flows were updated; both now pass while checking the interrupted work and restored movement.

Two older payroll fixtures still fail on the unchanged baseline and on this branch: `RenewalContinue write` expects pending hires under the superseded hiring flow; `PayrollContinue write` expects both applicants to be hired without the current wallet contract. No payroll logic was changed. Later phases of those two fixtures were not run after their setup failed; the current prepaid-contract continuation suite above passed.

No rendered or manual gameplay review, Windows test, or Android test was performed. Test artifacts and checkpoint files stayed in temporary isolated data directories; no personal save or unrelated checkout was changed.
