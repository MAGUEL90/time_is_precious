# ARCHITECTURE - Time is Precious

Last updated: 2026-09-05

## Purpose

This document is the architectural source of truth for **Time is Precious**.

It defines technical responsibilities, ownership boundaries, state separation, and integration rules. It does not replace `docs/game-concept.md` for design intent or `ROADMAP.md` for current priority.

## Core Game Identity

Time is Precious is a 2D top-down management RPG focused on:
- Time pressure.
- Resource management.
- Work delegation.
- Production chains.
- City growth.
- Player home / settlement progression.
- Variable progression between players.
- Long-term AI-assisted unique NPCs that stay controlled by game systems.

## Current Architectural Priority

Do not expand into large systems too early.

Stabilize this core loop first:

```text
Gather resource
-> Store resource
-> Hire / assign suitable worker when needed
-> Start work/job
-> Produce output
-> Claim or continue processing output
-> Use output for progression
```

Current player-facing workshop foundation includes:
- Inventory-to-workshop transfer.
- Workshop deposit and withdraw.
- Worker assignment UI.
- Profession/resource validation.
- Mudbrick job start from workshop storage.
- World-time-driven work progression.
- NPC-produced output entering `WorkShopStorage.claimable_outputs`.

The current production architecture blocker is not job start. It is the player-facing continuation after `wet_mudbrick`: claim/route -> drying -> `sun_dried_mudbrick` -> visible progression.

## Source-of-truth roles

- `docs/game-concept.md` = intended game design.
- `ROADMAP.md` = current progress and priority.
- `ARCHITECTURE.md` = system responsibilities and boundaries.
- `DEVLOG.md` = merged implementation history.
- `docs/root-branch-map.md` = technical domain and branch taxonomy.
- Current source/scenes = implementation truth.

## Important Architecture Rule: Population != Employment

Do not mix population logic with employment logic.

An NPC can be a resident without being a worker.
An NPC can be hired but not assigned.
An assigned worker may not currently be executing a job.
An NPC consumes city needs because they are a resident, not because they are hired.

### Population / Citizenship Layer

Conceptual statuses:
- `migrant`
- `resident`
- `rejected`
- `left_city`

Responsibilities:
- whether the NPC belongs to the city
- whether the NPC counts toward population
- whether the NPC consumes city stock / resident needs

### Employment / Worker Layer

Conceptual statuses:
- `unemployed`
- `applicant`
- `hired`
- `assigned`
- `working`

Responsibilities:
- employment eligibility
- Job Board applicant visibility
- hiring
- workplace assignment
- active work execution

### Current lifecycle implementation

Merged prototype implementation now supports the main lifecycle:

```text
Accepted resident
-> daily applicant eligibility evaluation
-> APPLICANT
-> Job Board hire
-> linked WorkerData
-> HIRED
-> workshop assignment
-> ASSIGNED
-> job execution / worker runtime state
```

Key responsibilities:
- `CitizenData` owns population and employment status.
- `CitizenManager` owns the runtime citizen registry and applicant-state transitions.
- `WorkerDatabase` owns WorkerData lookup/creation plus hire/assign/unassign integration.
- `WorkerData` represents worker-specific work data while resolving linked citizen information where appropriate.
- Workshop assignment must update the linked citizen employment state rather than keeping an unrelated parallel flag.

Legacy worker compatibility may exist, but new work should not create additional disconnected employment authorities.

## Citizen / Immigration Layer

- `CitizenGenerator` creates prototype citizen data.
- `CitizenManager` stores the runtime citizen registry.
- `ImmigrationManager` evaluates immigration and manages pending batches.
- Accepted immigrants become residents/citizens.
- Rejected/left citizens must not consume city resources.
- `CitySpawner` / `CitizenActor` represent resident data in the world.
- Visual presentation should stay separate from gameplay authority unless an approved trait system intentionally connects them.

Current immigration approval remains batch-based unless design explicitly changes it.

## Applicant / Job Board Layer

For the current prototype, applicants originate from accepted residents.

```text
Resident
-> needs / eligibility check
-> Applicant
-> Job Board
-> Player hires
-> WorkerData linked to citizen identity
```

Do not spawn unrelated external applicants unless design explicitly introduces a separate applicant source.

Applicant evaluation is a gameplay-system responsibility, not a UI responsibility. Job Board UI displays and triggers approved actions; it must not invent eligibility rules.

