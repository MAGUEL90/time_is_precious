extends Node

const CITY_TOOL_STORAGE_SCRIPT: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")
const RAID_STATE_SCRIPT: Script = preload("res://scenes/raid/raid_state.gd")
const RAID_CONFIG_SCRIPT: Script = preload("res://scenes/raid/raid_config.gd")

const FULL_ID: String = "condition_full"
const TWO_NEEDS_ID: String = "condition_two_needs"
const ONE_NEED_ID: String = "condition_one_need"
const EMPTY_ID: String = "condition_empty"
const LEGACY_WORKER_ID: String = "condition_legacy_worker"
const READY_BREAD: String = "barley_bread"
const SIMPLE_CLOTHES: String = "simple_clothes"
const DAILY_STEP: float = 0.05
const MINUTES_PER_DAY: int = 1440
const ZERO_DEPARTURE_ID: String = "condition_zero_departure"

var failures: int = 0
var fixture_day: int = 0
var provider: Node
var created_provider: bool = false

var original_citizens: Dictionary = {}
var original_workers: Dictionary = {}
var original_dismissed_workers: Dictionary = {}
var original_clock: Dictionary = {}
var original_city_stock: Dictionary = {}
var original_needs_state: Dictionary = {}
var original_provider_state: Dictionary = {}
var original_city_progress_state: Dictionary = {}
var city_progress_state: Node


func _ready() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	# Allow the autoload manager's deferred roster/storage bindings to complete.
	await get_tree().process_frame
	_snapshot_global_state()
	_prepare_fixture()
	_test_stock_preview_before_settlement()
	_test_actual_allocations_and_duplicate_settlement()
	_test_stock_preview_after_settlement()
	_test_raid_refreshes_actual_satisfaction()
	_test_empty_day_then_condition_recovery()
	_test_all_condition_targets_and_step_boundaries()
	_test_exact_zero_departure()
	_restore_global_state()

	if failures > 0:
		push_error("SatisfactionConditionTest FAILED (%d failure(s))" % failures)
		get_tree().quit(1)
		return

	print("SatisfactionConditionTest PASSED")
	get_tree().quit(0)


func _snapshot_global_state() -> void:
	original_citizens = CitizenManager.citizens_by_id.duplicate()
	original_workers = WorkerDatabase.workers_by_id.duplicate()
	original_dismissed_workers = WorkerDatabase.dismissed_workers.duplicate()
	original_clock = {
		"day": TimeComponentManager.current_day,
		"hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute,
		"timer": TimeComponentManager._timer,
		"processing": TimeComponentManager.is_processing(),
		"paused": TimeComponentManager.is_paused,
		"tree_paused": get_tree().paused
	}
	original_city_stock = {"shelter_capacity": CityStockManager.shelter_capacity}
	for property_name: String in [
		"last_food_fulfilled_count", "last_food_unfulfilled_count",
		"last_clothing_fulfilled_count", "last_clothing_unfulfilled_count",
		"last_shelter_capacity_fulfilled_count", "last_shelter_capacity_unfulfilled_count",
		"last_processed_day", "last_food_processed_day", "last_clothing_processed_day",
		"_processing_daily_needs", "_processing_food", "_processing_clothing",
		"_daily_needs_retry_pending", "_daily_needs_retry_after_frame",
		"clothing_allocations", "last_needs_results", "food_coverage_until",
		"satisfaction_last_minute", "_satisfaction_retry_pending", "_food_recheck_pending"
	]:
		var value: Variant = CitizenNeedsManager.get(property_name)
		if value is Dictionary or value is Array:
			value = value.duplicate(true)
		original_needs_state[property_name] = value

	provider = get_node_or_null("/root/WorkStateRuntime/CityToolStorage")
	if is_instance_valid(provider):
		original_provider_state = _snapshot_provider(provider)
	city_progress_state = get_node_or_null("/root/WorkStateRuntime/CityProgression")
	if is_instance_valid(city_progress_state):
		for property_name: String in ["level", "progress", "last_daily", "last_event", "last_awarded_day", "_last_breach_id"]:
			var value: Variant = city_progress_state.get(property_name)
			if value is Dictionary or value is Array:
				value = value.duplicate(true)
			original_city_progress_state[property_name] = value


