# ROADMAP - Time is Precious

Last updated: 2026-10-18

## Purpose of This Document

`ROADMAP.md` is the **single source of truth for current development position, priority, and next work**.

If you or an implementation agent need to answer **"Where are we now, and what should we work on next?"**, start here.

Other documents have different jobs:

- `docs/game-concept.md` = design source of truth: what the game should become.
- `ROADMAP.md` = progress source of truth: where development is now and what comes next.
- `DEVLOG.md` = merged implementation history and playable snapshots.
- `ARCHITECTURE.md` = technical responsibilities and system boundaries.
- `docs/root-branch-map.md` = technical domain / Git branch map, not a progress tracker.
- `DEMO_DISTRIBUTION.md` = demo rollout strategy after the prototype is ready.

Do not use an old PR list, branch list, or technical root map as the main indicator of current progress.

## Current merged baseline — PR #115 (2026-10-18)

The current baseline includes PR #114 (gameplay/main integration, merge commit
`78779c4`) and PR #115 (date-palm persistence and reusable pickup sources, merge
commit `d6ea244`). The repository is on the PR #115 result; old branch and
"pending merge" notes below describe their dated checkpoints only.

PR #114 integrated the current city layout, warehouse access, raid/city
progression work, startup Continue flow, sleep checkpoints and UI consistency.
PR #115 generalized persistent pickup stock into registered city sources and
upgraded the checkpoint format to v4. It reads v1/v2/v3 explicitly; v3 palm
records migrate through the legacy six-palm adapter, while v4 requires an exact
authored source/config match. New or changed source content in a v4 save
generation still needs an explicit migration.

The Game Director reported a Windows 4.5.1 manual sleep-checkpoint/Continue
round trip with harvested palm stock restored, and confirmed
`PickupSourcesTest: PASS`. These results are recorded in
`docs/task_reports/reusable-pickup-sources-2026-10-18.md`. They validate that
checkpoint/source path, not a full fresh-start daily or production journey.

## Current validation gate — fresh-start first playthrough

Cloud Godot 4.5.1 headless now demonstrates a fresh New Game with empty personal
inventory/wallet/worker roster reaching two paid drying batches, a normal merchant
brick sale, Drying Yard level 2, sleep checkpoint and exact separate-process
Continue. Player and worker needs stay active; requests use natural RNG. The
branch fixes a detached merchant view still receiving runtime-ledger signals.
See `docs/task_reports/mvp-first-playthrough-2026-10-18.md` for runs and limitations.

**Overall acceptance remains partial:** automated workshop progression is proven
for the recorded samples, but human understanding/visuals are untested. Clothing,
shelter and Stone have no normal supply path on this map, so city level-up and
wall preparation are blocked by content/design decisions. First financing can
wait multiple merchant visits. Existing fixture passes remain separate evidence.

## Historical implementation checkpoints

The dated sections that follow preserve the scope and evidence recorded at each
checkpoint. Any old branch, local-only, pending-review or pending-merge wording
is historical; consult the current merged baseline above for present status.

### PR #115 — reusable pickup sources (merged 2026-10-18)

Pickup sources now share configurable item/quantity, slot stock and optional refill
behavior. Date palms are compatibility wrappers; their gameplay remains unchanged.
Schema v4 persists registered city sources without a six-tree writer list, and reads
v1/v2/v3 explicitly. The old six-ID list remains only in v3 migration. New content
within a v4 save generation still requires an explicit layout/config migration.
See `docs/task_reports/reusable-pickup-sources-2026-10-18.md` for usage, tests and
scope limits. The work was merged in PR #115; its prior branch-review status is closed.

### Date palm disk persistence — original v3 checkpoint (2026-10-17)

The original persistence checkpoint extended the save format to schema v3 with the
six palms' available slots, remaining refill minutes, and independent RNG state.
Continue and home sleep checkpoints use the existing city/home load path with no
offline progress. Legacy v1/v2 files explicitly start trees full with zero timer
and fresh RNG; they contain no historical tree data. Gameplay and balance stay
unchanged. Validation evidence and limitations are recorded in
`docs/task_reports/date-palm-persistence-2026-10-17.md`. PR #115 subsequently
generalized this state and advanced the active format to v4.

### PR #114 — gameplay/main integration (merged 2026-10-17)

The gameplay branch now combines the current wall/warehouse city layout with the
six Food MVP palms, relocated with Game Director approval. Both raid and date
debug controls remain available, while the later no-tooltip inventory policy is
preserved. Food values and refill timing are unchanged. At this checkpoint palm
stock/refill timers were session-only and palm views were excluded from personal
drops during handoff/checkpoint restore. PR #115 later added disk persistence.
The previous 72-hour walking results describe the old map, not these new positions.
See `docs/task_reports/gameplay-main-integration-2026-10-17.md` for the PR #114
integration evidence and its platform/playthrough limits.

## City progression MVP — merged in PR #114 (2026-10-10 implementation checkpoint)