## Worker Assignment Layer

Assignment is separate from hiring and separate from active job execution.

```text
HIRED
-> player assigns to workplace
-> ASSIGNED
-> job starts
-> active work runtime
```

Removing a worker from the workplace should return the linked employment state to the appropriate hired/idle state rather than deleting citizen identity.

Workshop UI must not become the authoritative storage location for worker employment state.

## City Needs Layer

Food/basic need consumption depends on population state.

Correct conceptual rule:

```text
if population_status == resident:
    consume_city_stock()
```

Incorrect:

```text
if is_hired:
    consume_city_stock()
```

Current daily needs/satisfaction/reliability behavior exists at prototype level, but balance remains unfinished.

## Workshop / Production Responsibilities

The workshop production family is currently earth/clay/construction-material work.

Current intended flow:

```text
Manage Storage
-> Deposit raw materials
-> Assign worker
-> Choose/start relevant job
-> Validate profession and resources
-> Job consumes workshop storage
-> World time advances work
-> NPC output enters claimable escrow
-> Player claims output or routes it forward
-> Further process where relevant
```

### Storage separation

`WorkShopStorage.items` and `claimable_outputs` are different concepts.

- Stored items = normal workshop inventory available for actions/processes.
- Claimable output = NPC-produced output awaiting player claim/routing.

Withdraw must not silently bypass claimable escrow.

### WorkManager

`WorkManager` is responsible for work orders, input consumption, timing, worker execution state, and routing output according to the work flow.

It must not become the authority for unrelated city population, UI layout, quest logic, or global economy design.

### ProcessManager

`ProcessManager` handles process/batch-style transformation logic. Future drying integration should reuse this responsibility where appropriate rather than embedding a second process engine inside UI scripts.

### WorkStateRuntime

Current project setup includes a runtime work-state bootstrap/autoload path so work/process systems can remain synchronized with world-time changes across the player-facing flow.

`TimeComponentManager.emit_time_signal()` publishes the current `time_changed`
snapshot for synchronization. Only elapsed time through `advance_one_minute()`
emits `minute_changed`, `hour_changed` and `day_changed`; refreshing a snapshot
must not charge Player needs or simulate another day.

Do not add duplicate scene-local bootstrap instances without a specific architectural reason.

Each authored WorkshopPlot now uses its unique exported `plot_id` to retain a construction
state under this runtime host. `main_workshop` retains the original `MainWorkshopConstruction`
node; other identities use `WorkshopConstruction_` plus their SHA256 hash. Each state owns
its material transaction, clearing/build deadlines, progress and worker order ID. Authored
IDs must be unique and stable; unnamed fixtures fall back to the node name, with
`WorkshopPlot` retaining the original primary identity. Completed workshop production and
storage still use shared services; separate construction does not imply separate inventories.
The map owns proximity, construction UI and the completed WorkShop instance. Scene changes
replace map nodes but retain construction state; disk persistence is not implemented.
Construction has no production-item output or escrow and does not create a WorkManager
production order. Existing WorkManager and ProcessManager retain workshop production authority.

### City Storage and equipment supply

Content Worksites reuse one `CityToolStorage` child of the existing `WorkStateRuntime` host.
It owns physical item stacks, unique equipment units, and their worker allocations for the current game session,
so stock deposited from persistent player Inventory is not discarded on a home/city
scene change. Isolated worksite fixtures still create their own scene-local providers.

`Worksites/CityStorageArea` is a reusable Area2D access point. Player interaction uses the
existing nearest-interactable selection and E input. Opening and confirming a transfer both
require the player inside this area's collision shape. Its modal reuses `city_storage.tscn`
and the Workshop quantity-selection UI; closing, leaving range, or deleting the area restores
movement and the prior tree pause state. Inventory Send and right-click city deposits are removed.

The area's child `DeliveryPoint` instances the existing `StorageDestination` and binds to
that same runtime CityToolStorage. It is discovered as `City Storage` by the existing Hauler
destination selector alongside Storage A/B; its arrival marker is at the physical entrance.
`has_capacity_for()` and `try_add_item()` validate and receive eligible physical cargo
directly into city stacks/unique equipment, without touching or signalling player Inventory.
Receipts reject invalid quantities/items, corrupt counted stacks and reentrant mutations;
successful receipts notify city observers once after installing the complete state.
City capacity is currently unbounded; a numeric limit remains TBD.