func _snapshot_provider(target: Node) -> Dictionary:
	var snapshot: Dictionary = {}
	for property_name: String in ["items", "food_portions"]:
		var value: Variant = target.get(property_name)
		if value is Dictionary:
			snapshot[property_name] = value.duplicate(true)
	return snapshot


func _prepare_fixture() -> void:
	TimeComponentManager.set_process(false)
	if not is_instance_valid(provider):
		provider = CITY_TOOL_STORAGE_SCRIPT.new()
		provider.name = "CityToolStorage"
		WorkStateRuntime.add_child(provider)
		created_provider = true

	CitizenManager.citizens_by_id.clear()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	CitizenManager.citizens_by_id[FULL_ID] = _make_resident(FULL_ID, 0.05)
	var two_needs: CitizenData = _make_resident(TWO_NEEDS_ID, 0.99)
	two_needs.employment_status = CitizenData.EmploymentStatus.HIRED
	CitizenManager.citizens_by_id[TWO_NEEDS_ID] = two_needs
	CitizenManager.citizens_by_id[ONE_NEED_ID] = _make_resident(ONE_NEED_ID, 0.33)
	CitizenManager.citizens_by_id[EMPTY_ID] = _make_resident(EMPTY_ID, 0.30)

	var linked_worker: WorkerData = WorkerData.new()
	linked_worker.worker_id = TWO_NEEDS_ID
	linked_worker.satisfaction = 0.1
	WorkerDatabase.workers_by_id[TWO_NEEDS_ID] = linked_worker
	var legacy_worker: WorkerData = WorkerData.new()
	legacy_worker.worker_id = LEGACY_WORKER_ID
	legacy_worker.display_name = "Unlinked worker"
	legacy_worker.satisfaction = 0.70
	WorkerDatabase.workers_by_id[LEGACY_WORKER_ID] = legacy_worker

	fixture_day = TimeComponentManager.current_day + 100
	TimeComponentManager.current_day = fixture_day
	TimeComponentManager.current_hour = 0
	TimeComponentManager.current_minute = 0
	TimeComponentManager._timer = 0.0
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	CitizenNeedsManager.last_processed_day = fixture_day - 1
	CitizenNeedsManager.last_food_processed_day = fixture_day - 1
	CitizenNeedsManager.last_clothing_processed_day = fixture_day - 1
	CitizenNeedsManager.last_food_fulfilled_count = 0
	CitizenNeedsManager.last_food_unfulfilled_count = 0
	CitizenNeedsManager.last_clothing_fulfilled_count = 0
	CitizenNeedsManager.last_clothing_unfulfilled_count = 0
	CitizenNeedsManager.last_shelter_capacity_fulfilled_count = 0
	CitizenNeedsManager.last_shelter_capacity_unfulfilled_count = 0
	CitizenNeedsManager._processing_daily_needs = false
	CitizenNeedsManager._processing_food = false
	CitizenNeedsManager._processing_clothing = false
	CitizenNeedsManager._daily_needs_retry_pending = false
	CitizenNeedsManager._daily_needs_retry_after_frame = false
	CitizenNeedsManager._satisfaction_retry_pending = false
	CitizenNeedsManager._food_recheck_pending = false
	CitizenNeedsManager.clothing_allocations.clear()
	CitizenNeedsManager.last_needs_results.clear()
	CitizenNeedsManager.food_coverage_until.clear()
	CitizenNeedsManager.satisfaction_last_minute.clear()

	provider.set("items", {READY_BREAD: 3, SIMPLE_CLOTHES: 1})
	provider.set("food_portions", {})
	CityStockManager.shelter_capacity = 2
	var now: int = fixture_day * MINUTES_PER_DAY
	for person_id: String in [FULL_ID, TWO_NEEDS_ID, ONE_NEED_ID, EMPTY_ID, LEGACY_WORKER_ID]:
		CitizenNeedsManager.satisfaction_last_minute[person_id] = now