Branch `feature/time-world/city-progression` adds session city level/progress to City Hub (C).
Settled daily resident needs grant +5 each for all fed, all clothed, and average satisfaction >=70%.
A missing wall costs 5 daily; an actual standing-wall breach costs 10 once. Progress clamps to
0–100. At 100, Level Up advances one city level and resets progress; city levels never fall.
Level 1 uses Early raiders, level 2 Developing, level 3+ Advanced for future departures only.
Existing departing parties retain their composition and arrival. The original
implementation note predated the PR #114 save integration; city progression is
included in the current city checkpoint. Current normal-start results and remaining gates are recorded above.

## Raid system — merged in PR #114 (2026-10-10 implementation checkpoint)

Approach **Iddin-Sin** inside the south wall, press **E**, advance the opening greeting, review the quote and
choose **Build** or **Repair**. Enter reveals these choices alongside **Not now**,
while the discussion panel stays visible. His world name caption is hidden; his dialogue name remains. Build/rebuild costs 10 Stone + 5 Wood Log and takes
120 game minutes. Repair costs 1 Stone per started 5 missing HP and takes 60
game minutes. Materials come from City Storage at job start; HP updates on
completion. Jobs persist across map changes, pause during attacks, and a breached
repair is cancelled with its materials refunded. Wall management remains read-only;
press C to open wall status and raid reports. Construction uses a wall/watchtower icon and progress bar in City Management and above the relevant world location. Wall HP remains a separate meter and replaces the world construction indicator during attacks. The persistent bottom-right raid panel stays hidden.

The first party departs when initial construction completes. Its composition is
rolled once at departure: Light contributes 1 strength and takes 2 travel days,
Normal 2 strength / 3 days, Heavy 4 strength / 4 days. The party travels together
at its slowest member's speed. Early parties contain 3–5 members with 5–7 total
strength; 10% of parties carry a Heavy, at most one. Detection occurs 1 day before
arrival and never shifts arrival. Three safe days follow a raid before the next
party is generated and departs. Composition survives map changes and cannot be
rerolled through Inspect, repairs or upgrades.

Every 5 active seconds the group deals max(0, total strength - wall Defend).
Wall level 1 keeps 50 HP / Defend 2; the raid still lasts at most 60 active
seconds. Reports and painted-wall visuals follow actual results.

Debug shows the departure/arrival countdown. **Next party: Early** cycles through
Early, Developing (4–7 members, 8–11 strength, 25% Heavy presence, max 2), and
Advanced (6–10 members, 12–16 strength, 45% Heavy presence, max 3). It applies at
the next departure only. City progression now selects Early/Developing/Advanced at levels 1/2/3+;
Debug can still override the next stage until a later level change. **Send raiders** starts that party's full journey during recovery; an
existing journey cannot be restarted. Wall-HP reset remains available. During
combat the effective clock is x1, with the selected speed restored afterward.
**Wall materials** tops
up only the materials missing for the next job in City Storage, for playtesting
before the map has a Stone source; it does not seed normal gameplay.
City Storage now accepts Stone and Wood Log deposits.
The left 16x16 ! button opens merchant and detected-raid notifications, replacing
the overlapping top notices. City Management colors active threats red and shows
a castle-to-raider travel bar after detection. The icon approaches the castle
using the actual remaining journey time. Routine status sentences are hidden in
City Management; attack warnings appear only during combat/looting. The red !
button gently pulses during detection/attack/looting and returns to normal afterward. Main-profile protected stock reserve is
zero. On breach, ranked looting uses the remainder of the same 60-second raid:
10 weight capacity, one whole counted item per active second, and a once-per-breach
5 percentage-point satisfaction penalty. Selection uses existing value/food value,
weight, and rarity as a tie-break. Raiders stop at capacity, the time limit, or when
nothing fits. Results record actual losses, breach/loot duration and retreat reason.

Iddin-Sin now offers Improve -> Wall Lv.2 / Watchtower, with a quote before Start.
Wall level 2 costs 20 Stone + 10 Wood Log and 240 game minutes, granting 80 HP
and Defend 3. Repair the current wall first. Watchtower costs 10 Stone + 10 Wood
Log and 180 minutes; it detects a party two days before arrival and
unlocks Inspect for detected/active raids. One project runs at a time. Breach
refunds unfinished improvements, while completed wall tier and tower survive;
rebuild restores the retained tier. A simple tower marker appears at the wall.

Inspect opens a separate panel with a card per present raider type, a replaceable
pixel icon and x quantity, plus the current phase/ETA. Back or Escape returns to
City Management; C closes both. Lost access, a new party, map exit and raid end
clear old intelligence. Fonts use 6/12 and the former oversized tooltip is removed.

Gate/collision work, scout patrols, guard posts/soldiers, weapons and
raider effects/statuses remain future work. Raid disk saving was still future
work at this checkpoint; PR #114 added raid state to the city save. Citizen flight remains
disabled. Unique equipment instances and opened food portions remain outside the
counted-stack loot API. See `docs/task_reports/raider-composition-inspect-2026-10-10.md`
for this checkpoint and `docs/task_reports/raid-mvp-scope-2026-10-05.md` for earlier scope.
## Historical Food MVP — PR #111 six-palm walking checkpoint (2026-10-05)

