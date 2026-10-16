extends Node

const RAID_STATE_SCRIPT: Script = preload("res://scenes/raid/raid_state.gd")
const RAID_CONFIG_SCRIPT: Script = preload("res://scenes/raid/raid_config.gd")
const CITY_STORAGE_SCRIPT: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")

var failures: int = 0
var state: Node
var storage: Node
var map_fixture: Node2D
var storage_changed_count: int = 0
var inventory_before: Dictionary = {}
var clock_before: Dictionary = {}
var clock_paused_before: bool = false
var clock_processing_before: bool = false

func _ready() -> void:
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)

func _run() -> void:
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	storage = CITY_STORAGE_SCRIPT.new()
	storage.name = "SyntheticCityStorage"
	add_child(storage)
	storage.items = {"stone": 12, "wood_log": 6}
	storage.units = {"fixture_tool": {"tool_id": "stone_hammer", "worker_id": "worker_fixture"}}
	storage.food_portions = {"barley_bread": 2}
	storage.changed.connect(_on_storage_changed)
	var units_before: Dictionary = storage.units.duplicate(true)
	var portions_before: Dictionary = storage.food_portions.duplicate(true)

	var config: Resource = RAID_CONFIG_SCRIPT.new()
	config.set("timed_work_enabled", true)
	config.set("instant_build_enabled", false)
	config.set("instant_repair_enabled", false)
	config.set("build_materials", {"stone": 10, "wood_log": 5})
	config.set("repair_materials_per_step", {"stone": 1})
	config.set("repair_hp_per_step", 5)
	config.set("build_minutes", 120)
	config.set("repair_minutes", 60)
	config.set("wall_max_hp", 50)
	config.set("wall_defend", 0)
	config.set("raids_enabled", false)
	config.set("duration_seconds", 60.0)
	config.set("hit_interval_seconds", 5.0)
	state = RAID_STATE_SCRIPT.new()
	state.name = "SyntheticWallLedger"
	state.config = config
	state.storage = storage
	add_child(state)
	await get_tree().process_frame
	var base_minute: int = _clock_minute()
	_expect(state.get_work_quote().kind == "build" and state.wall_level == 0,
		"Synthetic wall ledger begins ruined with build as its quoted work kind.")

	_test_build_shortage_quote_and_start()
	await _test_build_completion_across_map_replace(base_minute)
	await _test_stale_quote_and_repair_rounding(base_minute)
	await _test_raid_pause_resume_and_breach_refund(base_minute)

	_expect(Inventory.items == inventory_before, "Timed wall material work never changes player Inventory.")
	_expect(storage.units == units_before and storage.food_portions == portions_before,
		"Wall material work leaves unique equipment and food portions untouched.")
	_finish()

func _test_build_shortage_quote_and_start() -> void:
	storage.items = {}
	storage_changed_count = 0
	var empty_stock: Dictionary = storage.items.duplicate(true)
	var units_snapshot: Dictionary = storage.units.duplicate(true)
	var quote: Dictionary = state.get_work_quote()
	_expect(quote.kind == "build" and quote.materials == {"stone": 10, "wood_log": 5}
		and not quote.can_start, "An empty City Storage shows the full build requirement as unavailable.")
	_expect(not state.request_wall_work(quote) and storage.items == empty_stock
		and storage_changed_count == 0 and state._work_kind.is_empty(),
		"Empty stock blocks construction atomically without charging or starting a job.")

	storage.items = {"stone": 10, "wood_log": 4}
	var before: Dictionary = storage.items.duplicate(true)
	quote = state.get_work_quote()
	_expect(quote.kind == "build" and quote.materials == {"stone": 10, "wood_log": 5}
		and quote.duration_minutes == 120 and not quote.can_start,
		"Build quote lists its full synthetic materials and duration while one stock is short.")
	_expect(not state.request_wall_work(quote), "Short City Storage cannot start a wall build.")
	_expect(storage.items == before and storage.units == units_snapshot and storage_changed_count == 0
		and state._work_kind.is_empty(), "A multi-material shortage is rejected atomically without starting work.")

	storage.items = {"stone": 12, "wood_log": 6}
	before = storage.items.duplicate(true)
	var read_quote: Dictionary = state.get_work_quote()
	var second_read: Dictionary = state.get_work_quote()
	_expect(read_quote.can_start and read_quote == second_read and storage.items == before
		and storage_changed_count == 0, "Reading the same available quote repeatedly does not reserve or consume materials.")
	storage.items["wood_log"] = 4
	var changed_stock: Dictionary = storage.items.duplicate(true)
	_expect(not state.request_wall_work(read_quote), "A quote becomes stale when required City Storage stock changes.")
	_expect(storage.items == changed_stock and state._work_kind.is_empty() and storage_changed_count == 0,
		"A stale quote is rejected without partial material consumption.")

	storage.items = {"stone": 12, "wood_log": 6}
	storage_changed_count = 0
	quote = state.get_work_quote()
	_expect(state.request_wall_work(quote), "A current, affordable build quote starts timed construction.")
	_expect(storage.items == {"stone": 2, "wood_log": 1} and storage_changed_count == 1,
		"Construction charges the exact materials once at job start.")
	_expect(state.wall_hp == 0 and state.wall_level == 0 and state._work_kind == "build"
		and state._work_remaining == 120, "Starting construction does not grant wall HP before work finishes.")
	var paid_stock: Dictionary = storage.items.duplicate(true)
	_expect(not state.request_wall_work(quote) and not state.build_wall(),
		"A repeated quote or direct build request cannot restart work already in progress.")
	_expect(storage.items == paid_stock and storage_changed_count == 1,
		"Repeated start attempts do not charge City Storage a second time.")