func _make_resident(citizen_id: String, satisfaction: float) -> CitizenData:
	var citizen: CitizenData = CitizenData.new()
	citizen.citizen_id = citizen_id
	citizen.display_name = citizen_id
	citizen.satisfaction = satisfaction
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	return citizen


func _test_stock_preview_before_settlement() -> void:
	_expect(CitizenNeedsManager.get_food_consumer_count() == 5,
		"Four residents and one unlinked worker make five unique daily consumers.")
	_expect(CitizenManager.get_all_residents().size() == 4,
		"The linked worker remains part of the resident cohort only once.")
	_expect(int(CitizenNeedsManager.get_food_supply_summary(provider).consumer_count) == 5
		and int(CitizenNeedsManager.get_clothing_supply_summary(provider).consumer_count) == 5,
		"Food and clothing stock summaries include the unlinked worker without duplicating the linked one.")

	var full_before: Dictionary = CitizenNeedsManager.get_person_needs_summary(FULL_ID)
	_expect(bool(full_before.evaluated) and is_equal_approx(float(full_before.condition_target), 0.0)
		and str(full_before.trend) == "down",
		"A live pre-settlement summary reports current unfulfilled services and their actual target.")
	_expect(is_equal_approx(float(full_before.satisfaction), 0.05)
		and int(full_before.food_stock) == 3 and int(full_before.clothing_stock) == 1
		and int(full_before.shelter_capacity) == 2,
		"A pre-settlement summary reports actual satisfaction and shared stock separately.")
	_expect(provider.get("items") == {READY_BREAD: 3, SIMPLE_CLOTHES: 1}
		and full_before.food == false and full_before.clothing == false and full_before.shelter == false,
		"Reading the summary neither consumes reserves nor changes fulfillment flags.")