`CityToolStorage.accepts_item()` is the common item policy for deposit choices, whole-batch
deposit validation and Hauler preflight/receipt. It accepts registered ready Consumables with
positive food value, the explicit existing finished-clothing IDs in `CLOTHING_ITEM_IDS`,
`shekel`, and `SUPPORTED_ITEM_IDS` worker equipment. Clothing uses an explicit list because
most existing garment resources still carry the generic Resource category. This does not
change their values or worker equipment support. Gold Nugget, raw ingredients and materials
are rejected. Existing registered raw stock stays visible and preserved; intake rules are
not a migration or a player withdrawal path.

The shared worksite adapter disables City Storage for unsupported output, exposes a reason
in the Hauler selector, and revalidates assignment and Start. Other storage providers keep
their own acceptance/capacity rules. The transport's existing pre-pickup and unload checks
retain responsibility for conserving source output and cargo if a standing route is stale.

Hauling keeps the existing three-item trips, next-day schedule and accepted-delivery target/XP.
Pickup moves worksite output into route cargo; only an accepted unload adds city stock and
clears cargo. Rejected in-flight cargo returns to the worksite and retries through the standing
plan when the endpoint is available. Storage A/B retain their independent authored stock and
capacity; automatic onward routing is not implemented.

Selecting a worker equipment slot reuses the City Storage panel for Equip/Unequip only,
retaining the selected worker, slot, categories, equipment markers, and owner details.
Worker Hub has no Deposit/Withdraw actions or separate City Storage tab. Both interfaces
use the same provider. The worker-management adapter still enforces slots and active-work locks.

CityToolStorage validates each complete deposit batch before committing Inventory, item
stacks, and tool units and notifying observers. Supported worker equipment becomes distinct
unallocated units; other eligible items become counted stacks. The physical access UI is
deposit-only and explains that city deposits cannot be returned. The compatibility method
`withdraw_items_to_inventory()` always rejects without state changes or notifications,
including for unused or released equipment. Unequip releases units within the same city stock.
Food and clothing remain physical items and are not converted into
CityStockManager supply points on deposit. Daily food and clothing now use the physical
city stock through the guarded consumption/allocation paths below.
Content grants no playtest items by default; workshop stock remains owned by WorkShopStorage.

This stock lifetime does not preserve worksite assignments, hauling progress, or output
across scene changes, and it does not add disk saving or a new autoload.

### Physical city food and daily needs

`CityToolStorage.get_food_supply_points()` derives meal availability from registered
Consumable items with positive food values plus retained prepared portions. Raw food
resources, personal Inventory, Hauler cargo and workshop stock do not count as ready city
meals. `food_portions` records unused points by source item ID after a whole food item is
opened; those points no longer exist in the whole-item stack. Portions share the provider's
runtime lifetime, remain city-owned, and have no withdrawal path.

`consume_food_points()` validates the complete stock state and requested amount, consumes
existing portions first, then whole food in ascending food-value/item-ID order, and retains
any excess as portions. Its guarded commit installs items and portions together before one
city change notification. Failure mutates nothing; Inventory and equipment are unaffected.

`CitizenNeedsManager` uses one ordered recipient snapshot: residents, then legacy workers
without a linked citizen, with each identity counted once. Its daily food transaction feeds
the affordable recipients at the unchanged one-point/person rate; linked workers resolve
the result through CitizenData. Food fulfilled/unfulfilled counters include this same set.
The existing midnight event drives consumption, with per-day and reentrancy guards so time
skips process every day and repeated notifications cannot eat the same day's ration twice.
Existing shelter and reliability values are preserved. Satisfaction follows the approved
daily basic-needs rule in `docs/game-concept.md` section 11.

The physical City Storage food summary, legacy GameplayHUD food status and immigration food
readiness query this same stock/recipient calculation. Full days remaining is whole days
at the current population's daily need; zero recipients is displayed as no daily need.
Reading a summary never creates a provider or consumes stock. The former
`CityStockManager.food_supply` and legacy conversion helpers remain compatibility data/API;
they are not the source for current daily food, food UI or immigration food readiness, and
are not silently converted or added to the physical totals. The worker test scene now seeds
physical bread explicitly instead of the old counter.

### Physical clothing allocations and worker need results