func _test_build_completion_across_map_replace(base_minute: int) -> void:
	_set_clock_minute(base_minute + 30)
	_expect(state._work_remaining == 90 and state.wall_hp == 0,
		"A 30-minute world-time jump advances the pending build without granting HP.")
	map_fixture = Node2D.new()
	map_fixture.name = "FirstSyntheticMap"
	add_child(map_fixture)
	map_fixture.free()
	map_fixture = Node2D.new()
	map_fixture.name = "ReturnedSyntheticMap"
	add_child(map_fixture)
	_expect(is_instance_valid(state) and state._work_kind == "build" and state._work_remaining == 90,
		"The hosted wall ledger keeps its pending build across a map replacement.")
	_set_clock_minute(base_minute + 119)
	_expect(state._work_remaining == 1 and state.wall_hp == 0 and state.wall_level == 0,
		"Build remains pending one minute before its exact due time.")
	_set_clock_minute(base_minute + 120)
	_expect(state._work_kind.is_empty() and state._work_remaining == 0
		and state.wall_hp == 50 and state.wall_level == 1,
		"Build completes on the exact due minute and grants level 1 at full HP.")
	_expect(storage.items == {"stone": 2, "wood_log": 1},
		"Build completion does not charge materials a second time.")

func _test_stale_quote_and_repair_rounding(base_minute: int) -> void:
	storage.items = {"stone": 10, "wood_log": 5}
	storage_changed_count = 0
	state.wall_hp = 45
	var stale_quote: Dictionary = state.get_work_quote()
	_expect(stale_quote.kind == "repair" and stale_quote.materials == {"stone": 1}
		and stale_quote.duration_minutes == 60 and stale_quote.can_start,
		"Repair quote at 45 HP costs one stone step and lists the synthetic duration.")
	state.wall_hp = 40
	var stock_before_stale_request: Dictionary = storage.items.duplicate(true)
	var revised_quote: Dictionary = state.get_work_quote()
	_expect(revised_quote.materials == {"stone": 2} and not state.request_wall_work(stale_quote),
		"A wall-condition change invalidates an earlier repair quote.")
	_expect(storage.items == stock_before_stale_request and state._work_kind.is_empty()
		and storage_changed_count == 0, "A stale wall-condition quote consumes no supplies.")

	state.wall_hp = 37
	var quote: Dictionary = state.get_work_quote()
	var stock_before_quote: Dictionary = storage.items.duplicate(true)
	_expect(quote.materials == {"stone": 3} and quote.duration_minutes == 60 and quote.can_start,
		"Repair rounds a 13 HP deficit up to three five-HP material steps.")
	_expect(state.get_work_quote() == quote and storage.items == stock_before_quote and storage_changed_count == 0,
		"Reading a repair quote does not charge or reserve materials.")
	_expect(state.request_wall_work(quote), "A current repair quote starts timed repair.")
	_expect(storage.items == {"stone": 7, "wood_log": 5} and storage_changed_count == 1,
		"Repair consumes the three quoted stone units exactly once at start.")
	_expect(state.wall_hp == 37 and state._work_remaining == 60 and state._work_restore_hp == 13,
		"Repair holds HP steady until the job finishes and records its paid repair amount.")
	stock_before_quote = storage.items.duplicate(true)
	_expect(not state.request_wall_work(quote) and not state.repair_wall(),
		"Repair cannot be restarted while its timed job is active.")
	_expect(storage.items == stock_before_quote and storage_changed_count == 1,
		"Repeated repair attempts do not consume additional stock.")

	_set_clock_minute(base_minute + 150)
	_expect(state._work_remaining == 30 and state.wall_hp == 37,
		"Repair progresses by elapsed world minutes.")
	_set_clock_minute(base_minute + 130)
	_expect(state._work_remaining == 30,
		"A world-clock rewind cannot erase or repeat already-counted work time.")
	_set_clock_minute(base_minute + 149)
	_expect(state._work_remaining == 30,
		"Returning forward below the previous high-water minute does not double-count work.")
	_set_clock_minute(base_minute + 151)
	_expect(state._work_remaining == 29,
		"Work resumes only after world time moves past its previous high-water minute.")
	_set_clock_minute(base_minute + 179)
	_expect(state._work_remaining == 1 and state.wall_hp == 37,
		"A skipped time interval advances repair to one minute before completion.")
	_set_clock_minute(base_minute + 180)
	_expect(state._work_kind.is_empty() and state._work_remaining == 0 and state.wall_hp == 50,
		"Repair restores full HP exactly when its 60-minute job becomes due.")
	_expect(storage.items == {"stone": 7, "wood_log": 5},
		"Repair completion does not consume extra materials.")