func _test_actual_allocations_and_duplicate_settlement() -> void:
	var needs_changed_count: Array[int] = [0]
	var reentrant_callback := func() -> void:
		needs_changed_count[0] += 1
		CitizenNeedsManager.process_daily_needs()
	CitizenNeedsManager.needs_changed.connect(reentrant_callback)
	CitizenNeedsManager.process_daily_needs()
	CitizenNeedsManager.needs_changed.disconnect(reentrant_callback)

	var full: Dictionary = CitizenNeedsManager.get_person_needs_summary(FULL_ID)
	var two: Dictionary = CitizenNeedsManager.get_person_needs_summary(TWO_NEEDS_ID)
	var one: Dictionary = CitizenNeedsManager.get_person_needs_summary(ONE_NEED_ID)
	var empty: Dictionary = CitizenNeedsManager.get_person_needs_summary(EMPTY_ID)
	var legacy: Dictionary = CitizenNeedsManager.get_person_needs_summary(LEGACY_WORKER_ID)
	_expect(needs_changed_count[0] == 1 and CitizenNeedsManager.last_needs_results.size() == 5,
		"One settlement and its reentrant callback record exactly one result per unique recipient.")
	_expect(bool(full.food) and bool(full.clothing) and bool(full.shelter)
		and bool(two.food) and not bool(two.clothing) and bool(two.shelter)
		and bool(one.food) and not bool(one.clothing) and not bool(one.shelter)
		and not bool(empty.food) and not bool(empty.clothing) and not bool(empty.shelter),
		"Actual physical stock and the two-place shelter capacity produce distinct resident outcomes.")
	_expect(not bool(legacy.food) and not bool(legacy.clothing) and not bool(legacy.shelter),
		"The unlinked worker is evaluated after residents and receives only unallocated shelter capacity.")
	_expect(is_equal_approx(float(full.condition_target), 0.99)
		and is_equal_approx(float(two.condition_target), 0.66)
		and is_equal_approx(float(one.condition_target), 0.33)
		and is_equal_approx(float(empty.condition_target), 0.0)
		and is_equal_approx(float(legacy.condition_target), 0.0),
		"Actual fulfillment maps to 0, 0.33, 0.66, or 0.99 condition targets.")
	_expect(is_equal_approx(float(full.satisfaction), 0.05)
		and is_equal_approx(float(two.satisfaction), 0.99)
		and is_equal_approx(float(one.satisfaction), 0.33)
		and is_equal_approx(float(empty.satisfaction), 0.30)
		and is_equal_approx(float(legacy.satisfaction), 0.70),
		"A same-minute needs settlement records service without a daily Satisfaction jump.")
	for person_id: String in [FULL_ID, TWO_NEEDS_ID, ONE_NEED_ID, EMPTY_ID, LEGACY_WORKER_ID]:
		_expect(is_zero_approx(float(CitizenNeedsManager.last_needs_results[person_id].satisfaction_delta)),
			"The daily ledger reports no Satisfaction delta for %s." % person_id)
	_expect(str(full.trend) == "up" and str(two.trend) == "down"
		and str(one.trend) == "stable" and str(empty.trend) == "down"
		and str(legacy.trend) == "down",
		"The daily summary exposes direction toward the condition target.")
	_expect(CitizenNeedsManager.last_food_fulfilled_count == 3
		and CitizenNeedsManager.last_food_unfulfilled_count == 2
		and CitizenNeedsManager.last_clothing_fulfilled_count == 1
		and CitizenNeedsManager.last_clothing_unfulfilled_count == 4
		and CitizenNeedsManager.last_shelter_capacity_fulfilled_count == 2
		and CitizenNeedsManager.last_shelter_capacity_unfulfilled_count == 2,
		"Need allocation counters cover actual resident and worker outcomes without counting linked workers twice.")
	_expect(int(provider.call("get_food_supply_points")) == 0
		and int(provider.call("get_clothing_item_count")) == 0
		and CityStockManager.shelter_capacity == 2,
		"Food and garments are consumed from CityToolStorage, while shelter capacity remains a reserve.")
	_expect(WorkerDatabase.get_worker_data(TWO_NEEDS_ID).get_resolved_satisfaction() == two.satisfaction
		and CitizenNeedsManager.last_needs_results.has(TWO_NEEDS_ID)
		and not CitizenNeedsManager.last_needs_results.has("duplicate:" + TWO_NEEDS_ID),
		"A linked WorkerData reads the resident's actual satisfaction and has only one daily result.")

	var stock_after_first: Dictionary = provider.get("items").duplicate(true)
	var satisfaction_after_first: Array[float] = _current_satisfactions()
	var results_after_first: Dictionary = CitizenNeedsManager.last_needs_results.duplicate(true)
	CitizenNeedsManager.process_daily_needs()
	CitizenNeedsManager.process_daily_food_needs()
	CitizenNeedsManager.process_daily_clothing_needs()
	_expect(provider.get("items") == stock_after_first
		and _current_satisfactions() == satisfaction_after_first
		and CitizenNeedsManager.last_needs_results == results_after_first
		and needs_changed_count[0] == 1,
		"Repeated same-day food, clothing, full-settlement, and reentrant calls do not consume or apply twice.")


func _test_stock_preview_after_settlement() -> void:
	var empty_before: Dictionary = CitizenNeedsManager.get_person_needs_summary(EMPTY_ID)
	provider.set("items", {READY_BREAD: 2, SIMPLE_CLOTHES: 1})
	CityStockManager.shelter_capacity = 5
	var empty_after: Dictionary = CitizenNeedsManager.get_person_needs_summary(EMPTY_ID)
	_expect(int(empty_after.food_stock) == 2 and int(empty_after.clothing_stock) == 1
		and int(empty_after.shelter_capacity) == 5,
		"The summary refreshes current food, clothing, and shelter reserves after settlement.")
	_expect(bool(empty_after.evaluated) and not bool(empty_after.food) and not bool(empty_after.clothing)
		and not bool(empty_after.shelter) and is_equal_approx(float(empty_after.condition_target), 0.0)
		and is_equal_approx(float(empty_after.satisfaction), float(empty_before.satisfaction)),
		"Adding stock after settlement does not retroactively fulfill needs or change Satisfaction/target.")


