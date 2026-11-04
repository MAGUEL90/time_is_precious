extends Node

const STATE = preload("res://scenes/raid/raid_state.gd")
const STORAGE = preload("res://scenes/storage_destination/city_tool_storage.gd")
var failures: int = 0
var fixtures: Array[Node] = []
var _reentrant_state: Node
var _reentrant_quote: Dictionary = {}
var _reentrant_attempted: bool = false
var _reentrant_started: bool = false
var _conservation_state: Node
var _conservation_expected: Dictionary = {}
var _conservation_observed: bool = false

func _ready() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func fixture() -> Node:
	var storage = STORAGE.new()
	add_child(storage)
	storage.items = {"stone": 100, "wood_log": 100}
	var state = STATE.new()
	var config: Resource = load("res://scenes/raid/wall_playtest.tres").duplicate(true)
	# This suite covers wall improvements and retains the legacy fixed three-day
	# travel fixture; mixed-party composition has a focused regression scene.
	config.party_profile = load("res://scenes/raid/normal_raider_party.tres").duplicate(true)
	state.config = config
	state.storage = storage
	add_child(state)
	state.wall_level = 1
	state.wall_hp = 50
	state.phase = "safe"
	state._schedule_from(state._latest_minute)
	fixtures.append(state)
	fixtures.append(storage)
	return state

