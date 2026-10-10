extends Node

const CITY_PROGRESS_SCRIPT: Script = preload("res://scenes/city_progression/city_progression_state.gd")
const RAID_CONFIG_SCRIPT: Script = preload("res://scenes/raid/raid_config.gd")
const RAID_STATE_SCRIPT: Script = preload("res://scenes/raid/raid_state.gd")
const CITY_STORAGE_SCRIPT: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")
const PARTY_PROFILE: Resource = preload("res://scenes/raid/mixed_raider_party.tres")
const TEST_CITIZEN_ID: String = "city_progression_needs_resident"
const NEEDS_PROPERTIES: Array[String] = [
	"last_food_fulfilled_count", "last_food_unfulfilled_count",
	"last_clothing_fulfilled_count", "last_clothing_unfulfilled_count",
	"last_shelter_capacity_fulfilled_count", "last_shelter_capacity_unfulfilled_count",
	"last_processed_day", "last_food_processed_day", "last_clothing_processed_day",
	"_processing_daily_needs", "_processing_food", "_processing_clothing",
	"clothing_allocations", "last_needs_results"
]

var failures: int = 0
var city_progress: Node
var raid_state: Node
var storage: Node
var created_storage: bool = false
var original_citizens: Dictionary = {}
var original_workers: Dictionary = {}
var original_dismissed_workers: Dictionary = {}
var original_inventory: Dictionary = {}
var original_city_stock: Dictionary = {}
var original_clock: Dictionary = {}
var original_needs_state: Dictionary = {}
var original_storage_state: Dictionary = {}
var original_clock_processing: bool = true
var breach_signal_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_snapshot_globals()
	_prepare_isolated_runtime()
	_create_fixture()

	_test_threat_stages_and_manual_level_up()
	_test_direct_daily_settlement()
	_test_needs_processing_awards_consumed_food()
	_test_real_breach_and_breach_deduplication()
	_test_missing_wall_penalty_after_breach()

	_cleanup_fixture()
	_restore_globals()
	print("CityProgressionTest %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)


func _snapshot_globals() -> void:
	original_citizens = CitizenManager.citizens_by_id.duplicate()
	original_workers = WorkerDatabase.workers_by_id.duplicate(true)
	original_dismissed_workers = WorkerDatabase.dismissed_workers.duplicate(true)
	original_inventory = Inventory.items.duplicate(true)
	original_city_stock = {
		"food_supply": CityStockManager.food_supply,
		"clothing_supply": CityStockManager.clothing_supply,
		"treasury_shekel": CityStockManager.treasury_shekel,
		"shelter_capacity": CityStockManager.shelter_capacity
	}
	original_clock = {
		"day": TimeComponentManager.current_day,
		"hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute,
		"weather": TimeComponentManager.current_weather,
		"paused": TimeComponentManager.is_paused,
		"tree_paused": get_tree().paused
	}
	original_clock_processing = TimeComponentManager.is_processing()
	for property_name: String in NEEDS_PROPERTIES:
		if not _has_property(CitizenNeedsManager, property_name):
			continue
		var value: Variant = CitizenNeedsManager.get(property_name)
		if value is Dictionary or value is Array:
			value = value.duplicate(true)
		original_needs_state[property_name] = value

	storage = get_node_or_null("/root/WorkStateRuntime/CityToolStorage")
	if is_instance_valid(storage):
		original_storage_state = _snapshot_storage(storage)


func _prepare_isolated_runtime() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	CitizenManager.citizens_by_id.clear()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()

	if not is_instance_valid(storage):
		storage = CITY_STORAGE_SCRIPT.new()
		storage.name = "CityToolStorage"
		WorkStateRuntime.add_child(storage)
		created_storage = true
	storage.set("items", {})
	storage.set("food_portions", {})
	CityStockManager.shelter_capacity = 0


func _create_fixture() -> void:
	var config: Resource = RAID_CONFIG_SCRIPT.new()
	config.set("raids_enabled", true)
	config.set("instant_build_enabled", true)
	config.set("wall_max_hp", 50)
	config.set("wall_defend", 2)
	config.set("warning_days", 1)
	config.set("party_profile", PARTY_PROFILE)
	config.set("max_fleeing_residents", 0)
	config.set("satisfaction_penalty", 0.0)
	config.set("ranked_looting_enabled", false)

	raid_state = RAID_STATE_SCRIPT.new()
	raid_state.set("config", config)
	add_child(raid_state)

	city_progress = CITY_PROGRESS_SCRIPT.new()
	add_child(city_progress)
	city_progress.call("bind_raid", raid_state)
	raid_state.connect("wall_breached", _on_breach_signal)
	_expect(bool(raid_state.call("build_wall")), "The real RaidState fixture builds its wall.")
	_expect(int(raid_state.get("wall_hp")) > 0,
		"The real RaidState fixture starts with a standing wall.")


func _test_threat_stages_and_manual_level_up() -> void:
	var departed_party: Dictionary = raid_state.get("_party").duplicate(true)
	_expect(city_progress.call("get_threat_stage") == &"early"
		and raid_state.get("_composition_stage") == &"early"
		and str(departed_party.get("stage_id", "")) == "early",
		"Level 1 selects the early threat stage and the departing party records it.")

	city_progress.set("progress", 100)
	_expect(bool(city_progress.call("request_level_up"))
		and int(city_progress.get("level")) == 2
		and int(city_progress.get("progress")) == 0
		and city_progress.call("get_threat_stage") == &"developing"
		and raid_state.get("_composition_stage") == &"developing",
		"A manual level-up at 100 resets progress and moves level 2 to developing threats.")
	_expect(raid_state.get("_party") == departed_party,
		"Changing the city threat stage leaves a party that already departed unchanged.")
	_expect(not bool(city_progress.call("request_level_up"))
		and int(city_progress.get("level")) == 2
		and int(city_progress.get("progress")) == 0,
		"A repeated level-up click cannot advance again after progress resets below 100.")

	city_progress.set("progress", 100)
	_expect(bool(city_progress.call("request_level_up"))
		and int(city_progress.get("level")) == 3
		and int(city_progress.get("progress")) == 0
		and city_progress.call("get_threat_stage") == &"advanced"
		and raid_state.get("_composition_stage") == &"advanced",
		"Level 3 selects the advanced threat stage after the second manual level-up.")
	_expect(raid_state.get("_party") == departed_party,
		"The advanced stage applies only to future parties, preserving the departed party snapshot.")
	_expect(not bool(city_progress.call("request_level_up"))
		and int(city_progress.get("level")) == 3,
		"A second repeated click at zero progress does not produce another level.")


func _test_direct_daily_settlement() -> void:
	var first_day: int = int(original_clock.day) + 1
	var fully_served: Array[Dictionary] = [
		_needs_result(first_day, true, true, 0.8),
		_needs_result(first_day, true, true, 0.6)
	]
	_expect(_settle_day(first_day, fully_served, true),
		"A new completed day settles once for its full resident cohort.")
	var daily: Dictionary = city_progress.get("last_daily")
	_expect(int(daily.get("food", 0)) == 5
		and int(daily.get("clothing", 0)) == 5
		and int(daily.get("satisfaction", 0)) == 5,
		"All-fed and all-clothed residents whose average satisfaction is exactly 0.70 earn each +5 daily bonus.")
	var progress_after_full_day: int = int(city_progress.get("progress"))
	_expect(progress_after_full_day == 15
		and not _settle_day(first_day, fully_served, true)
		and int(city_progress.get("progress")) == progress_after_full_day,
		"A repeated settlement for the same day cannot award its bonuses twice.")

	var incomplete_day: int = first_day + 1
	var incomplete_cohort: Array[Dictionary] = [
		_needs_result(incomplete_day, true, true, 0.7),
		_needs_result(incomplete_day, false, false, 0.68)
	]
	_expect(_settle_day(incomplete_day, incomplete_cohort, true),
		"The next day accepts a cohort with unmet needs.")
	daily = city_progress.get("last_daily")
	_expect(int(daily.get("food", -1)) == 0
		and int(daily.get("clothing", -1)) == 0
		and int(daily.get("satisfaction", -1)) == 0
		and int(daily.get("total", -1)) == 0,
		"One unserved resident blocks all-or-nothing food and clothing bonuses, and a 0.69 average misses satisfaction.")

	var empty_day: int = incomplete_day + 1
	_expect(_settle_day(empty_day, [], true), "An empty resident cohort still closes its day.")
	daily = city_progress.get("last_daily")
	_expect(int(daily.get("food", -1)) == 0
		and int(daily.get("clothing", -1)) == 0
		and int(daily.get("satisfaction", -1)) == 0
		and int(daily.get("total", -1)) == 0,
		"A zero-resident day grants no food, clothing, or satisfaction bonuses.")


func _test_needs_processing_awards_consumed_food() -> void:
	var day: int = int(original_clock.day) + 4
	var resident: CitizenData = _make_resident(TEST_CITIZEN_ID)
	resident.employment_status = CitizenData.EmploymentStatus.HIRED
	resident.satisfaction = 0.7
	CitizenManager.add_citizen(resident)
	CityStockManager.shelter_capacity = 1
	storage.set("items", {"barley_bread": 1, "simple_clothes": 1})
	storage.set("food_portions", {})
	_expect(int(storage.call("get_food_supply_points")) == 1,
		"The live needs fixture begins with exactly one food point for one resident.")

	TimeComponentManager.current_day = day
	CitizenNeedsManager.set("last_processed_day", day - 1)
	CitizenNeedsManager.set("last_food_processed_day", day - 1)
	CitizenNeedsManager.set("last_clothing_processed_day", day - 1)
	CitizenNeedsManager.set("_processing_daily_needs", false)
	CitizenNeedsManager.set("_processing_food", false)
	CitizenNeedsManager.set("_processing_clothing", false)
	CitizenNeedsManager.set("clothing_allocations", {})
	CitizenNeedsManager.set("last_needs_results", {})

	CitizenNeedsManager.call("process_daily_needs")
	var result: Dictionary = CitizenNeedsManager.get("last_needs_results").get(TEST_CITIZEN_ID, {})
	var progress_after_needs: int = int(city_progress.get("progress"))
	_expect(bool(result.get("evaluated", false))
		and int(result.get("day", -1)) == day
		and bool(result.get("food", false))
		and bool(result.get("clothing", false))
		and bool(result.get("shelter", false)),
		"process_daily_needs records the resident's completed food, clothing, and shelter evaluation.")
	_expect(int(storage.call("get_food_supply_points")) == 0
		and not storage.get("items").has("barley_bread"),
		"Daily-needs processing consumes the only available food point.")
	var daily: Dictionary = city_progress.get("last_daily")
	_expect(int(daily.get("food", 0)) == 5
		and int(daily.get("clothing", 0)) == 5
		and int(daily.get("satisfaction", 0)) == 5
		and progress_after_needs >= 30,
		"The needs_changed signal awards food after the exact available food stock has been consumed.")

	CitizenNeedsManager.needs_changed.emit()
	_expect(int(city_progress.get("progress")) == progress_after_needs,
		"Re-emitting needs_changed for an already-awarded day does not grant a second bonus.")


func _test_real_breach_and_breach_deduplication() -> void:
	city_progress.set("progress", 5)
	_expect(bool(raid_state.call("start_debug_raid", true)),
		"The real RaidState starts a deterministic breach against its standing wall.")
	raid_state.set_process(false)
	raid_state.call("advance_attack", 50.0)
	var report: Dictionary = raid_state.call("get_last_report")
	_expect(int(raid_state.get("wall_hp")) == 0
		and str(report.get("outcome", "")) == "breached"
		and int(report.get("buildings_destroyed", {}).get("Castle wall", 0)) == 1,
		"A real RaidState breach destroys a wall that was standing when the attack began.")
	_expect(breach_signal_count == 1
		and int(city_progress.get("progress")) == 0
		and str(city_progress.get("last_event")) == "Wall breached: -10",
		"A real breach signal applies one -10 penalty and clamps low progress at zero.")

	city_progress.set("progress", 23)
	raid_state.emit_signal("wall_breached", int(report.get("id", 1)))
	_expect(breach_signal_count == 2 and int(city_progress.get("progress")) == 23,
		"A repeated breach id cannot apply a second penalty even when progress is above zero.")

	city_progress.set("progress", 5)
	city_progress.call("_on_wall_breached", 2)
	_expect(int(city_progress.get("progress")) == 0,
		"A distinct breach id applies its penalty and clamps progress at zero.")
	city_progress.set("progress", 25)
	city_progress.call("_on_wall_breached", 2)
	_expect(int(city_progress.get("progress")) == 25,
		"A previously applied breach id remains deduplicated after progress changes.")
	city_progress.set("progress", 5)
	city_progress.call("_on_wall_breached", 3)
	_expect(int(city_progress.get("progress")) == 0,
		"Each new breach id subtracts ten without allowing negative progress.")

	city_progress.set("progress", 23)
	raid_state.set("phase", "warning")
	raid_state.call("_start_attack", 7)
	var ruined_report: Dictionary = raid_state.call("get_last_report")
	_expect(str(ruined_report.get("outcome", "")) == "breached"
		and ruined_report.get("buildings_destroyed", {}).is_empty()
		and breach_signal_count == 2
		and int(city_progress.get("progress")) == 23,
		"Resolving a real RaidState breach from existing ruins creates no second wall-breach event or city penalty.")


func _test_missing_wall_penalty_after_breach() -> void:
	var day: int = int(original_clock.day) + 5
	var result: Array[Dictionary] = [_needs_result(day, true, true, 1.0)]
	_expect(_settle_day(day, result, false),
		"A completed day settles with the wall absent after a confirmed breach.")
	var daily: Dictionary = city_progress.get("last_daily")
	_expect(int(daily.get("food", 0)) == 5
		and int(daily.get("clothing", 0)) == 5
		and int(daily.get("satisfaction", 0)) == 5
		and int(daily.get("wall", 0)) == -5
		and int(daily.get("total", 0)) == 10,
		"An absent wall applies the daily -5 penalty alongside otherwise earned bonuses.")


func _settle_day(day: int, residents: Array[Dictionary], wall_standing: bool) -> bool:
	return bool(city_progress.call("settle_day", day, residents, wall_standing))


func _needs_result(day: int, food: bool, clothing: bool, satisfaction: float) -> Dictionary:
	return {
		"evaluated": true,
		"day": day,
		"food": food,
		"clothing": clothing,
		"satisfaction": satisfaction
	}


func _make_resident(citizen_id: String) -> CitizenData:
	var resident: CitizenData = CitizenData.new()
	resident.citizen_id = citizen_id
	resident.display_name = "Progression Test Resident"
	resident.population_status = CitizenData.PopulationStatus.RESIDENT
	resident.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	return resident


func _on_breach_signal(_raid_id: int) -> void:
	breach_signal_count += 1


func _snapshot_storage(target: Node) -> Dictionary:
	var snapshot: Dictionary = {}
	for property_name: String in ["items", "food_portions", "units"]:
		var value: Variant = target.get(property_name)
		if value is Dictionary:
			snapshot[property_name] = value.duplicate(true)
	for property_name: String in ["_unit_sequence", "_transfer_in_progress"]:
		if _has_property(target, property_name):
			snapshot[property_name] = target.get(property_name)
	return snapshot


func _cleanup_fixture() -> void:
	if is_instance_valid(raid_state) and raid_state.is_connected("wall_breached", _on_breach_signal):
		raid_state.disconnect("wall_breached", _on_breach_signal)
	if is_instance_valid(city_progress):
		city_progress.free()
		city_progress = null
	if is_instance_valid(raid_state):
		raid_state.free()
		raid_state = null
	if created_storage and is_instance_valid(storage):
		storage.free()
		storage = null
		created_storage = false


func _restore_globals() -> void:
	CitizenManager.citizens_by_id = original_citizens.duplicate()
	WorkerDatabase.workers_by_id = original_workers.duplicate(true)
	WorkerDatabase.dismissed_workers = original_dismissed_workers.duplicate(true)
	Inventory.items = original_inventory.duplicate(true)
	CityStockManager.food_supply = int(original_city_stock.food_supply)
	CityStockManager.clothing_supply = int(original_city_stock.clothing_supply)
	CityStockManager.treasury_shekel = int(original_city_stock.treasury_shekel)
	CityStockManager.shelter_capacity = int(original_city_stock.shelter_capacity)
	TimeComponentManager.current_day = int(original_clock.day)
	TimeComponentManager.current_hour = int(original_clock.hour)
	TimeComponentManager.current_minute = int(original_clock.minute)
	TimeComponentManager.current_weather = str(original_clock.weather)
	TimeComponentManager.is_paused = bool(original_clock.paused)
	get_tree().paused = bool(original_clock.tree_paused)
	for property_name: String in original_needs_state.keys():
		if _has_property(CitizenNeedsManager, property_name):
			CitizenNeedsManager.set(property_name, original_needs_state[property_name])
	TimeComponentManager.set_process(original_clock_processing)
	if not created_storage and is_instance_valid(storage):
		for property_name: String in ["items", "food_portions", "units"]:
			if original_storage_state.has(property_name):
				storage.set(property_name, original_storage_state[property_name].duplicate(true))
		for property_name: String in ["_unit_sequence", "_transfer_in_progress"]:
			if original_storage_state.has(property_name):
				storage.set(property_name, original_storage_state[property_name])


func _has_property(target: Object, property_name: String) -> bool:
	for property_info: Dictionary in target.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