func _test_raid_pause_resume_and_breach_refund(base_minute: int) -> void:
	state.wall_hp = 40
	storage.items = {"stone": 10, "wood_log": 5}
	storage_changed_count = 0
	var repair_quote: Dictionary = state.get_work_quote()
	_expect(repair_quote.materials == {"stone": 2} and state.request_wall_work(repair_quote),
		"A two-step repair starts before a non-breaching debug raid.")
	_expect(storage.items == {"stone": 8, "wood_log": 5}, "Repair stock is paid before the raid starts.")
	_expect(state.start_debug_raid(false), "A controlled light debug raid starts while repair is pending.")
	var paused_work_remaining: int = state._work_remaining
	_set_clock_minute(base_minute + 300)
	_expect(state.phase == "attacking" and state._work_remaining == paused_work_remaining,
		"World-time changes do not advance repair during an attack.")
	state.advance_attack(60.0)
	_expect(state.phase == "recovery" and state.get_last_report().outcome == "repelled"
		and state._work_kind == "repair" and state._work_remaining == paused_work_remaining,
		"A repelled raid leaves the interrupted repair pending.")
	_set_clock_minute(base_minute + 360)
	_expect(state._work_kind.is_empty() and state._work_remaining == 0 and state.wall_hp > 4,
		"Pending repair resumes and completes after a repelled raid.")
	_expect(storage.items == {"stone": 8, "wood_log": 5},
		"A resumed repair keeps only its original material charge.")

	state.wall_hp = 30
	storage.items = {"stone": 10, "wood_log": 5}
	storage_changed_count = 0
	repair_quote = state.get_work_quote()
	_expect(repair_quote.materials == {"stone": 4} and state.request_wall_work(repair_quote),
		"A four-step repair starts before a breaching debug raid.")
	_expect(storage.items == {"stone": 6, "wood_log": 5}, "Breached repair materials are held in City Storage's paid balance.")
	_expect(state.start_debug_raid(true), "A controlled heavy debug raid starts while repair is pending.")
	_set_clock_minute(base_minute + 390)
	_expect(state.phase == "attacking" and state._work_remaining == 60 and state.wall_hp == 30,
		"Repair remains paused during the attack until the wall breach resolves.")
	state.advance_attack(30.0)
	_expect(state.phase == "recovery" and state.wall_hp == 0 and state.get_last_report().outcome == "breached",
		"The heavy raid breaches the wall at its sixth five-second hit.")
	_expect(state._work_kind.is_empty() and state._work_remaining == 0 and state._work_paid.is_empty(),
		"A breach cancels the pending repair job and clears its paid-material record.")
	_expect(storage.items == {"stone": 10, "wood_log": 5},
		"A breached repair refunds every paid material to City Storage.")
	_expect("returned to City Storage" in state.last_work_message and storage_changed_count == 2,
		"The refund is reported once after the repair payment and return.")

func _clock_minute() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _set_clock_minute(total_minutes: int) -> void:
	TimeComponentManager.current_day = floori(float(total_minutes) / 1440.0)
	var minute_of_day: int = posmod(total_minutes, 1440)
	TimeComponentManager.current_hour = minute_of_day / 60
	TimeComponentManager.current_minute = minute_of_day % 60
	TimeComponentManager.emit_time_signal()

func _snapshot_globals() -> void:
	inventory_before = Inventory.items.duplicate(true)
	clock_before = {
		"day": TimeComponentManager.current_day,
		"hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute,
		"weather": TimeComponentManager.current_weather,
	}
	clock_paused_before = TimeComponentManager.is_paused
	clock_processing_before = TimeComponentManager.is_processing()

func _on_storage_changed() -> void:
	storage_changed_count += 1

func _finish() -> void:
	if is_instance_valid(state):
		var time_callable: Callable = Callable(state, "_on_time_changed")
		if TimeComponentManager.time_changed.is_connected(time_callable):
			TimeComponentManager.time_changed.disconnect(time_callable)
		state.free()
		state = null
	if is_instance_valid(storage):
		storage.free()
		storage = null
	TimeComponentManager.current_day = int(clock_before.day)
	TimeComponentManager.current_hour = int(clock_before.hour)
	TimeComponentManager.current_minute = int(clock_before.minute)
	TimeComponentManager.current_weather = str(clock_before.weather)
	TimeComponentManager.is_paused = clock_paused_before
	TimeComponentManager.set_process(clock_processing_before)
	print("WallWorkTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
