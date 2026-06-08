# DEVLOG - Time is Precious

Last updated: 2026-06-09

## Project Identity
**Time is Precious** is a 2D top-down management RPG with a Mesopotamian theme, built in Godot Engine 4 / 4.5.

Core pillars:
- Time as the main strategic pressure.
- Resource management.
- Worker / NPC delegation.
- Production chains.
- City and player home progression.
- Variable progression between players.

## Current Development Focus
The current focus is not adding big features. The focus is stabilizing the playable core loop.

Priority order:
1. Resource gathering.
2. Resource storage.
3. Work / process execution.
4. NPC delegation.
5. Production output.
6. Basic progression impact.
7. Minimum playable prototype.

## Milestone Snapshot
Completed or merged work:
- PR #57: Job Board began showing applicant offers instead of directly starting jobs.
- PR #58: Planning docs established the project direction, including the separation between population/citizen status and employment/worker status.
- PR #59: Asset control docs introduced the asset guide, palette guide, and asset registry workflow.
- PR #61: Modular worker visual was added with layered body, head, clothes, hands, hair, and accessories.
- PR #62: Palette guide was updated with the current game colors, including skin, clothing, hair, UI, and Mesopotamian earth-tone rules.
- PR #63: Roadmap was refocused around the playable core loop.
- PR #64: Variable progression became a design pillar so the game does not become too predictable.
- PR #65: Resolution direction was documented as 1280x720, 16:9 landscape, PC first, Android landscape compatible.
- PR #66: Modular citizens, shared character assets, citizen runtime data, city spawning, and immigration accept/reject flow were added.

Current local work after PR #66:
- Workshop menu became player-facing.
- Manage Storage submenu was added.
- Item transfer UI supports deposit and withdraw.
- Item change popup shows item gains/losses for storage movement.
- Workshop can assign a prototype worker and start mudbrick production from stored materials.
- Mudbrick job output enters claimable workshop escrow.

## 2026-06-09 - Workshop Storage and Mudbrick Job Loop

### What changed
Added the first player-facing workshop loop around storage, worker assignment, and mudbrick job start.

Implemented:
- `WorkshopMenuUI` now exposes workshop actions through a modal UI.
- `WorkshopStorageMenuUI` separates storage management from the main workshop menu.
- `ItemTransferUI` is reused for both deposit and withdraw.
- `WorkShop.deposit_selected_items_from_player()` moves selected inventory items into `WorkShopStorage`.
- `WorkShop.withdraw_selected_items_to_player()` moves stored workshop items back into player inventory.
- `ItemChangePopup` gives visual feedback for item movement:
  - deposit: player `-amount`, workshop `+amount`
  - withdraw: player `+amount`, workshop `-amount`
- `WorkShop.assign_test_worker()` assigns the first available prototype worker.
- `WorkShop.start_mudbrick_job_from_storage()` starts `mudbrick_make` using `WorkShopStorage` as both source and output store.
- NPC job output enters `WorkShopStorage.claimable_outputs` instead of directly entering normal storage.

### Validation
Manual Godot runtime testing confirmed:
- Assign worker action works.
- Deposit of `clay_lump`, `water_jar`, and `straw_bundle` works.
- Withdraw returns stored items to player inventory.
- Popup direction changes correctly between deposit and withdraw.
- Mudbrick job starts from workshop storage after a worker is assigned.
- Completed mudbrick job creates a claimable `wet_mudbrick` output.

Observed successful test output:

```text
Assigned worker: worker_crafter_01
Selected items: { "clay_lump": 3, "water_jar": 3, "straw_bundle": 3 }
Started mudbrick job: <order_id>
Claimable outputs count: 1
Claimable[0]: { "items": { "wet_mudbrick": 60 }, "service_fee_shekel": 5, ... }
```

### Remaining boundaries
- Worker assignment is still a prototype/test path, not yet connected to real hired citizens.
- Main workshop action currently doubles as assign/start depending on assignment state; this should become separate `Assign Worker` and `Start Job` actions.
- Workshop job selection UI is not final; current path starts mudbrick directly.
- Drying process still needs player-facing verification after wet mudbrick becomes claimable.
- Failure feedback should be improved when storage/inventory capacity blocks transfer.
- Debug prints should be reduced or converted to UI feedback before polish.

## 2026-06-04 - Modular Citizens and Immigration Flow Added

### What changed
PR #66 added the first runtime slice for modular citizens and immigration.

Implemented:
- Shared modular character assets now support reusable body, head, hand, hair, clothing, and accessory combinations.
- Player visual uses shared body / hand / clothes assets with player-specific head and hair.
- `CitizenData` and `VisualProfile` define citizen identity, basic need flags, status, profession, and visual appearance.
- `CitizenManager`, `CitizenGenerator`, and `ImmigrationManager` manage the citizen registry, random citizen creation, immigration pressure/chance, and pending immigrant batches.
- `CitySpawner` and `CitizenActor` show accepted citizens in the test city.
- Immigration request UI lets the player accept or reject the full immigrant batch.

### Validation
- Manual Godot runtime testing confirmed modular visuals, citizen spawning, immigration request popup, accept/reject flow, and HUD count updates.
- `git diff --check` passed before the PR.

### Remaining boundaries
- This is a prototype foundation, not final save/load.
- Accepted citizens currently live in the runtime registry.
- Job Board applicant conversion, worker hiring from citizens, and richer citizen traits still need future work.

## 2026-06-01 - Variable Progression Pillar Added

### What changed
Added a design pillar stating that the game should not be too easy to predict from a gameplay/progression perspective.

### Why
The intended experience is that different players can develop different cities and progression paths. The game should not become a fixed spreadsheet with one obvious optimal route.

### Design direction
The game should use controlled randomness and system-driven variation.

Examples:
- Migrant count may vary based on city prosperity.
- Applicant quality and traits may vary.
- Timing of opportunities may vary.
- Needs pressure may vary within readable limits.
- Production or city events may include small controlled modifiers.

### Important boundary
Randomness should create strategic variation, not chaos.

The player should still feel that decisions matter.

Correct direction:

```text
Player decision
-> System state
-> Controlled random variation
-> Readable result
```

Wrong direction:

```text
Pure random outcome
-> Player cannot plan
-> Result feels unfair
```

## Current Design Issue: Worker vs Resident
A key issue has been identified: the code/design must not treat `worker` and `resident` as the same concept.

Important decision:
- Food consumption should depend on **resident/citizen status**.
- Food consumption should not depend on whether an NPC has been hired as a worker.

Correct flow:

```text
Migrant arrives
-> Player accepts or rejects
-> Accepted migrant becomes Resident / Citizen
-> Resident starts consuming city stock
-> Eligible resident can appear on Job Board
-> Player hires applicant
-> Hired worker can be assigned to work/process
```

## Working Design Decision
Separate NPC state into two layers:

### Population Status
Examples:
- `migrant`
- `resident`
- `rejected`
- `left_city`

### Employment Status
Examples:
- `unemployed`
- `applicant`
- `hired`
- `assigned`
- `working`

This avoids the mistake of using only one boolean such as `is_hired` for all NPC logic.