The approved main-map layout introduced six date palms. At this checkpoint, each
reused the pickup scene, retained independent session stock, and replenished missing slots after a random
1–18 game hours, capped at three pickups by default. Debug stock/countdown/refill
and the existing inventory consumption flow are integrated on `feature/item/food-mvp`.

A scripted 72-hour walking route passed three seeds with active needs, normal
movement/clock rates, real home doors/sleep, and 18 hours of wood gathering.
Each run ate 108 dates, produced 35 logs and retained 6–15 dates without collapse.
Travel, work and sleep are now covered together; human pacing, Godot 4.5.x/Windows,
longer sessions and wider seed coverage remain pending. Keep current food values
for review rather than treating these three samples as final balance approval.
PR #115 later added disk persistence for the source stock/timers. See
`docs/task_reports/food-walking-playtest-2026-10-05.md`. PR #111 was merged into
main; Cooking, barley and new weather rules are deferred.

## Traveling merchant MVP — merged in PR #110 (2026-10-04)

The Game Director selected the common traveling merchant as the next economy step,
with customer quests and Rare visitors deferred. The feature branch adds finite
stock, a finite Shekel wallet, buy/sell access and runtime visit continuity to the
minimal map. The approved MVP schedule starts on game day 1, repeats every three
days, and runs 08:00–18:00. Later arrival/tier rules must depend on city statistics;
those statistics and rules do not exist yet.

Prices, stock and purchase quotas are explicitly provisional playtest configuration.
Each visit now randomly selects one or two requests from wood (3–6) and dry
bricks (10–20), with fixed prices and a stable request ledger during the visit;
buying goods from the merchant never restores those quotas. Selling
personally held sun-dried mudbricks provides Shekel; at this checkpoint it did
not complete the full zero-capital workshop construction/production loop or
disk saving. Later PRs added city/home checkpoint persistence.
The fixed-profile accounting regression verifies seven logs from six hours of
wood gathering and a six-log sale for 12 Shekel. Randomized gameplay does not
guarantee that request on the first visit; the randomized ledger passed a separate
20-visit test. PR #110 later merged this MVP (merge commit `83a67f3`); the earlier
pending-review statement is historical.

The Game Director closed the merchant MVP scope: no additional request-explanation
dialogue or quest flow. Keep the two-item request pool for this MVP. Broader goods,
Rare tiers and city-stat-driven visitors remain future work. No further merchant
features are planned before review. See `docs/task_reports/merchant-mvp-closure-2026-10-04.md`.

## Player worksite energy — branch checkpoint (2026-10-04)

Manual player gathering now integrates remaining energy (derived from fatigue)
over each work minute. Confirmation shows estimated output; NPC daily production
and existing needs drain rates are unchanged. The initial linear curve is provisional.
See `docs/task_reports/player-energy-output-2026-10-04.md`. The merchant branch
now restores five main-map worksites, existing home/sleep access and Nightmare,
with needs active in both outdoor and home scenes. Resource stocks survive a
trip home within the running session. A short Trade/Leave greeting appears at every
merchant interaction. The transaction panel omits the departure schedule. See `docs/task_reports/merchant-main-map-loop-2026-10-04.md`.
Food availability remains the next balancing dependency: hunger reaches 100%
before the first sale in the measured starting route.

## Development Principle

Build a small playable prototype first.

Do not expand into large systems before the core loop is stable, readable, repeatable, and testable without developer help.

Long-term progression should also avoid becoming fully deterministic. Controlled variation can be introduced after the basic loop is stable.

# Current Position

The project is currently in **Technical Prototype -> Playable Loop Integration**.

The existing systems support the recorded normal-start workshop loop. Remaining
gates concern human readability, merchant pacing and missing supply paths for
city progression/defense; adding large systems is not the current priority.