func _test_raid_refreshes_actual_satisfaction() -> void:
	var before: Dictionary = CitizenNeedsManager.get_person_needs_summary(FULL_ID)
	var raid_config: Resource = RAID_CONFIG_SCRIPT.new()
	raid_config.set("wall_max_hp", 1)
	raid_config.set("wall_defend", 0)
	raid_config.set("instant_build_enabled", true)
	raid_config.set("satisfaction_penalty", 0.05)
	raid_config.set("max_fleeing_residents", 0)
	var raid_state: Node = RAID_STATE_SCRIPT.new()
	raid_state.set("config", raid_config)
	add_child(raid_state)
	var built: bool = bool(raid_state.call("build_wall"))
	var started: bool = bool(raid_state.call("start_debug_raid", true))
	raid_state.set_process(false)
	raid_state.call("advance_attack", 5.0)
	var raid_result: Dictionary = raid_state.call("get_last_report")
	var after: Dictionary = CitizenNeedsManager.get_person_needs_summary(FULL_ID)
	raid_state.free()
	_expect(built and started and str(raid_result.get("outcome", "")) == "breached"
		and int(raid_result.get("residents_affected", -1)) == 4
		and raid_result.get("citizens_fled", []).is_empty(),
		"A real deterministic breach applies the population effect to residents while excluding the legacy worker.")
	_expect(is_equal_approx(float(before.satisfaction), 0.05)
		and is_equal_approx(float(after.satisfaction), 0.01)
		and is_equal_approx(float(after.condition_target), 0.99)
		and bool(after.food) and bool(after.clothing) and bool(after.shelter)
		and str(after.trend) == "up",
		"Reading the summary after a raid exposes changed actual Satisfaction with the settled needs target intact.")


