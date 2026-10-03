# Main-map production audit — 2026-10-03

Baseline: c7d0a4e, feature/process-workshop/main-map-access.
Scope: testing and reporting only; no gameplay, balance, economy, or map edits.
Overall: PARTIAL — normal startup reaches held wet bricks, but cannot unlock them without a Shekel source.

## Runtime results

Godot 4.5.1, GL Compatibility, 1200x675 window / 400x225 viewport.

| Test | Result | What this proves |
| --- | --- | --- |
| NormalStartProductionAudit | Expected blocker reproduced | Current ContentScene, empty personal Inventory, normal Laborer hire, earned construction materials, clearing, building, deposits, production, failed fee payment |
| MainMapHaulerStartTest | PASS | Normal Laborer/Hauler hiring, one starting city Cart, explicit Equip, Wood Daily delivery, E withdrawal, equipment ownership and reload |
| MainMapWorksitesTest | PASS | All five current-map sites, output identity/conservation, stockpile withdrawal and inventory edges; simultaneous hauling portion uses test workers |
| CurrentMapFundedProductionTest | PASS | Two complete production cycles on current ContentScene using explicit fixture supplies, 100 Shekel and a fixture Laborer; drying yard construction/upgrade, fees, output withdrawal and cancellation |

## Normal-start observations

No money, resources, or workers were granted by the new normal-start audit.
The supplied city Cart remains the approved normal startup behavior.
The player earned 9 Wood, 24 Reed and 18 Clay through three-hour Hourly sessions.
Worker clearing completed after 180 minutes; building consumed the existing requirements
and completed after 4320 minutes. The hired Laborer was released for production.

Surplus construction stock was deposited, followed by six Straw and six Water for two
recipes. Production started with free stock Wood 3, Reed 16, Clay 6, Straw 6, Water 6.
The real hired Laborer produced 17 wet bricks, retained as Held Output.
The player's Shekel balance remained zero. Clicking Pay returned:
"Not enough currency to pay this output fee."
The wet bricks stayed held and free wet stock remained zero.

This passing diagnostic means the blocker was reliably observed; it does NOT mark the
normal production loop complete.

## Findings

1. Normal Shekel access is the main blocker. Shaping has a 5-Shekel output fee and drying
   a 2-Shekel fee per batch. No working income route was exercised or supplied by this
   map audit. Starting inventory is empty; current-map content does not supply normal
   money. An approved earning/supply rule is needed before claiming a self-contained loop.
2. Actual worker output may be below the recipe's nominal 20. Current output code applies
   satisfaction and reliability multipliers. A 0.85 satisfaction multiplier yields 17 on
   a successful reliability roll. The run observed 17; resolved citizen stats were not
   separately logged, so that exact cause is a code-supported inference.
   Drying requires 20 free wet bricks per batch. A single 17-brick lot is insufficient
   even after payment; another shaping job is needed. This follows current rules and is
   not treated as a newly proven defect.
3. Depositing every harvested item can fill workshop storage enough to reject production.
   An exploratory run deposited 33 Water and left only 46 capacity; start did not succeed.
   The precise rejection was not logged in that run. Source inspection shows the output
   capacity guard in WorkShop.start_job_from_storage; depositing only needed amounts
   enabled the subsequent run. The first-run cause therefore remains an inference.
4. Existing ObjectDB shutdown warnings and 15 retained resources appeared in all final
   runs. No new script errors appeared in the final passing runs.

## Test-development failures retained as evidence

The initial exploratory normal-start run assumed production had started, then attempted
to access a nonexistent output card. Its subsequent nil/index errors belonged to the
new audit harness, not demonstrated gameplay crashes. The harness now stops on a failed
start and logs the actual start error.

The next run incorrectly asserted the fixture's exact 20-brick output for a real hired
worker. The observed output was 17 and fee rejection already worked. The audit assertion
was corrected to accept the existing variable output behavior without changing worker
stats or gameplay rules. The final run passed and reproduced the fee blocker.

## Limits

- Automated interactions use E events and existing UI button signals; the player is
  teleported to interaction points. This is not a keyboard-only navigation/pathfinding test.
- Clock advancement shortens waiting. Existing player-needs debug protection remains on.
- A fixed random seed is used for the production result; worker stats remain unchanged in
  the normal-start audit. The funded two-cycle fixture explicitly sets worker stats.
- Hauling and normal-start production are separate runs, not one continuous no-debug
  journey through every requested step.
- Two full cycles are proven only with fixture funding/materials/worker, not normal economy.
- Save/load to disk, long-term food/clothing/wages balance and mobile were not tested.
- Existing UI overlap/readability remains deferred.

## Changes for repeatability

- Added normal_start_production_audit.gd/.tscn.
- Added current_map_funded_production_test.tscn.
- Added an optional authored_map_scene export to the existing mudbrick_player_flow_test.gd;
  its old fixture remains the default.
- No gameplay or economy changes; no commit/push performed for this audit.

Rendered evidence inspected:
- normal-start-payment-blocked.png: 17 locked wet bricks and the currency rejection.
- mvp-free-sun_dried_mudbrick.png: funded fixture's finished output after two cycles.

Evidence folder:
C:/Users/Hendro/.codex/visualizations/2026/09/26/01a0dc60-e89d-7533-abe7-945885d9db59

Next recommendation: define and implement ordinary Shekel access, then retest the entire
continuous route with hired workers and variable yield, including enough wet bricks for
two drying batches. Do not silently grant currency or change fees/yields to make it pass.