```text
TIME IS PRECIOUS
|
|-- 0. GAME VISION / DESIGN
|   `-- Game Concept                                  [ACTIVE DESIGN / STABLE FOUNDATION]
|
|-- 1. PLAYABLE PROTOTYPE                            [CURRENT PHASE]
|   |
|   |-- A. Daily Player Loop
|   |   |-- Player home starting scene               [DONE]
|   |   |-- Home <-> city transition                 [DONE]
|   |   |-- World time continuity                    [DONE]
|   |   |-- Hunger / Fatigue / Focus                 [MVP DONE]
|   |   |-- Sleep                                    [MVP DONE]
|   |   |-- Collapse / Nightmare                     [MVP DONE]
|   |   `-- Full-loop balance and validation         [IN PROGRESS]
|   |
|   |-- B. Core Production Loop                      [NORMAL-START AUTOMATION PASS; HUMAN QA OPEN]
|   |   |-- Inventory / item handling                [DONE]
|   |   |-- Workshop deposit / withdraw              [DONE]
|   |   |-- Worker assignment                        [DONE - PROTOTYPE]
|   |   |-- Profession/resource validation           [DONE - PROTOTYPE]
|   |   |-- Start mudbrick job                       [DONE]
|   |   |-- Produce wet_mudbrick                     [DONE]
|   |   |-- Player-facing claim / continue flow      [NORMAL-START AUTOMATION PASS]
|   |   |-- Dry wet_mudbrick                         [NORMAL-START AUTOMATION PASS]
|   |   |-- Produce sun_dried_mudbrick               [NORMAL-START AUTOMATION PASS]
|   |   `-- Use final output for progression         [YARD UPGRADE / MERCHANT NORMAL-START PASS]
|   |
|   |-- C. Population / Worker Layer
|   |   |-- Citizen generation                       [DONE - PROTOTYPE]
|   |   |-- Immigration accept / reject              [DONE - PROTOTYPE]
|   |   |-- Visible city citizens                    [DONE - PROTOTYPE]
|   |   |-- Population vs employment separation      [DONE - PROTOTYPE]
|   |   |-- Resident -> applicant evaluation         [DONE - PROTOTYPE]
|   |   |-- Job Board applicant hiring               [DONE - PROTOTYPE]
|   |   |-- Hired -> assigned / unassigned lifecycle [DONE - PROTOTYPE]
|   |   |-- City daily needs loop                    [PARTIAL / PENDING BALANCE]
|   |   `-- End-to-end worker loop validation        [IN PROGRESS]
|   |
|   |-- D. Player-Facing Clarity
|   |   |-- Inventory UI                             [DONE - PROTOTYPE]
|   |   |-- Gameplay HUD                             [DONE - PROTOTYPE]
|   |   |-- Job Board UI                             [DONE - PROTOTYPE]
|   |   |-- Workshop UI                              [DONE - PROTOTYPE]
|   |   |-- Failure / missing-resource feedback      [IN PROGRESS]
|   |   `-- Production state clarity                 [IN PROGRESS]
|   |
|   `-- E. Persistence
|       |-- Runtime state across scene changes       [DONE]
|       `-- City/home checkpoint + Continue          [IMPLEMENTED; TESTED SCOPE NOTED ABOVE]
|
|-- 2. INTERNAL PLAYTEST                             [ENTRY GATE NOT YET VERIFIED]
|   |-- Complete daily loop without manual setup
|   |-- Repeatable production loop
|   |-- Condition / Sleep / Focus tuning
|   `-- Internal playtest checklist
|
|-- 3. VERTICAL SLICE                                [LATER]
|   |-- Consistent presentation
|   |-- Representative gameplay loop
|   `-- Stable test build
|
`-- 4. DEMO DISTRIBUTION                             [LATER]
```

## You Are Here

The new normal-start driver completes two drying batches, pays production fees
from earned sales, upgrades the yard and resumes after sleep/Continue. The older
main-map integration fixture remains implementation coverage only. City-level
progression uses a separate needs/wall ledger and lacks necessary supply paths.
Human readability and long-term sustainability remain unverified.

```text
Clay / straw / water
-> Player Inventory
-> WorkshopStorage
-> Assign Worker
-> Start Mudbrick Job
-> wet_mudbrick
-> CLAIM / CONTINUE PROCESS          <- CURRENT WORK AREA
-> Drying
-> sun_dried_mudbrick
-> Visible / usable progression
```

Until the fresh-start path is reviewed, avoid expanding into another large
production chain or major management feature.

## Approved Storage Integration Checkpoints - 2026-09-20

The Game Director accepted Canva slide 2 (`Storage Flow - Rekomendasi`) with permanent
city ownership: player Inventory can deposit at City Storage Area2D + E, but city stock
cannot return to personal Inventory. `docs/game-concept.md` section 20.2 is the design
authority. These checkpoints support the production loop; accepting the direction does
not mark the entire system implemented.

On 2026-09-21 the Game Director confirmed the manual deposit/no-return/food-summary checklist,
then approved the same intake restriction for players and Haulers: ready food, finished
clothing, Shekel and supported worker equipment. Raw materials, raw food and Gold Nugget are
excluded. This supersedes the previous all-registered-items intake. Old city stock is retained.
The filter checkpoint is locally validated (10 regression suites, parse/launch and rendered
UI checks). On 2026-09-22 the Game Director confirmed all three final playtest points passed,
including intake, clay Hauler choices and daily food/portions. See
`docs/task_reports/city-storage-item-filter.md`. No branch/domain transition is authorized.

1. **City ownership gate - locally validated, awaiting human review.** Remove player
   withdrawal from the city UI and reject it in the backend. Preserve physical goods,
   deposit cancellation/atomicity and worker equip/unequip. Update diagram and design docs.
2. **Hauling into the central warehouse - locally validated, awaiting human review.** The
   existing City Storage Area now exposes a Hauler destination bound to the shared stock.
   Cargo conservation, rejection/return/retry, accepted-only target/XP, UI and runtime stock
   retention are covered by the City Storage hauling regression. Storage A/B remain available;
   define their onward route before relying on them as transit. City capacity remains TBD.
3. **Location stock and workshop logistics - deferred by the Game Director on 2026-09-21.**
   City-to-workshop Hauler supply is not a prerequisite for closing this City Storage branch.
   Finish review and validation of the approved City Storage supply checkpoints first.
   Future integration adds stable location IDs,
   ownership/access checks and stock per workshop while preserving Free/Held/Pending and
   existing capacity/fee rules. City goods must not become withdrawable personal goods via
   cargo, workshop storage, fee payment or reload. Preserve personal workshop access by
   distinguishing ownership before enabling the city-to-workshop route. Define mixed-owner
   production before allowing mixed lots. Save/load must conserve the full item chain;
   the existing isolated worksite save fixture is not full-game persistence.
