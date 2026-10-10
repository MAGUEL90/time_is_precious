extends Node

const STATE = preload("res://scenes/raid/raid_state.gd")
const STORAGE = preload("res://scenes/storage_destination/city_tool_storage.gd")
var failures: int = 0
var fixtures: Array[Node] = []

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
	var state = fixture()
	check(state.config.is_valid(), "Approved improvements profile is valid.")
	check(not state.get_work_quote("unknown").can_start, "Unknown jobs cannot spend materials.")
	var original_stock: Dictionary = state.storage.items.duplicate(true)
	var quote: Dictionary = state.get_work_quote("upgrade")
	check(quote.can_start and quote.target_hp == 80 and quote.target_defend == 3 and quote.duration_minutes == 240, "Upgrade quote has approved benefits and duration.")
	check(state.storage.items == original_stock and state.wall_level == 1, "Reading a quote is side-effect free.")
	var stale: Dictionary = quote.duplicate(true)
	stale.target_hp = 999
	check(not state.request_wall_work(stale) and state.storage.items == original_stock, "Forged benefits cannot bypass quote revalidation.")
	check(state.request_wall_work(quote), "A valid upgrade starts.")
	check(state.storage.items == {"stone": 80, "wood_log": 90} and state.wall_hp == 50 and state.wall_level == 1, "Materials are charged once; old wall remains until completion.")
	check(not state.request_wall_work(quote) and not state.get_work_quote("watchtower").can_start, "Parallel or duplicate work is blocked.")
	minutes(state, 239)
	check(state.wall_level == 1 and state._work_remaining == 1, "Upgrade waits the full duration.")
	minutes(state, 1)
	check(state.wall_level == 2 and state.wall_hp == 80 and state.get_status().defend == 3, "Completion applies level-2 HP and Defend.")
	check(not state.get_work_quote("upgrade").can_start, "No level-3 or repeated upgrade is offered.")
	var arrival: int = state._attack_at
	check(state.request_wall_work(state.get_work_quote("watchtower")), "A watchtower is an independent timed addition.")
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
	check(state.request_wall_work(state.get_work_quote()), "Ruined level-2 wall can be rebuilt.")
	minutes(state, 120)
	check(state.wall_level == 2 and state.wall_hp == 80 and state.watchtower_built and state._attack_at == next_arrival, "Rebuild retains completed tier/tower and does not reroll travel.")
	state.wall_hp = 71
	check(state.get_work_quote().materials == {"stone": 2}, "Repair price uses the upgraded HP maximum.")
	check(state.request_wall_work(state.get_work_quote()), "Level-2 repair starts.")
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
	for kind: String in ["upgrade", "watchtower"]:
		var interrupted = fixture()
		var before: Dictionary = interrupted.storage.items.duplicate(true)
		check(interrupted.request_wall_work(interrupted.get_work_quote(kind)), "Interruption fixture starts " + kind)
		interrupted.wall_hp = 1
		interrupted.phase = "warning"
		interrupted._start_attack(3)
		interrupted.set_process(false)
		var remaining: int = interrupted._work_remaining
		minutes(interrupted, 10)
		check(interrupted._work_remaining == remaining, "Active raid pauses " + kind)
		interrupted.advance_attack(5.0)
		check(interrupted._work_kind.is_empty() and interrupted.storage.items == before and not interrupted.watchtower_built and interrupted.wall_level == 1, "Breach refunds unfinished " + kind + " without granting its benefits.")
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
	shortage.storage.items = {}
	var short_quote: Dictionary = shortage.get_work_quote("upgrade")
	check(not short_quote.can_start and short_quote.target_hp == 80 and short_quote.materials == {"stone": 20, "wood_log": 10}, "Insufficient stock still presents the exact benefit and material quote.")
	shortage.wall_hp = 45
	check(not shortage.get_work_quote("upgrade").can_start, "Damaged wall must be repaired before an upgrade.")
	check(Inventory.items == inventory_before, "Defense improvements never spend personal Inventory.")
	for node: Node in fixtures:
		node.free()
	print("DefenseImprovementsTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