func _test_empty_day_then_condition_recovery() -> void:
	provider.set("items", {})
	provider.set("food_portions", {})
	CityStockManager.shelter_capacity = 0
	var before: Dictionary = CitizenNeedsManager.get_person_needs_summary(FULL_ID)
	_expect(bool(before.evaluated) and bool(before.food) and bool(before.clothing) and bool(before.shelter)
		and int(before.food_stock) == 0 and int(before.clothing_stock) == 0
		and int(before.shelter_capacity) == 0,
		"A stock preview changes immediately while current allocations remain covered until their actual expiry.")
	_expect(TimeComponentManager.advance_minutes(MINUTES_PER_DAY),
		"The existing allocations are integrated through an actual 24-hour clock advance.")
	fixture_day = TimeComponentManager.current_day
	_expect(CitizenNeedsManager.last_processed_day == fixture_day,
		"The midnight signal performs the next daily service settlement once.")
	var after: Dictionary = CitizenNeedsManager.get_person_needs_summary(FULL_ID)
	var empty_after: Dictionary = CitizenNeedsManager.get_person_needs_summary(EMPTY_ID)
	var two_after: Dictionary = CitizenNeedsManager.get_person_needs_summary(TWO_NEEDS_ID)
	var one_after: Dictionary = CitizenNeedsManager.get_person_needs_summary(ONE_NEED_ID)
	_expect(not bool(after.food) and bool(after.clothing) and not bool(after.shelter)
		and is_equal_approx(float(after.condition_target), 0.33)
		and is_equal_approx(float(after.satisfaction), 0.06),
		"Food and shelter shortages lower the target while the previous day's clothing allocation remains valid.")
	_expect(not bool(empty_after.food) and not bool(empty_after.clothing) and not bool(empty_after.shelter)
		and is_equal_approx(float(empty_after.condition_target), 0.0)
		and is_equal_approx(float(empty_after.satisfaction), 0.20),
		"An unmet resident declines gradually over the actual day without leaving before reaching zero (satisfaction=%.9f)." % float(empty_after.satisfaction))
	_expect(is_equal_approx(float(two_after.satisfaction), 0.89)
		and is_equal_approx(float(one_after.satisfaction), 0.33),
		"The elapsed day follows prior service targets before reallocation (two=%.9f, one=%.9f)." % [float(two_after.satisfaction), float(one_after.satisfaction)])

	var recovery_ids: Array[String] = [FULL_ID, TWO_NEEDS_ID, ONE_NEED_ID, EMPTY_ID, LEGACY_WORKER_ID]
	for recovery_day: int in range(1, 22):
		fixture_day += 1
		TimeComponentManager.current_day = fixture_day
		CitizenNeedsManager.last_processed_day = fixture_day - 1
		provider.set("items", {READY_BREAD: 5, SIMPLE_CLOTHES: 5})
		provider.set("food_portions", {})
		CityStockManager.shelter_capacity = 5
		var previous: Dictionary = {}
		var previous_targets: Dictionary = {}
		var integration_minutes: Dictionary = {}
		var now: int = fixture_day * MINUTES_PER_DAY
		for person_id: String in recovery_ids:
			var person_summary: Dictionary = CitizenNeedsManager.get_person_needs_summary(person_id)
			previous[person_id] = float(person_summary.satisfaction)
			var cursor: int = int(CitizenNeedsManager.satisfaction_last_minute.get(person_id, now))
			previous_targets[person_id] = _target_during_interval(person_id, cursor)
			integration_minutes[person_id] = maxi(0, now - cursor)
		CitizenNeedsManager.process_daily_needs()
		for person_id: String in recovery_ids:
			var summary: Dictionary = CitizenNeedsManager.get_person_needs_summary(person_id)
			var movement: float = DAILY_STEP * float(integration_minutes[person_id]) / float(MINUTES_PER_DAY)
			var expected: float = clampf(move_toward(float(previous[person_id]), float(previous_targets[person_id]), movement), 0.0, 1.0)
			_expect(bool(summary.food) and bool(summary.clothing) and bool(summary.shelter)
				and is_equal_approx(float(summary.condition_target), 0.99)
				and is_equal_approx(float(summary.satisfaction), expected)
				and float(summary.satisfaction) <= 1.0,
				"Recovery day %d records full actual service while settling %s toward the prior interval target." % [recovery_day, person_id])
	_expect(is_equal_approx(CitizenNeedsManager.satisfaction_condition_value(false, false, false), 0.0)
		and is_equal_approx(CitizenNeedsManager.satisfaction_condition_value(true, false, false), 0.33)
		and is_equal_approx(CitizenNeedsManager.satisfaction_condition_value(true, true, false), 0.66)
		and is_equal_approx(CitizenNeedsManager.satisfaction_condition_value(true, true, true), 0.99),
		"The four fulfillment counts map exactly to 0, 33, 66, and 99 percent targets.")
	var recovered: Dictionary = CitizenNeedsManager.get_person_needs_summary(FULL_ID)
	_expect(is_equal_approx(float(recovered.satisfaction), 0.99)
		and str(recovered.trend) == "stable",
		"Repeated fully fulfilled days reach the 99% ceiling without overshoot and then stabilize.")


func _target_during_interval(person_id: String, absolute_minute: int) -> float:
	var citizen: CitizenData = CitizenManager.get_citizen(person_id)
	var person: Variant = citizen if citizen != null and citizen.population_status == CitizenData.PopulationStatus.RESIDENT else WorkerDatabase.get_worker_data(person_id)
	if person == null:
		return 0.0
	var food: bool = bool(CitizenNeedsManager.call("_food_covered_at", person_id, absolute_minute))
	var day: int = floori(float(absolute_minute) / float(MINUTES_PER_DAY))
	var allocation: Dictionary = CitizenNeedsManager.call("_get_valid_clothing_allocation", person_id, day)
	var clothing: bool = not allocation.is_empty()
	return CitizenNeedsManager.satisfaction_condition_value(food, clothing, bool(person.shelter_fulfilled))