4. **Physical citizen supply - food and clothing human-tested; summary UI locally validated.**
   The approved food follow-up consumes ready-to-eat city items at the unchanged one point
   per unique resident/unlinked legacy worker each midnight. Retain excess as prepared
   portions; raw ingredients remain production stock. Availability, daily need and full
   days remaining now share one calculation. Daily/reentrant guards, shortages, portions,
   scene transitions and the physical menu are covered by food regressions. This central
   food checkpoint is independent of step 3's pending workshop ownership route.
   On 2026-09-22 the Game Director approved one physical clothing item per person for seven
   days, automatic replacement when expired, and an unfulfilled need when stock is absent.
   Physical issue/renewal, shortages/recovery and unique recipients are now implemented.
   Worker Hub Details exposes daily needs, remaining clothing days and actual satisfaction/
   reliability changes. Eleven targeted regression suites passed, including rendered UI
   and clothing retention across scene transitions. Canva slide 3 documents the actual flow;
   the earlier recommendation remains on slide 2. A dedicated F6 clothing fixture supports
   quick day advancement and real deposit recovery. See `docs/task_reports/city-storage-clothing.md`.
   Deposit does not convert goods to old abstract supply counters.
   The Game Director subsequently confirmed the clothing lifecycle, Details and approved
   +5/-5 satisfaction behavior worked in the F6 playtest. A Clothing Supply panel now shows
   unique people, current coverage, spare garments, people awaiting supply and additional
   stock needed. Deposit changes reserve immediately; coverage changes during the next
   daily evaluation. The eight-person/seven-garment shortage, one-item restock and 8/8
   next-day recovery passed backend and rendered UI regressions. The new summary still
   needs the Game Director's visual check. See `docs/task_reports/city-storage-supply-summary.md`.

Initial workshop construction now follows the fixed-plot MVP in game-concept section 20.1;
new city capacity values remain TBD. City food,
portions and clothing allocations currently survive scene changes within the
running game, not a restart. Workshop withdrawal rules, production values, project settings
and the existing save format are unchanged. See `docs/task_reports/city-storage-food.md`
for the food checkpoint's verification and remaining limits.

# Immediate Priority Stack

Work from top to bottom unless a concrete blocker requires otherwise.

**Current gate (2026-10-18):** review the recorded normal-start automation, then
resolve clothing/shelter/Stone scope and validate human understanding. Keep the
user-reported Windows Continue result, existing fixtures and new normal-start
journey evidence separate. No balance/content change is approved by these tests.

The dated notes below are historical integration checkpoints. Their branch and
merge status reflects the date of each note and does not replace the current
baseline at the top of this roadmap.

**Map authoring reset - 2026-09-28:** At the Game Director's request, ContentScene
now has empty tile layers using `tile_set_base_new_28_09_2026.png`, retaining
WorkshopPlot, Job Board and player/HUD support. Worksites, HomeDoor and the
embedded NightmareWorld are removed from this authoring map. The previous map
is preserved as `scenes/test_scenes/fixtures/content_worksites_map.tscn` for
production, resource and City Storage regression tests. Earlier full-map flow
results describe that fixture. See `docs/task_reports/content-tileset-reset.md`.

**Resource map reintegration - 2026-10-01:** The newly authored space now contains
Clay, Wood, Reed, Straw and Water worksites with one matching stockpile each,
using the existing Hourly/Daily inspector, resource rates, hauling and E withdrawal.
Tiles, player, both workshop plots and Job Board retain the Game Director's layout.
MainMapWorksitesTest passes actual E inspection, cancellation, three-hour work,
overflow conservation, full-bag storage guards, map reload and five simultaneous
Daily/Hauler deliveries on the current ContentScene. ResourceWorksitesTest and
ContentDepthTimeDebugTest also pass. Normal startup grants no personal materials
and hires no workers; the initial city Cart is described below. This restores material access; complete current-map production
and normal Shekel income remain separate unfinished gates.
See `docs/task_reports/main-map-worksites-reintegration.md`.

**Hauler onboarding - 2026-10-01:** Job Board now offers one Worksite Hauler
alongside the existing Workshop Laborer, through the same citizen hiring and
daily-wage rules. Reload preserves hired/dismissed identities. Haulers still
require an explicitly equipped cart before worksite assignment. MainMapHaulerStartTest,
InitialWorkshopStartTest, WorkshopHiringRosterAudit, WorkerControlTest and
PopulationEmploymentIntegrationTest pass. Following the Game Director's request
for a Cart on 2026-10-03, normal startup now supplies one city-owned Cart through
Worker Hub's existing Tool slot. MainMapHaulerStartTest also passes normal hire,
UI equip, Daily Wood delivery, E withdrawal, unique allocation, equipment retention
on reload and return to city supplies on dismissal. The Cart is supplied once per
city runtime; it is not a personal Inventory grant or automatic equipment.
See `docs/task_reports/main-map-hauler-onboarding.md`.