`CityToolStorage.get_clothing_item_count()` counts the approved finished-clothing IDs.
`take_clothing_items(maximum)` removes up to the available whole units in stable item-ID
order, committing once under the same transfer guard as other city transactions. It does
not stage goods through Inventory or affect food portions or allocated tools.

`CitizenNeedsManager.clothing_allocations` records item ID, issue day and last valid day
per unique person. One item issued on day D covers D through D+6; replacement is due on D+7.
The daily clothing pass uses the same resident-first recipient set as food. Linked workers
resolve their citizen allocation; an unlinked worker receives at most one allocation.
Valid allocations consume no new item. Expired or missing coverage requests replacement
stock; an unsuccessful request marks clothing unfulfilled for that daily evaluation.
Per-day and reentrant guards prevent repeated issue. Allocations remain on the existing
autoload across scene transitions, without adding fields to CitizenData or WorkerData.

`get_clothing_supply_summary()` reports available items, unique consumers, valid coverage
and replacements currently due. Legacy GameplayHUD and immigration use this physical
summary; the old CityStockManager clothing counter no longer fulfills current needs.
The immigration bonus amounts and existing probabilities are unchanged.

The physical City Storage modal reads this same summary beside the existing Food Supply
panel. Covered is current valid coverage; Reserve is unused physical garments; Awaiting
is replacements currently due; Short is `max(0, Awaiting - Reserve)`. Sufficient reserve
for uncovered people displays `Ready next day`, without marking them covered before the
daily evaluation. Both panels refresh on stock/time/population changes and the completed
`needs_changed` signal, and disconnect their refresh listeners when closed. Opening or
refreshing the modal never issues clothing or consumes food.

After all three needs are evaluated, `last_needs_results` stores per-person flags, missing
needs, clothing days remaining and actual clamped satisfaction/reliability changes.
`needs_changed` is emitted once after the complete daily result. Worker-management rows
read `get_worker_needs_summary()`; Worker Hub Details refreshes its visible scrollable
popup from the signal. Missing evaluation displays unknown needs and current values without
an invented delta. UI reads never issue clothing or process another day.

This does not implement disk saving. A future persistence snapshot must retain city items,
prepared portions, clothing allocations and processed-day markers coherently to prevent
duplication on load.

### Approved storage integration direction (staged, not fully implemented)

The Game Director accepted Canva slide 2 on 2026-09-20 with permanent city ownership after
deposit. See `docs/game-concept.md` section 20.2 for the approved behavior and `ROADMAP.md`
for delivery gates. The target structure retains one central City Storage for the MVP,
separate cargo in transit, and stock scoped to each workshop. Storage A/B are optional
transit destinations with onward routing, not alternative global stock providers.
The 2026-09-21 intake restriction supersedes the earlier general-material warehouse scope;
city-to-workshop logistics remain deferred and may not bypass the approved item filter.

Reuse the existing storage/delivery responsibilities rather than introducing another global
manager. A shared transfer boundary must validate stable location IDs, item IDs/quantities,
ownership, capacity, filters and access before applying a complete movement. UI requests a
transfer; it is not the authority for ownership. Worker equipment allocation is not a second
copy of the item. A failed delivery retains cargo; loading/delivery must not duplicate stock.

Before enabling city-to-workshop supply, distinguish city-owned lots from existing personal
workshop stock. Free/Held/Pending describe availability, not ownership; paying a fee must not
make city goods personally withdrawable. Cargo, stock and output need consistent ownership
through both transfers and save/load. Production of mixed-owner inputs must be specified
before mixing those lots. The current player-deposit and inbound-Hauler checkpoints do not
implement outbound city logistics or a cross-location ownership schema.

Persist the authoritative stock/allocation/cargo/output data together, with validated
cross-references and an explicit compatibility plan. The isolated worksite save fixture is
not a complete production save system and must not be silently replaced or migrated.
Ready-food consumption and the approved seven-day physical clothing distribution are
integrated independently of the pending workshop route.

## Player Runtime / Scene Transition Responsibilities

The current prototype keeps selected player/runtime state across scene transitions.

- The current main scene is the ContentScene authoring map, with player-needs debug
  guards enabled. The Home scene and reusable scene/spawn routing remain available;
  the current map does not include the earlier Home Door or Nightmare composition.
- `PlayerRuntimeState` supports runtime persistence across scene changes.
- `SceneTransition` owns transition/routing behavior, including the complete fade
  after the outgoing door is freed. A door starts that flow without awaiting it
  on the outgoing scene and resets its trigger if loading fails.