func minutes(state: Node, amount: int) -> void:
	var now: int = state._latest_minute + amount
	state._on_time_changed(now / 1440, (now % 1440) / 60, now % 60, "clear")

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	var inventory_capacity_before: float = Inventory.max_load
	Inventory.max_load = 100000.0
	Inventory.items.assign({"stone": 500, "wood_log": 500})
	_test_build_and_atomic_inventory_charge()
	var state = fixture()
	check(state.config.is_valid(), "Approved improvements profile is valid.")
	check(not state.get_work_quote("unknown").can_start, "Unknown jobs cannot spend materials.")
	var original_stock: Dictionary = state.storage.items.duplicate(true)
	var inventory_before_upgrade: Dictionary = Inventory.items.duplicate(true)
	var quote: Dictionary = state.get_work_quote("upgrade")
	check(quote.can_start and quote.target_hp == 80 and quote.target_defend == 3 and quote.duration_minutes == 240, "Upgrade quote has approved benefits and duration.")
	check(state.storage.items == original_stock and Inventory.items == inventory_before_upgrade and state.wall_level == 1, "Reading a quote is side-effect free.")
	var stale: Dictionary = quote.duplicate(true)
	stale.target_hp = 999
	check(not state.request_wall_work(stale) and state.storage.items == original_stock and Inventory.items == inventory_before_upgrade, "Forged benefits cannot bypass quote revalidation.")
	_reentrant_state = state
	_reentrant_quote = quote.duplicate(true)
	_reentrant_attempted = false
	_reentrant_started = false
	_conservation_state = state
	_conservation_expected = inventory_before_upgrade.duplicate(true)
	_conservation_observed = false
	Inventory.items_changed.connect(_on_inventory_commit)
	check(state.request_wall_work(quote), "A valid upgrade starts.")
	Inventory.items_changed.disconnect(_on_inventory_commit)
	check(_reentrant_attempted and not _reentrant_started, "An Inventory callback cannot start a second project during payment.")
	check(_conservation_observed, "Inventory observers see the staged wall payment with no missing materials.")
	check(Inventory.items.get("stone", 0) == int(inventory_before_upgrade.get("stone", 0)) - 20 and Inventory.items.get("wood_log", 0) == int(inventory_before_upgrade.get("wood_log", 0)) - 10 and state.storage.items == original_stock and state._work_paid_source == "inventory" and state.wall_hp == 50 and state.wall_level == 1, "Materials are charged once from Inventory; City Storage and the old wall remain unchanged.")
	check(not state.request_wall_work(quote) and not state.get_work_quote("watchtower").can_start, "Parallel or duplicate work is blocked.")
	minutes(state, 239)
	check(state.wall_level == 1 and state._work_remaining == 1, "Upgrade waits the full duration.")
	minutes(state, 1)
	check(state.wall_level == 2 and state.wall_hp == 80 and state.get_status().defend == 3, "Completion applies level-2 HP and Defend.")
	check(not state.get_work_quote("upgrade").can_start, "No level-3 or repeated upgrade is offered.")
	var arrival: int = state._attack_at
	var inventory_before_tower: Dictionary = Inventory.items.duplicate(true)
	check(state.request_wall_work(state.get_work_quote("watchtower")), "A watchtower is an independent timed addition.")
	check(Inventory.items.get("stone", 0) == int(inventory_before_tower.get("stone", 0)) - 10 and Inventory.items.get("wood_log", 0) == int(inventory_before_tower.get("wood_log", 0)) - 10 and state.storage.items == original_stock, "Watchtower materials come from Inventory in the quoted quantities.")
	minutes(state, 179)
	check(not state.watchtower_built and state.inspect_raiders().is_empty(), "An unfinished tower grants no intelligence.")
	minutes(state, 1)
	check(state.watchtower_built and state.get_warning_days() == 2 and state._attack_at == arrival, "Completed tower expands detection without moving arrival.")
	check(state.inspect_raiders().is_empty() and state.get_status().raider_type == "Unknown", "A tower does not reveal an undetected expedition.")
	minutes(state, arrival - 2880 - state._latest_minute)
	check(state.phase == "warning" and state.inspect_raiders().type == "Normal raiders", "Tower detects and identifies the existing party two days before arrival.")
	check(not state.get_work_quote("watchtower").can_start, "A second tower cannot be built.")
	state._start_attack(4)
	state.set_process(false)
	state.advance_attack(5.0)
	check(state.wall_hp == 79, "Level-2 Defend applies to actual incoming hits.")
	state.advance_attack(55.0)
	check(state.get_last_report().outcome == "repelled" and state.inspect_raiders().is_empty(), "Inspection closes after retreat; intelligence does not expose a future party.")
	state.wall_hp = 0 # Simulate a later breach after the upgraded wall wears down.
	var next_arrival: int = state._attack_at
	var inventory_before_rebuild: Dictionary = Inventory.items.duplicate(true)
	check(state.request_wall_work(state.get_work_quote()), "Ruined level-2 wall can be rebuilt.")
	check(Inventory.items.get("stone", 0) == int(inventory_before_rebuild.get("stone", 0)) - 10 and Inventory.items.get("wood_log", 0) == int(inventory_before_rebuild.get("wood_log", 0)) - 5 and state.storage.items == original_stock, "Rebuilding an upgraded wall charges the unchanged build cost to Inventory.")
	minutes(state, 120)
	check(state.wall_level == 2 and state.wall_hp == 80 and state.watchtower_built and state._attack_at == next_arrival, "Rebuild retains completed tier/tower and does not reroll travel.")
	state.wall_hp = 71
	var inventory_before_repair: Dictionary = Inventory.items.duplicate(true)
	var repair_city_stock: Dictionary = state.storage.items.duplicate(true)
	var repair_quote: Dictionary = state.get_work_quote()
	check(repair_quote.materials == {"stone": 2} and repair_quote.duration_minutes == 60, "Repair price and duration use the upgraded HP maximum.")
	check(state.request_wall_work(repair_quote), "Level-2 repair starts.")
	check(Inventory.items.get("stone", 0) == int(inventory_before_repair.get("stone", 0)) - 2 and state.storage.items == repair_city_stock and state._work_paid_source == "inventory", "Wall repair charges only Inventory the unchanged material amount.")
	minutes(state, 60)
	check(state.wall_hp == 80, "Level-2 repair restores the upgraded maximum.")
	var baseline = fixture()
	minutes(baseline, 1440)
	check(baseline.phase == "safe" and baseline.inspect_raiders().is_empty(), "No tower preserves the original one-day warning.")
	minutes(baseline, 1440)
	check(baseline.phase == "warning" and baseline.get_status().raider_type == "Unknown" and baseline.inspect_raiders().is_empty(), "Detected raider type remains unknown without surveillance.")
	var mid_journey = fixture()
	minutes(mid_journey, 1440)
	var fixed_arrival: int = mid_journey._attack_at
	check(mid_journey.request_wall_work(mid_journey.get_work_quote("watchtower")), "Level-1 wall can add a tower without buying level 2.")
	minutes(mid_journey, 180)
	check(mid_journey.phase == "warning" and mid_journey._attack_at == fixed_arrival, "A tower completed within its detection window reveals the existing party immediately.")
	for kind: String in ["repair", "upgrade", "watchtower"]:
		var interrupted = fixture()
		if kind == "repair":
			interrupted.wall_hp = 45
		var before: Dictionary = Inventory.items.duplicate(true)
		var city_before: Dictionary = interrupted.storage.items.duplicate(true)
		check(interrupted.request_wall_work(interrupted.get_work_quote(kind)), "Interruption fixture starts " + kind)
		interrupted.wall_hp = 1
		interrupted.phase = "warning"
		interrupted._start_attack(3)
		interrupted.set_process(false)
		var remaining: int = interrupted._work_remaining
		minutes(interrupted, 10)
		check(interrupted._work_remaining == remaining, "Active raid pauses " + kind)
		interrupted.advance_attack(5.0)
		check(interrupted._work_kind.is_empty() and Inventory.items == before and interrupted.storage.items == city_before and not interrupted.watchtower_built and interrupted.wall_level == 1, "Breach refunds unfinished " + kind + " to Inventory without granting its benefits.")
	var battle_upgrade = fixture()
	check(battle_upgrade.request_wall_work(battle_upgrade.get_work_quote("upgrade")), "Battle-damage fixture starts an upgrade.")
	battle_upgrade.phase = "warning"
	battle_upgrade._start_attack(3)
	battle_upgrade.set_process(false)
	battle_upgrade.advance_attack(60.0)
	check(battle_upgrade.wall_hp == 38 and battle_upgrade.wall_level == 1, "The unfinished upgrade uses original defense throughout a surviving raid.")
	minutes(battle_upgrade, 240)
	check(battle_upgrade.wall_hp == 68 and battle_upgrade.wall_level == 2, "Finishing an upgrade preserves the damage taken during interruption.")
	battle_upgrade.watchtower_built = true
	battle_upgrade.phase = "warning"
	battle_upgrade._start_attack(100)
	battle_upgrade.set_process(false)
	battle_upgrade.advance_attack(60.0)
	check(battle_upgrade.wall_hp == 0 and battle_upgrade.wall_level == 2 and battle_upgrade.watchtower_built,
		"An actual breach destroys only the wall durability, not the completed tier or tower.")
	var shortage = fixture()
	var funded_inventory: Dictionary = Inventory.items.duplicate(true)
	var stale_funded_quote: Dictionary = shortage.get_work_quote("upgrade")
	var shortage_city_stock: Dictionary = shortage.storage.items.duplicate(true)
	Inventory.items.clear()
	check(not shortage.request_wall_work(stale_funded_quote) and shortage._work_kind.is_empty() and shortage.storage.items == shortage_city_stock and Inventory.items.is_empty(), "A stale affordable quote cannot charge City Storage after Inventory changes.")
	var short_quote: Dictionary = shortage.get_work_quote("upgrade")
	check(not short_quote.can_start and short_quote.target_hp == 80 and short_quote.materials == {"stone": 20, "wood_log": 10} and short_quote.reason == "Not enough materials in Inventory.", "City Storage cannot make up a short Inventory balance; the exact material quote remains visible.")
	shortage.wall_hp = 45
	check(not shortage.get_work_quote("upgrade").can_start, "Damaged wall must be repaired before an upgrade.")
	Inventory.items.assign(funded_inventory)
	_test_inventory_refund_paths()
	for node: Node in fixtures:
		if is_instance_valid(node):
			node.free()
	Inventory.items.assign(inventory_before)
	Inventory.max_load = inventory_capacity_before
	print("DefenseImprovementsTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _test_build_and_atomic_inventory_charge() -> void:
	var state = fixture()
	state.wall_hp = 0
	state.wall_level = 0
	state.phase = "unbuilt"
	var storage_before: Dictionary = state.storage.items.duplicate(true)
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	Inventory.items.assign({"stone": 10, "wood_log": 4})
	var insufficient_quote: Dictionary = state.get_work_quote("build")
	check(not insufficient_quote.can_start and not state.request_wall_work(insufficient_quote) and Inventory.items == {"stone": 10, "wood_log": 4} and state.storage.items == storage_before, "A mixed shortage rejects the whole wall payment without taking the available Stone or using City Storage.")
	Inventory.items.assign(inventory_before)
	var quote: Dictionary = state.get_work_quote("build")
	check(quote.can_start and quote.duration_minutes == 120 and quote.materials == {"stone": 10, "wood_log": 5}, "Wall build retains its approved time and material quote.")
	check(state.request_wall_work(quote), "Timed wall construction starts with player materials.")
	check(Inventory.items == {"stone": int(inventory_before.get("stone", 0)) - 10, "wood_log": int(inventory_before.get("wood_log", 0)) - 5} and state.storage.items == storage_before, "Wall construction atomically consumes only Inventory materials.")

func _on_inventory_commit() -> void:
	_observe_payment_conservation()
	if _reentrant_attempted or not is_instance_valid(_reentrant_state):
		return
	_reentrant_attempted = true
	_reentrant_started = _reentrant_state.request_wall_work(_reentrant_quote)

func _observe_payment_conservation() -> void:
	if not is_instance_valid(_conservation_state):
		return
	var observed: Dictionary = Inventory.items.duplicate(true)
	for item_id: String in _conservation_state._work_paid:
		observed[item_id] = int(observed.get(item_id, 0)) + int(_conservation_state._work_paid[item_id])
	_conservation_observed = observed == _conservation_expected

func _test_inventory_refund_paths() -> void:
	var legacy = fixture()
	var legacy_inventory: Dictionary = Inventory.items.duplicate(true)
	legacy.storage.items = {"stone": 98, "wood_log": 100}
	legacy._work_kind = "repair"
	legacy._work_paid = {"stone": 2}
	legacy._work_paid_source = "city_storage"
	legacy._refund_interrupted_repair()
	check(legacy.storage.items == {"stone": 100, "wood_log": 100} and Inventory.items == legacy_inventory and legacy._work_kind.is_empty(), "A migrated city-funded repair returns its payment to City Storage.")
	legacy._refund_interrupted_repair()
	check(legacy.storage.items.get("stone", 0) == 100, "A completed legacy refund cannot be repeated.")

	var pending = fixture()
	var return_cost: Dictionary = {"stone": 2}
	var expected_total: Dictionary = Inventory.items.duplicate(true)
	var paid_quantity_before: int = int(Inventory.items.get("stone", 0))
	Inventory.items["stone"] = paid_quantity_before - 2
	pending._work_kind = "repair"
	pending._work_paid = return_cost.duplicate()
	pending._work_paid_source = "inventory"
	var paid_weight: float = Inventory.get_bulk_item_total_weight(return_cost)
	var full_weight: float = Inventory.get_total_inventory_weight()
	var old_capacity: float = Inventory.max_load
	Inventory.max_load = full_weight + minf(0.0001, paid_weight / 2.0)
	var before_failed_refund: Dictionary = Inventory.items.duplicate(true)
	pending._refund_interrupted_repair()
	check(pending._refund_pending and pending._work_kind == "repair" and pending._work_paid == return_cost and Inventory.items == before_failed_refund, "A full Inventory retains the pending refund without losing or duplicating its paid materials.")
	Inventory.max_load = maxf(old_capacity, full_weight + paid_weight + 1.0)
	_conservation_state = pending
	_conservation_expected = expected_total
	_conservation_observed = false
	Inventory.items_changed.connect(_on_inventory_commit)
	pending._refund_interrupted_repair()
	Inventory.items_changed.disconnect(_on_inventory_commit)
	check(not pending._refund_pending and pending._work_kind.is_empty() and Inventory.items.get("stone", 0) == int(before_failed_refund.get("stone", 0)) + 2, "The pending Inventory refund retries once space is available.")
	check(_conservation_observed, "Inventory observers see the refund staged out of the ledger before it arrives.")
	pending._refund_interrupted_repair()
	check(Inventory.items.get("stone", 0) == int(before_failed_refund.get("stone", 0)) + 2, "Retrying a completed Inventory refund cannot duplicate materials.")
	Inventory.max_load = old_capacity