**Debug-assisted production retest - 2026-10-03:** The separate map Debug panel
now supplies Shekel, construction and two-cycle production kits, with opt-in
worker performance protection and a player protection toggle. Current-map testing
with a normally hired Laborer completes two production/drying cycles, payments,
yard upgrade and withdrawal. This is a debug-assisted result; normal Shekel
access and needs balance remain unfinished. See `docs/task_reports/debug-production-testing.md`.

**Content layout cleanup - 2026-10-03:** At the Game Director's request,
ContentScene now retains two workshop plots and the Job Board, with resource
sites and map stockpiles removed. WorkerRuntime preserves worker presentation
and management; uncleared plots no longer show the world debug title.
Earlier main-map gathering/hauling acceptance results describe the previous
layout, not the current map. See `docs/task_reports/content-scene-cleanup-2026-10-03.md`.

**Audit part 1 cleanup - local validation:** Obsolete old-map test entrypoints and
the inactive work-state prototype are retired. Current-map Worker Hub/Hauler tests
use `WorkerRuntime`; resource regressions retain their populated-map fixtures.
The production-chain suite preserves the rejected empty-wallet payment check.
See `scenes/test_scenes/README.md` for active entrypoints and result criteria, and
`docs/task_reports/audit-part-1-cleanup-2026-10-03.md` for validation evidence.

**Historical audit technical follow-up - 2026-10-04:** The approved parts 2–8 fixes and the
remaining clock, fade/Nightmare timing and shutdown cleanup have passed 41 unique
regression suites on Godot 4.5.2, including graphical workshop/depth checks and
real dialogue cycles. The Game Director chose to retain the minimal two-plot map.
At that audit date, normal income, full normal-game integration and real disk
saving remained separate unfinished features. Later PRs integrated the current
main map and city/home checkpoint; the 2026-10-18 audit records clean-start results.
Desktop software rendering was checked at the existing
viewport/window settings; local hardware/OS and Android playtests remain unverified.
See `docs/task_reports/audit-followup-2026-10-04.md`. Human PR/merge review is pending.

**Modal pause check - 2026-10-03:** Physical K opens Worker Hub and K/Esc/Close
release its pause on the current map, with empty and hired rosters. A separate
confirmed freeze-like case came from Work Progress (J): the map hides its
CanvasLayer for authoring, but opening only showed its child and paused the game.
Opening now shows both layers. MainMapWorkerHubTest and WorkshopPlotAccessTest
pass; the user's K-specific symptom has not been reproduced. See
`docs/task_reports/worker-hub-pause-investigation.md`.

**Historical handoff - 2026-09-26:** City Storage supply work is merged into main
through PR #105 (merge commit 2a7b773). The earlier instruction to remain on
feature/workers/city-storage-supply is historical; do not reopen that completed
branch merely because earlier checkpoint descriptions still say awaiting review.
City-to-workshop Hauler supply remains deferred.

Godot MCP is installed on the current main baseline; its editor plugin and runtime
autoload are enabled in `project.godot`. The addon includes the documented local
Godot 4.5 compatibility patch; see `addons/godot-mcp/GODOT_MCP_SETUP.md`.
The bounded ContentScene cleanup removes the empty ContentDirector, inactive root
camera and no-op root script. The Game Director accepted its playtest; automated
ContentWorksitesIntegrationTest passed. Cleanup still requires PR/merge review.

The parked feature/process-workshop/mvp-mudbrick-flow checkpoint was reviewed and its
guidance UI and playtest/regression fixtures integrated locally into main-map-access.
The original worktree at baseline 4de7d05 remains untouched. Current item-information
UI additions were preserved. Five current-version suites passed, including a new
authored-map test that builds the workshop and completes two production cycles,
upgrades the Drying Yard with finished bricks, and withdraws final output.
See docs/task_reports/mudbrick-main-map-integration.md. The Game Director approved fixed-plot, worker-built initial workshop
construction on 2026-09-26. The 2026-09-27 follow-up adds a hand prompt and required
three-hour clearing by player OR one worker, without materials, before the hammer prompt.
Clearing, construction and main-map production regressions pass; see
docs/task_reports/workshop-clearing.md. The local main-map-access branch implements
direct requirements UI, team-based construction and existing workshop access after completion.
See docs/task_reports/workshop-plot-access.md for validation. On 2026-09-26 the Game
Director approved wood/reed/straw/water sources and one initial Laborer applicant at a
physical Job Board. The subsequent correction now reuses the Clay Worksite inspector,
Hourly/Daily work, stock and hauling with per-site resource/rate configuration; the separate
Gather component has been removed. These are integrated locally; InitialWorkshopStartTest verifies an empty inventory and no hired
workers through manual gathering, hiring, construction and map reload without material
seeding. See docs/task_reports/shared-resource-worksites.md. Job Board audit confirms the original
basic hiring UI is still current; Worker Hub has no alternative applicant-hiring flow.
Historical status at the end of September: that local integration was later
merged through PR #108 and further incorporated by PR #114. Its test-owned
resources and worker do not establish the normal fresh-start route. The full
daily loop with ordinary player/citizen needs remains a validation question.

