extends Node

const RAID_CONFIG_SCRIPT: Script = preload("res://scenes/raid/raid_config.gd")
const RAID_STATE_SCRIPT: Script = preload("res://scenes/raid/raid_state.gd")
const CITY_STORAGE_SCRIPT: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")
const WALL_PLAYTEST_CONFIG_PATH: String = "res://scenes/raid/wall_playtest.tres"
const MINUTES_PER_DAY: int = 1440
const TEST_CITIZEN_IDS: Array[String] = [
	"raid_regression_worker",
	"raid_regression_a",
	"raid_regression_b",
	"raid_regression_c"
]

var failures: int = 0
var states: Array[Node] = []
var original_clock_processing: bool = true
var original_clock_paused: bool = false

func _ready() -> void:
	original_clock_processing = TimeComponentManager.is_processing()
	original_clock_paused = TimeComponentManager.is_paused
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = true
	_run.call_deferred()

func _run() -> void:
	_test_wall_build_and_production_defaults()
	_test_attack_hit_counts_and_persistent_damage()
	_test_warning_schedule_and_clock_jumps()
	_test_breach_loot_population_and_report_safety()
	_test_empty_storage_and_invalid_config()
	_cleanup_fixture_citizens()
	for state: Node in states:
		if is_instance_valid(state):
			state.free()
	TimeComponentManager.is_paused = original_clock_paused
	TimeComponentManager.set_process(original_clock_processing)
	print("RaidRegressionTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _test_wall_build_and_production_defaults() -> void:
	var playtest_config: Resource = load(WALL_PLAYTEST_CONFIG_PATH).duplicate(true)
	_expect(playtest_config.instant_build_enabled and playtest_config.wall_max_hp == 50,
		"The loaded production profile retains free construction and the approved 50 HP.")
	_expect(playtest_config.get("raids_enabled") == false
		and playtest_config.call("is_valid") == true,
		"The production wall playtest remains valid with raids disabled.")

	var state: Node = _new_state(_fixture_config())
	_expect(str(state.get("phase")) == "unbuilt" and int(state.get("wall_hp")) == 0
		and int(state.get("_attack_at")) == -1,
		"A new wall begins as ruins with zero HP and no raid scheduled.")
	var starting_minute: int = _now_minute()
	_emit_time_at(state, starting_minute + MINUTES_PER_DAY * 20)
	_expect(str(state.get("phase")) == "unbuilt" and int(state.get("_attack_at")) == -1,
		"Clock advances do not schedule a raid while the wall remains unbuilt.")
	_expect(state.call("build_wall") == true and int(state.get("wall_hp")) == 50
		and int(state.get("wall_level")) == 1 and str(state.get("phase")) == "safe",
		"Building once creates the approved level 1 wall at 50 HP.")
	_expect(int(state.get("_attack_at")) > starting_minute + MINUTES_PER_DAY * 20,
		"The first raid schedule is created only when the wall is built.")
	state.set("wall_hp", 37)
	_expect(state.call("build_wall") == false and int(state.get("wall_hp")) == 37,
		"Building an intact wall again fails and does not heal its damage.")
	state.free()

func _test_attack_hit_counts_and_persistent_damage() -> void:
	var weak_state: Node = _new_state(_fixture_config(1))
	_expect(weak_state.call("build_wall") == true, "The weak-attack fixture builds its wall.")
	_begin_scheduled_attack(weak_state)
	weak_state.call("advance_attack", 4.999)
	_expect(int(weak_state.get("_hits")) == 0 and int(weak_state.get("wall_hp")) == 50,
		"No synthetic hit lands before the approved five-second interval.")
	weak_state.call("advance_attack", 0.001)
	_expect(int(weak_state.get("_hits")) == 1 and int(weak_state.get("wall_hp")) == 49,
		"The first synthetic hit lands exactly at five seconds.")
	weak_state.call("advance_attack", 55.0)
	var weak_report: Dictionary = weak_state.call("get_last_report")
	_expect(int(weak_report.get("hits", 0)) == 12 and int(weak_state.get("wall_hp")) == 38
		and str(weak_state.get("phase")) == "recovery",
		"At the approved 60 seconds and five-second interval, twelve weak synthetic hits leave 38 HP.")
	weak_state.call("advance_attack", 60.0)
	weak_state.call("get_last_report")
	_expect(int(weak_state.get("wall_hp")) == 38 and int(weak_report.get("wall_damage", 0)) == 12,
		"Resolved wall damage persists across repeated advances and report reads.")
	_expect(weak_state.call("build_wall") == false and int(weak_state.get("wall_hp")) == 38,
		"A repeat build attempt after a survived raid does not heal the wall.")

	var defended_state: Node = _new_state(_fixture_config(4, 4))
	_expect(defended_state.call("build_wall") == true, "The defense fixture builds its wall.")
	_begin_scheduled_attack(defended_state)
	defended_state.call("advance_attack", 60.0)
	var defended_report: Dictionary = defended_state.call("get_last_report")
	_expect(int(defended_report.get("hits", 0)) == 12 and int(defended_state.get("wall_hp")) == 50
		and int(defended_report.get("wall_damage", -1)) == 0,
		"Synthetic attacks at or below wall defense deal zero damage.")

func _test_warning_schedule_and_clock_jumps() -> void:
	var lead_state: Node = _new_state(_fixture_config())
	_expect(lead_state.call("build_wall") == true, "The schedule fixture builds its wall.")
	var first_attack_at: int = int(lead_state.get("_attack_at"))
	var warning_start: int = first_attack_at - int(lead_state.get("config").get("warning_days")) * MINUTES_PER_DAY
	_emit_time_at(lead_state, warning_start)
	_expect(str(lead_state.get("phase")) == "warning"
		and int(lead_state.get("_attack_at")) == first_attack_at,
		"The warning begins at its configured synthetic lead time without rerolling the attack schedule.")
	lead_state.free()

	var jump_state: Node = _new_state(_fixture_config())
	_expect(jump_state.call("build_wall") == true, "The jump fixture builds its wall.")
	var planned_attack_at: int = int(jump_state.get("_attack_at"))
	var jumped_to: int = planned_attack_at + MINUTES_PER_DAY * 10
	_emit_time_at(jump_state, jumped_to)
	var prepared_attack_at: int = jumped_to + int(jump_state.get("config").get("warning_days")) * MINUTES_PER_DAY
	_expect(str(jump_state.get("phase")) == "warning"
		and int(jump_state.get("_attack_at")) == prepared_attack_at,
		"A clock jump past an attack creates one warning lead instead of catching up or rerolling raids.")
	_emit_time_at(jump_state, planned_attack_at)
	_expect(str(jump_state.get("phase")) == "warning"
		and int(jump_state.get("_attack_at")) == prepared_attack_at,
		"Rewinding the clock does not change the warning phase or scheduled attack.")
	_emit_time_at(jump_state, prepared_attack_at)
	_expect(str(jump_state.get("phase")) == "attacking" and int(jump_state.get("_hits")) == 0,
		"Advancing to the prepared attack starts one raid with no catch-up hits.")
	jump_state.call("advance_attack", 60.0)
	_expect(str(jump_state.get("phase")) == "recovery"
		and int(jump_state.get("_attack_at")) == prepared_attack_at + 5 * MINUTES_PER_DAY,
		"Finishing a jumped raid schedules one future raid without replaying missed intervals.")

func _test_breach_loot_population_and_report_safety() -> void:
	var worker: CitizenData = _add_test_citizen(TEST_CITIZEN_IDS[0], "Raid Worker", 0.3,
		CitizenData.EmploymentStatus.ASSIGNED)
	var resident_a: CitizenData = _add_test_citizen(TEST_CITIZEN_IDS[1], "Resident A", 0.3)
	var resident_b: CitizenData = _add_test_citizen(TEST_CITIZEN_IDS[2], "Resident B", 0.3,
		CitizenData.EmploymentStatus.APPLICANT)
	var resident_c: CitizenData = _add_test_citizen(TEST_CITIZEN_IDS[3], "Resident C", 0.3)
	var worker_data: WorkerData = WorkerData.new()
	worker_data.worker_id = TEST_CITIZEN_IDS[0]
	WorkerDatabase.workers_by_id[worker_data.worker_id] = worker_data

	var storage: Node = CITY_STORAGE_SCRIPT.new()
	var initial_items: Dictionary = {
		"barley_bread": 3,
		"shekel": 4,
		"simple_clothes": 2
	}
	var initial_portions: Dictionary = {"roasted_drumstick": 1}
	var initial_units: Dictionary = {
		"raid_test_equipped_hammer": {"tool_id": "stone_hammer", "name": "Test Hammer", "worker_id": TEST_CITIZEN_IDS[0]},
		"raid_test_free_glove": {"tool_id": "basic_glove", "name": "Test Glove", "worker_id": ""}
	}
	storage.set("items", initial_items.duplicate(true))
	storage.set("food_portions", initial_portions.duplicate(true))
	storage.set("units", initial_units.duplicate(true))
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	var residents_before: Array[CitizenData] = CitizenManager.get_all_residents()
	var expected_total_satisfaction_drop: float = 0.0
	for citizen: CitizenData in residents_before:
		expected_total_satisfaction_drop += citizen.satisfaction - maxf(0.01, citizen.satisfaction - 0.8)
	var expected_satisfaction_drop: float = expected_total_satisfaction_drop / residents_before.size()

	var state: Node = _new_state(_fixture_config(9, 0, 4, 0.8, 1))
	state.set("storage", storage)
	_expect(state.call("build_wall") == true, "The breach fixture builds its wall.")
	_begin_scheduled_attack(state)
	state.call("advance_attack", 30.0)
	_expect(int(state.get("wall_hp")) == 0 and str(state.get("phase")) == "recovery",
		"The stronger synthetic attack reduces wall HP to exactly zero on its sixth hit.")
	var authoritative_report: Dictionary = state.call("get_last_report")
	var stolen: Dictionary = authoritative_report.get("stolen", {})
	var stolen_total: int = 0
	for item_id: String in initial_items:
		var amount_stolen: int = int(stolen.get(item_id, 0))
		stolen_total += amount_stolen
		var remaining_amount: int = int(storage.get("items").get(item_id, 0))
		_expect(remaining_amount + amount_stolen == int(initial_items[item_id]),
			"Raid loot conserves the actual %s stack quantity." % item_id)
		_expect(remaining_amount >= 1,
			"Raid loot preserves the synthetic one-unit reserve for %s." % item_id)
	_expect(stolen_total == 4 and stolen_total <= 4,
		"Loot theft is bounded by the synthetic four-stack capacity.")
	_expect(storage.get("food_portions") == initial_portions,
		"Raid loot leaves opened food portions untouched.")
	_expect(storage.get("units") == initial_units,
		"Raid loot leaves assigned and unassigned equipment untouched.")
	_expect(Inventory.items == inventory_before,
		"Raid loot does not mutate the player's inventory.")
	var fled_count: int = 0
	for citizen: CitizenData in [worker, resident_a, resident_b, resident_c]:
		if citizen.population_status == CitizenData.PopulationStatus.LEFT_CITY:
			fled_count += 1
	_expect(fled_count == 1,
		"A breach with three eligible synthetic nonworkers sends at most one resident away.")
	_expect(not CitizenManager.get_all_residents().is_empty(),
		"At least one resident remains in the city after the breach.")
	_expect(worker.population_status == CitizenData.PopulationStatus.RESIDENT
		and worker.employment_status == CitizenData.EmploymentStatus.ASSIGNED,
		"A worker with WorkerDatabase data remains employed and resident after the breach.")
	_expect(resident_a.satisfaction == 0.01 and resident_b.satisfaction == 0.01
		and resident_c.satisfaction == 0.01 and worker.satisfaction == 0.01,
		"The synthetic satisfaction penalty clamps every test resident at the 0.01 floor.")
	_expect(is_equal_approx(float(authoritative_report.get("satisfaction_drop", -1.0)), expected_satisfaction_drop),
		"The report records the population's average clamped satisfaction loss.")
	_expect(int(authoritative_report.get("hits", 0)) == 6
		and int(authoritative_report.get("wall_damage", 0)) == 50,
		"The breach report preserves the exact six-hit wall damage result.")

	var displayed_report: Dictionary = state.call("get_last_report")
	var displayed_stolen: Dictionary = displayed_report.get("stolen", {})
	displayed_stolen["barley_bread"] = 999
	displayed_report["stolen"] = displayed_stolen
	displayed_report["outcome"] = "edited"
	displayed_report["citizens_fled"] = []
	var reread_report: Dictionary = state.call("get_last_report")
	_expect(str(reread_report.get("outcome", "")) == "breached"
		and int(reread_report.get("stolen", {}).get("barley_bread", 0)) != 999
		and reread_report.get("citizens_fled", []).size() == 1,
		"Editing a report copy does not change the authoritative report.")
	state.call("advance_attack", 60.0)
	state.call("get_last_report")
	_expect(int(state.get("_report_sequence")) == 1
		and storage.get("items") == {"barley_bread": 1, "shekel": 2, "simple_clothes": 2}
		and Inventory.items == inventory_before,
		"Repeated attack advances and report reads do not resolve theft or population effects twice.")
	storage.free()

func _test_empty_storage_and_invalid_config() -> void:
	var invalid_config: Resource = _fixture_config()
	invalid_config.set("hit_interval_seconds", 0.0)
	_expect(invalid_config.call("is_valid") == false,
		"Malformed raid configuration is rejected by validation without instantiating an error-logging state.")

	var empty_storage: Node = CITY_STORAGE_SCRIPT.new()
	var empty_state: Node = _new_state(_fixture_config(9, 0, 4, 0.0, 0))
	empty_state.set("storage", empty_storage)
	_expect(empty_state.call("build_wall") == true, "The empty-stock fixture builds its wall.")
	_begin_scheduled_attack(empty_state)
	empty_state.call("advance_attack", 30.0)
	var report: Dictionary = empty_state.call("get_last_report")
	_expect(report.get("stolen", {}) == {} and empty_storage.get("items") == {},
		"A breached city with empty counted stock reports no theft and remains empty.")
	empty_storage.free()

func _fixture_config(
	attack: int = 1,
	defend: int = 0,
	loot_capacity: int = 0,
	satisfaction_penalty: float = 0.0,
	max_fleeing: int = 0
) -> Resource:
	# Fixture-only values below are deterministic test inputs, not gameplay balance.
	var config: Resource = RAID_CONFIG_SCRIPT.new()
	config.set("raids_enabled", true)
	config.set("instant_build_enabled", true)
	config.set("wall_max_hp", 50) # Approved first wall playtest value.
	config.set("wall_defend", defend) # Synthetic fixture defense.
	config.set("duration_seconds", 60.0) # Approved maximum raid duration.
	config.set("hit_interval_seconds", 5.0) # Approved hit interval.
	config.set("attack_min", attack) # Synthetic fixture attack strength.
	config.set("attack_max", attack)
	config.set("interval_min_days", 5) # Synthetic fixed schedule interval.
	config.set("interval_max_days", 5)
	config.set("warning_days", 1) # Synthetic warning lead for schedule tests.
	config.set("theft_capacity", loot_capacity) # Synthetic loot bound.
	config.set("reserve_per_stack", 1) # Synthetic reserve for conservation checks.
	config.set("satisfaction_penalty", satisfaction_penalty) # Synthetic population loss.
	config.set("max_fleeing_residents", max_fleeing)
	return config

func _new_state(config: Resource) -> Node:
	var state: Node = RAID_STATE_SCRIPT.new()
	state.set("config", config)
	add_child(state)
	states.append(state)
	return state

func _begin_scheduled_attack(state: Node) -> void:
	var attack_at: int = int(state.get("_attack_at"))
	var warning_days: int = int(state.get("config").get("warning_days"))
	_emit_time_at(state, attack_at - warning_days * MINUTES_PER_DAY)
	_emit_time_at(state, int(state.get("_attack_at")))
	_expect(str(state.get("phase")) == "attacking",
		"The deterministic fixture advances through warning into an attack.")

func _emit_time_at(state: Node, total_minutes: int) -> void:
	var day: int = total_minutes / MINUTES_PER_DAY
	var minute_of_day: int = posmod(total_minutes, MINUTES_PER_DAY)
	state.call("_on_time_changed", day, minute_of_day / 60, minute_of_day % 60, "clear")

func _now_minute() -> int:
	return TimeComponentManager.current_day * MINUTES_PER_DAY \
		+ TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _add_test_citizen(
	citizen_id: String,
	display_name: String,
	satisfaction: float,
	employment: CitizenData.EmploymentStatus = CitizenData.EmploymentStatus.UNEMPLOYED
) -> CitizenData:
	var citizen: CitizenData = CitizenData.new()
	citizen.citizen_id = citizen_id
	citizen.display_name = display_name
	citizen.satisfaction = satisfaction
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = employment
	CitizenManager.add_citizen(citizen)
	return citizen

func _cleanup_fixture_citizens() -> void:
	for citizen_id: String in TEST_CITIZEN_IDS:
		CitizenManager.citizens_by_id.erase(citizen_id)
		WorkerDatabase.workers_by_id.erase(citizen_id)

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