func _test_all_condition_targets_and_step_boundaries() -> void:
	var positions: Array[String] = ["below", "equal", "above"]
	var case_count: int = 0
	var interval_start: int = fixture_day * MINUTES_PER_DAY
	var interval_end: int = interval_start + 360
	var movement: float = DAILY_STEP * 360.0 / float(MINUTES_PER_DAY)
	for mask: int in range(8):
		var food: bool = (mask & 1) != 0
		var clothing: bool = (mask & 2) != 0
		var shelter: bool = (mask & 4) != 0
		var target: float = CitizenNeedsManager.satisfaction_condition_value(food, clothing, shelter)
		for position: String in positions:
			var satisfaction_before: float = target
			match position:
				"below":
					satisfaction_before = target - 0.02
				"above":
					satisfaction_before = target + 0.02

			# The valid range has no value below a zero target or above a .99
			# target. Those two synthetic edge inputs exercise the clamping guard.
			var test_id: String = "satisfaction_matrix_%d_%s" % [mask, position]
			var person: CitizenData = _make_resident(test_id, satisfaction_before)
			person.food_fulfilled = food
			person.clothing_fulfilled = clothing
			person.shelter_fulfilled = shelter
			if food:
				CitizenNeedsManager.food_coverage_until[test_id] = interval_end
			if clothing:
				CitizenNeedsManager.clothing_allocations[test_id] = {
					"item_id": SIMPLE_CLOTHES,
					"issued_day": fixture_day,
					"expires_day": fixture_day + 1
				}

			# Integrate six elapsed hours under the actual per-person entitlements,
			# then verify the daily recorder only publishes the resulting ledger.
			var integrated: float = float(CitizenNeedsManager.call(
				"_integrate_satisfaction", person, test_id, satisfaction_before, interval_start, interval_end))
			var expected_satisfaction: float = clampf(
				move_toward(satisfaction_before, target, movement), 0.0, 1.0)
			person.satisfaction = integrated
			CitizenNeedsManager.call("_apply_daily_effect_and_record", person, test_id, fixture_day)
			var result: Dictionary = CitizenNeedsManager.last_needs_results[test_id]
			var fulfilled_count: int = int(food) + int(clothing) + int(shelter)
			var expected_trend: String = "up" if integrated < target - 0.000000001 else ("down" if integrated > target + 0.000000001 else "stable")

			_expect(bool(result.evaluated)
				and bool(result.food) == food and bool(result.clothing) == clothing
				and bool(result.shelter) == shelter,
				"Target mask %d (%s) records the exact actual Food/Clothing/Shelter outcomes." % [mask, position])
			_expect(is_equal_approx(target, float(fulfilled_count) * 0.33)
				and is_equal_approx(CitizenNeedsManager.satisfaction_condition_value(
					bool(result.food), bool(result.clothing), bool(result.shelter)), target),
				"Target mask %d (%s) maps its three actual outcomes to the expected 0/33/66/99 target." % [mask, position])
			_expect(is_equal_approx(integrated, expected_satisfaction)
				and is_equal_approx(float(result.satisfaction), integrated)
				and is_zero_approx(float(result.satisfaction_delta))
				and float(result.satisfaction) >= 0.0 and float(result.satisfaction) <= 1.0,
				"Target mask %d (%s) integrates six hours at the elapsed-time rate; daily recording adds no jump." % [mask, position])
			_expect(CitizenNeedsManager.call("_satisfaction_trend", integrated, target) == expected_trend,
				"Target mask %d (%s) keeps the correct live trend after integration." % [mask, position])
			case_count += 1
			CitizenNeedsManager.last_needs_results.erase(test_id)
			CitizenNeedsManager.clothing_allocations.erase(test_id)
			CitizenNeedsManager.food_coverage_until.erase(test_id)
	_expect(case_count == 24,
		"The directed target matrix covers all eight actual-service combinations at below, equal, and above positions.")


func _current_satisfactions() -> Array[float]:
	var values: Array[float] = []
	for person_id: String in [FULL_ID, TWO_NEEDS_ID, ONE_NEED_ID, EMPTY_ID, LEGACY_WORKER_ID]:
		var summary: Dictionary = CitizenNeedsManager.get_person_needs_summary(person_id)
		values.append(float(summary.satisfaction))
	return values