## Priority 1 - Validate Fresh-Start Production

- [x] Reach `wet_mudbrick` from a fresh normal start without supplied resources (headless).
- [x] Complete claim/payment and two drying batches with active needs (headless).
- [x] Confirm final `sun_dried_mudbrick` is stored and withdrawable; visual review remains open.
- [x] Use earned final bricks for yard level 2 and normal merchant sales.

The authored main-map integration test completes two cycles with fixture-owned
resources, a worker and Shekel. Use it as implementation coverage, not evidence
that a fresh start completes this priority. The separate 2026-10-18 normal-start
driver supplies that automated evidence; human readability remains open.

**Exit condition:** the mudbrick loop can be completed repeatedly from normal
inputs to final output without developer intervention.

## Priority 2 - Validate the Complete Daily Loop

Validate this as one continuous play session:

```text
Wake at home
-> Enter city
-> Gather / manage resources
-> Review/hire workers when relevant
-> Assign work
-> Run production
-> Manage Hunger / Fatigue / Focus
-> Advance time
-> Return home
-> Sleep
-> Continue into next day
```

- [x] No developer supplies/setup between recorded normal-start steps (automated route).
- [x] Recorded city/home transitions and separate-process Continue preserve the earned snapshot.
- [ ] Confirm Sleep and Collapse rules do not break the day loop.
- [ ] Confirm Job Board / Worker Hub / workshop state remains understandable.
- [ ] Confirm accepted residents can reach applicant/hired/assigned states through the normal player-facing flow when conditions allow.

**Exit condition:** one full in-game day feels like a coherent game loop rather than a collection of test systems.

## Priority 3 - Clarity and Failure Feedback

- [ ] Missing materials are explained clearly.
- [ ] Missing/incorrect worker profession is explained clearly.
- [ ] Full inventory is explained clearly.
- [ ] Full workshop storage is explained clearly.
- [ ] Active / finished jobs are visually understandable.
- [ ] Player knows what to do after `wet_mudbrick` is produced.

**Exit condition:** a tester can understand what failed and what to do next without reading debug output.

## Priority 4 - Condition, Worker Needs and Balance Tuning

Existing systems are MVP/prototype systems. This is a tuning and validation task, not a reason to rebuild them from scratch.

Tune/validate:
- Hunger drain.
- Fatigue growth.
- Focus behavior and costs.
- Sleep duration and recovery.
- Once-per-day Sleep rule.
- Collapse / Nightmare consequence severity.
- Citizen daily needs pressure.
- Worker satisfaction/reliability effect on production.
- Wage/economy values only after design approval.

**Exit condition:** time pressure, conditions and worker management create meaningful trade-offs without obvious exploits or opaque punishment.

## Priority 5 - Save / Load Scope and Follow-up

City/home checkpointing, sleep autosave and Continue are implemented. PR #115
persists registered city pickup-source stock, refill timers and RNG using schema
v4. The Game Director confirmed a Windows sleep-checkpoint/Continue round trip
and `PickupSourcesTest: PASS` (see the current baseline and source report above).

Remaining save work is limited to future scope such as multiple selectable slots,
other map types, and explicit migration when authored source identities or
configuration change. Do not describe the implemented city/home checkpoint as
pending or imply that arbitrary-map persistence is complete.

The implemented city/home checkpoint path has passed the scoped automated and
user-reported checks noted above; full fresh-start playthrough validation remains
separate.

## Priority 6 - Internal Playtest

- [ ] Create a short internal playtest checklist.
- [ ] Test the daily loop from a clean start.
- [ ] Record blockers, confusion, exploits, and balance problems.
- [ ] Fix loop-breaking problems before adding scope.

# Phase Status

## Phase 0 - Foundation Review

**Status: Mostly complete for the current prototype.**

Core foundations already exist or are partially implemented:
- ItemDatabase.
- Inventory and weight handling.
- WorkshopStorage.
- WorkManager.
- ProcessManager.
- Player interaction.
- World time.
- Citizen / immigration prototype.
- Population/employment state separation.
- Job Board hiring prototype.
- Workshop worker assignment prototype.
- Player condition systems.
- Home / city scene flow.

Do not reopen this phase broadly unless a concrete blocker appears.

## Phase 0.5 - Playable Loop Stabilization

**Status: ACTIVE - THIS IS THE CURRENT DEVELOPMENT PHASE.**

Goal: connect existing systems into a readable, repeatable player-facing loop.

Main remaining gates:

`human readability + merchant pacing + citizen/defense supply access`

The claim/dry chain now has separate normal-start automated evidence as well as
fixture coverage. City level-up and wall access remain blocked by missing supply;
headless checks do not establish human understanding or final balance.

## Phase 1 - Core Loop Prototype

**Status: In progress.**

Success criteria:
- Player can acquire resources.
- Player can store / move resources.
- Player can hire/assign suitable workers where required.
- Work consumes correct inputs.
- Work generates output.
- Output can continue into the next production step.
- Final output creates visible progression.
- The loop is repeatable.

Phase 1 is not complete until the final output has an actual gameplay purpose.

## Phase 2 - Population and Worker Separation