- `Player.can_move` combines the existing external movement gate with local action
  locks and the global transition guard. Pickup, dialogue, sleep, collapse,
  Nightmare return and worksite/plot modals
  release only their own restriction, so one action cannot restore another action's
  stale lock state. Incoming and outgoing Players remain still during a fade.
- `NightmareWorld` measures playable time after the entry fade; global transitions
  do not consume its countdown. Existing durations and penalty conversion remain
  unchanged.

Runtime persistence is not the same as save/load to disk.

## Save / Persistence Boundary

Real save/load is not yet complete.

Future persistence should serialize authoritative data/state rather than spawned visual nodes.

Likely persisted domains will include:
- player conditions and progression
- day/sleep usage
- inventory
- citizens and employment states
- workshop/work/process state as required
- city resources

Before implementing persistence, define schema ownership and migration rules. Do not infer a stable schema from runtime objects alone.

## Display / UI Boundary

Current implementation uses a low logical viewport for pixel-art rendering and integer scaling. Project-wide viewport/stretch settings are configuration authority, not per-UI preferences.

ContentScene uses YSortWorld at world z_index 0 for characters and object art.
Nested WorkshopPlot/JobBoard/WorkShop visuals expose foot sorting pivots; sprite
offsets retain authored placement. WorkshopPlot partitions its existing 48x48
texture into rear wall, side posts and table regions, so the rear wall does not
occlude a player already inside the plot and the table sorts at its own feet.
Floor debris and terrain stay below characters,
while captions and interaction prompts stay above them. PlayerVisual's body,
clothes and head remain one sorted unit under Player.
TableResources contains authored ResourceIcon/ResourceIcon2 Sprite2D slots.
Their transforms define the material layout; runtime swaps only recipe textures
and shows them after construction. A tool script draws the table reference only
in the editor, so arranging any preview material works for other item icons.

ContentScene's scene-local TimeDebugOverlay lives in scenes/debug, separate from
gameplay panels. In debug builds its button/backtick toggle exposes clock speed
and time jumps through existing TimeComponentManager minute/day signals. It
respects gameplay pause/condition/transition guards, leaves physics speed and
base clock configuration intact, and creates no autoload or persistent state.
Its explicit Build materials button tops personal Inventory up to one construction
kit using the construction state's requirements. It preserves surplus, preflights
the complete missing weight and grants nothing automatically. Unlike clock controls,
supplies remain available in a paused build menu, refreshing via items_changed.

UI scripts/scenes may adapt layout, but they must not change `project.godot` display configuration as a local fix.

Experimental UI should be isolated under the approved sandbox after agent activation:

`res://scenes/test_scenes/ui_sandbox/`

Production UI remains under established `res://scenes/ui/` conventions.

## Design Pillar: Variable Progression

The game should avoid becoming a fixed spreadsheet where every playthrough follows one solved route.

Use controlled variation:

```text
Player decision
-> System state check
-> Controlled random variation
-> Readable result
```

Randomness should create strategic variation, not remove player agency.

Possible later variation layers include migrant timing, applicant availability/quality, resident traits, opportunity timing, and limited production/needs variation.

Do not introduce broad randomness before the deterministic prototype loop is stable and readable.

## AI NPC / Quest Integration Architecture

AI-powered unique NPCs are a long-term layer. They must not replace authoritative game systems.

Responsibility split:

```text
AI NPC = character voice, personality, intent, contextual dialogue
Quest System = rules, validation, objective tracking, reward approval
Game State = inventory, city state, trust, progress, economy authority
```

AI may suggest quest intent, but the game must validate item, quantity, timing, requirements, reward and completion.

AI must not directly create money/items, modify authoritative inventory, mark quests complete, distribute rewards, change trust/progression flags, or override economy rules.

Recommended order:
1. Stable dialogue.
2. Stable inventory/resource rules.
3. Normal quest system.
4. Trust/relationship state.
5. Quest templates and reward ranges.
6. AI dialogue layer for selected unique NPCs.
7. AI-assisted quest offering behind validation.

## Existing Core Systems to Preserve

Implementation agents should inspect and preserve the intent of existing systems including:
- ItemDatabase
- Inventory
- WorkShopStorage
- WorkManager
- ProcessManager
- TimeComponentManager
- CitizenManager
- CitizenGenerator
- ImmigrationManager
- CitizenNeedsManager
- WorkerDatabase
- Applicant/Job Board flow
- PlayerRuntimeState
- SceneTransition
- WorkStateRuntime
- gameplay UI scenes