func _test_exact_zero_departure() -> void:
	var departed: Array[int] = [0]
	var on_left := func(citizen: CitizenData) -> void:
		if citizen.citizen_id == ZERO_DEPARTURE_ID:
			departed[0] += 1
	CitizenManager.citizen_left.connect(on_left)
	provider.set("items", {})
	provider.set("food_portions", {})
	CityStockManager.shelter_capacity = 0
	var zero_candidate: CitizenData = _make_resident(ZERO_DEPARTURE_ID, 0.00001)
	CitizenManager.add_citizen(zero_candidate)
	var now: int = (TimeComponentManager.current_day * MINUTES_PER_DAY
		+ TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute)
	CitizenNeedsManager.satisfaction_last_minute[ZERO_DEPARTURE_ID] = now
	CitizenNeedsManager.food_coverage_until.erase(ZERO_DEPARTURE_ID)
	_expect(zero_candidate.population_status == CitizenData.PopulationStatus.RESIDENT
		and zero_candidate.satisfaction > 0.0,
		"A small positive starting value remains resident before elapsed time reaches zero.")
	_expect(TimeComponentManager.advance_minutes(1), "One game minute advances the near-zero resident.")
	_expect(is_zero_approx(zero_candidate.satisfaction)
		and zero_candidate.population_status == CitizenData.PopulationStatus.LEFT_CITY
		and departed[0] == 1,
		"An unserved resident leaves exactly when actual Satisfaction reaches zero.")
	_expect(not CitizenNeedsManager.satisfaction_last_minute.has(ZERO_DEPARTURE_ID)
		and not CitizenNeedsManager.food_coverage_until.has(ZERO_DEPARTURE_ID)
		and not CitizenNeedsManager.clothing_allocations.has(ZERO_DEPARTURE_ID),
		"Departure removes the person's satisfaction, food, and clothing tracking entries.")
	TimeComponentManager.advance_minutes(1)
	CitizenNeedsManager.process_daily_needs()
	_expect(departed[0] == 1,
		"Further clock and daily calls do not emit a duplicate departure.")
	CitizenManager.citizen_left.disconnect(on_left)


func _restore_global_state() -> void:
	CitizenManager.citizens_by_id.clear()
	for citizen_id: Variant in original_citizens:
		CitizenManager.citizens_by_id[citizen_id] = original_citizens[citizen_id]
	WorkerDatabase.workers_by_id.clear()
	for worker_id: Variant in original_workers:
		WorkerDatabase.workers_by_id[worker_id] = original_workers[worker_id]
	WorkerDatabase.dismissed_workers.clear()
	for worker_id: Variant in original_dismissed_workers:
		WorkerDatabase.dismissed_workers[worker_id] = original_dismissed_workers[worker_id]

	TimeComponentManager.current_day = int(original_clock.day)
	TimeComponentManager.current_hour = int(original_clock.hour)
	TimeComponentManager.current_minute = int(original_clock.minute)
	TimeComponentManager._timer = float(original_clock.timer)
	TimeComponentManager.set_process(bool(original_clock.processing))
	TimeComponentManager.is_paused = bool(original_clock.paused)
	get_tree().paused = bool(original_clock.tree_paused)
	CityStockManager.shelter_capacity = int(original_city_stock.shelter_capacity)
	for property_name: String in original_needs_state:
		var value: Variant = original_needs_state[property_name]
		if value is Dictionary or value is Array:
			value = value.duplicate(true)
		CitizenNeedsManager.set(property_name, value)

	if created_provider:
		if is_instance_valid(provider):
			provider.free()
	elif is_instance_valid(provider):
		for property_name: String in ["items", "food_portions"]:
			if original_provider_state.has(property_name):
				provider.set(property_name, original_provider_state[property_name].duplicate(true))
	if is_instance_valid(city_progress_state):
		for property_name: String in original_city_progress_state:
			var value: Variant = original_city_progress_state[property_name]
			if value is Dictionary or value is Array:
				value = value.duplicate(true)
			city_progress_state.set(property_name, value)