**Status: Core lifecycle prototype implemented; balance and full-loop validation remain.**

Current design flow:

```text
Migrant
-> accepted resident / citizen
-> eligible applicant
-> hired worker
-> assigned / working
```

Merged implementation now includes:
- citizen-backed population/employment states
- resident applicant evaluation
- Job Board hiring
- linked WorkerData creation
- assignment/unassignment lifecycle
- workshop assignment integration

Population status and employment status must stay separate.

Remaining work is mainly end-to-end gameplay validation, balancing, broader
professions/content, and later systemic consequences — not rebuilding the
lifecycle from scratch. City/home persistence is implemented; other save scopes
are listed under Phase 5.

Do not let Phase 2 expansion delay completion of the production / daily loop.

## Phase 2.5 - Controlled Variation Layer

**Status: Backlog.**

Long-term variation may include migrant arrival variation, applicant quality variation, resident traits, opportunity timing and small production/needs-pressure variation.

Randomness must remain readable and influenced by player decisions.

## Phase 3 - Prototype Asset Pass

**Status: Ongoing support work, not the main blocker.**

Use enough consistent art to make the prototype readable. Do not wait for final assets before validating gameplay.

## Phase 4 - Basic UI Pass

**Status: Partially implemented.**

Inventory, HUD, dialogue, Job Board and workshop interfaces exist at prototype level.
The current-playable-loop UI consistency pass was merged in PR #114:
shared small pixel fonts and disabled states,
City Hub Supply alignment, padded Inspect cards, centered physical City Storage,
bounded inventory confirmations and Job Board empty-state placement. The existing
Mesopotamian pixel style and player actions are preserved. Native visual review and
focused regressions are recorded in `docs/task_reports/2026-10-11-ui-consistency.md`;
human visual acceptance remains pending. Continue UI work when it directly improves
the current playable loop.

## Phase 5 - Save / Load

**Status: City/home checkpoint, sleep autosave and Continue implemented; scoped
Windows and automated source checks passed.**

Successful sleep now saves one checkpoint after recovery. Manual Save/Load buttons
have been removed from City Hub. PR #114 integrated the startup menu, which
provides Continue, New Game and Quit. Continue restores city/home checkpoints; New Game
requires confirmation when a checkpoint exists and archives the previous files.
The slot covers stocks, residents, jobs, construction,
progression and raids; home visits preserve the live worksite/hauling session. Loading
a sleep checkpoint returns to the saved home position and time without offline production.
PR #115 advances source saves to schema v4 and retains explicit readers/migrations
for earlier formats. Supply also displays existing Shelter capacity.
The isolated worksite prototype slot stays separate. Multiple selectable slots and
other-map saves remain follow-up work. F5 opens the startup menu; F6 runs the authored
scene directly for content editing. The main map no longer forces a day-zero merchant
in debug builds. See `docs/task_reports/2026-10-11-city-sleep-save.md` and
`docs/task_reports/2026-10-11-content-ready.md`. Full fresh-start playthrough
evidence is recorded separately in the 2026-10-18 audit.

## Phase 6 - Internal Playtest

**Status: Automated normal-start loop demonstrated; human readability, pacing and
city/defense supply decisions remain open.**

Entry gate:
- complete mudbrick chain
- coherent daily loop
- readable failure feedback
- basic condition/worker-needs tuning
- no developer-only setup required

## Phase 7 - Vertical Slice

**Status: Later.**

A vertical slice should represent the intended quality and identity of the game, not merely prove that systems technically run.

## Phase 8 - Demo Distribution

**Status: Later; planning exists, execution waits for readiness.**

See `DEMO_DISTRIBUTION.md` for channel roles and rollout details.

# Scope Guard - Do Not Prioritize Yet

Delay these unless necessary to unblock the current loop:
- another large production chain
- large NPC behavior expansion
- complex economy balancing
- full Advisor NPC / AI system
- large quest system
- large city simulation
- advanced combat
- large asset library
- advanced VFX / SFX
- marketing trailer
- uncontrolled public demo distribution

# Design Risk - Too Predictable

The game should eventually support controlled variation so players do not discover one permanently solved route.

However, do not solve this risk by adding complexity before the core loop works.

Preferred order:

```text
Stable deterministic prototype
-> readable complete loop
-> internal playtest
-> controlled variation
-> balancing
```

# Agent / Codex Working Rule

Before starting implementation, read this roadmap and identify the highest unfinished priority that the requested task belongs to.

When a meaningful feature is merged:
1. Update `DEVLOG.md` with what actually changed.
2. Update `ROADMAP.md` only if current status, priority, or a phase gate changed.
3. Update `ARCHITECTURE.md` only when technical responsibility or system boundaries changed.
4. Update `docs/game-concept.md` only when intended game design changed and the Game Director approved it.
5. Update `docs/root-branch-map.md` only when technical root/domain structure changed.

Do not copy PR history into this roadmap. PR and milestone history belongs in `DEVLOG.md`.

Do not use `docs/root-branch-map.md` as evidence that a feature is active, complete, or prioritized.

**Current implementation priority:** finish and validate the playable daily / mudbrick loop before expanding into new major systems.