Do not add another manager simply because a feature could be implemented that way. First determine which existing system already owns the responsibility.

## Main architecture risks

### Duplicate authority
Avoid multiple places owning the same state, especially:
- citizen/employment state
- worker assignment
- workshop storage/output
- world time
- player runtime state

### UI owning gameplay
UI should display state and request actions. It should not become the hidden owner of economy, employment, production, condition, or progression rules.

### Global-manager sprawl
The project already has many autoloads. Adding another autoload is a high-impact architecture change and requires explicit justification/approval.

Keep the existing `DialogueManager` registration after the game autoloads. On
Godot 4.5.2, the earlier order retained 15 addon script resources on runtime exit
(16 on editor import); moving only this registration to the end eliminated that
reproducible shutdown issue. Game autoload initialization does not need its
singleton; dialogue scenes use it after startup. This is a tested order dependency,
not an addon upgrade or a proven diagnosis of the engine's internal cause.

### Save schema churn
Do not lock persistence around unstable node structures before the daily loop is stable.

### AI becoming game authority
Future AI NPC systems must remain expressive layers over deterministic validated game rules.

## Code Change Policy

Prefer small isolated changes over broad rewrites.

When implementation evidence shows this document is stale, update the relevant snapshot/boundary; do not silently rewrite game design while doing so.

### Shared material worksites (local integration, 2026-09-26)

Content Worksites continues to own the existing inspector, manual sessions, daily scheduler,
ground output and hauling. ResourceSiteMarker is configuration only (item, minutes/unit,
stock); no parallel gathering controller is introduced. Session defaults retain Clay's
contract. Hauling captures item identity per route, and matching storage determines which
resource it accepts. The isolated Clay save fixture remains Clay-only; this is not a generic
worksite persistence schema or a new global manager.

Gameplay worker rosters now start empty. Job Board hiring populates WorkerDatabase;
the main-map adapter no longer seeds its playtest Hauler by default. Legacy worker
resources remain available through explicit reload_workers() calls in isolated fixtures.
Map reloads retain hired workers rather than rebuilding or clearing the runtime roster.

Authored Wood/Reed/Straw/Water stockpiles reuse StorageDestination and the existing
single-resource stockpile backend. WorksiteStockpileAccess adds guarded E withdrawal
to personal Inventory; workshop deposit continues through the existing workshop API.
Stockpile quantities retain their existing scene-local lifetime (no disk or map-reload persistence).

Workshop construction runtime now starts uncleared, then clearing, then empty (ready to
build), building and built. Clearing reserves one worker or executes a guarded manual
player time skip, without inventory transfer. Interrupted player clearing retains its
remaining minutes and stops unattended progress. The existing runtime host preserves
clearing/construction across maps; this adds no disk-save schema.

## Traveling Merchant Runtime (MVP)

The authored `TravelingMerchant` in ContentScene is a view/interaction adapter.
It acquires one `CommonTravelingMerchant` child under the existing WorkStateRuntime
host. This ledger owns visit stock, remaining request quotas, the merchant wallet and schedule progress across
map reloads. No new autoload, disk-save schema or city treasury authority is added.
The existing Player E dispatcher recognizes the `traveling_merchants` group.

`common_merchant.tres` contains the approved MVP schedule and provisional playtest
offers and separate purchase requests. Buy lists offered goods; Sell lists requested
goods with remaining demand. Selling reduces demand; buying never restores it. The
initial requests are six wood and twenty dry bricks per visit. Prices are from the
player's perspective. Finite stock, demand and wallet reset once
at a new scheduled arrival, never on menu reopen, scene reload or a clock rewind.
The MVP schedule is deterministic; city-statistics-based arrivals and Rare tiers
remain future design work.

The ledger preflights both balances, integer limits and final personal inventory
weight (Shekel is weightless) before committing all changes. It publishes Inventory's
existing change signal only after both sides agree, so existing HUD/storage readers
never observe a half trade. UI only requests actions; the scene adapter revalidates
physical access, departure, collapse and transitions. Browsing locks movement but
keeps world time running; departure closes the menu. Trading consumes/produces only
personal Inventory goods, never held workshop output or city-owned stock.
