extends Node

const CITY_PROGRESS_SCRIPT: Script = preload("res://scenes/city_progression/city_progression_state.gd")
const TEST_PERSON_ID: String = "daily_retry_bulk_resident"
const START_DAY: int = 40
const SKIP_MINUTES: int = 4320

class TestRaid extends Node:
	signal wall_breached(raid_id: int)
	var wall_hp: int = 50

	func get_last_report() -> Dictionary:
		return {"id": 0}

	func set_city_threat_stage(_stage: StringName) -> void:
		pass

var failures: int = 0
var progression: Node
var raid: Node
var injection_armed: bool = false
var injected: bool = false
var lock_released: bool = false
var observations: Array[Dictionary] = []
var minute_observations: Array[Dictionary] = []
var bonus_awards: int = 0
var run_storage: Node

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _near(actual: float, expected: float, label: String) -> void:
	_expect(absf(actual - expected) <= 0.000002, "%s: expected %.9f, got %.9f" % [label, expected, actual])

func _ensure_storage() -> void:
	run_storage = WorkStateRuntime.get_node_or_null("CityToolStorage")
	if run_storage == null:
		var storage_script: Script = load("res://scenes/storage_destination/city_tool_storage.gd")
		run_storage = storage_script.new()
		run_storage.name = "CityToolStorage"
		WorkStateRuntime.add_child(run_storage)

func _setup_progression_probe() -> void:
	progression = CITY_PROGRESS_SCRIPT.new()
	progression.name = "DailyRetryTestProgression"
	add_child(progression)
	raid = TestRaid.new()
	raid.name = "DailyRetryTestRaid"
	add_child(raid)
	progression.call("bind_raid", raid)
	progression.connect("changed", _on_progression_changed)

func _on_progression_changed() -> void:
	bonus_awards += 1

func _reset_case() -> CitizenData:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	TimeComponentManager.current_day = START_DAY
	TimeComponentManager.current_hour = 10
	TimeComponentManager.current_minute = 0
	TimeComponentManager._timer = 0.0
	CitizenManager.citizens_by_id.clear()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	WorkerDatabase._payroll_settling = false
	WorkerDatabase._idle_resignation_sweep_active = false
	CitizenNeedsManager.clothing_allocations.clear()
	CitizenNeedsManager.last_needs_results.clear()
	CitizenNeedsManager.food_coverage_until.clear()
	CitizenNeedsManager.satisfaction_last_minute.clear()
	CitizenNeedsManager.last_processed_day = START_DAY
	CitizenNeedsManager.last_food_processed_day = START_DAY
	CitizenNeedsManager.last_clothing_processed_day = START_DAY
	CitizenNeedsManager._processing_daily_needs = false
	CitizenNeedsManager._processing_food = false
	CitizenNeedsManager._processing_clothing = false
	CitizenNeedsManager._daily_needs_retry_pending = false
	CitizenNeedsManager._daily_needs_retry_after_frame = false
	CitizenNeedsManager._satisfaction_retry_pending = false
	CitizenNeedsManager._food_recheck_pending = false
	run_storage.set("items", {})
	run_storage.set("food_portions", {})
	run_storage.set("units", {})
	CityStockManager.shelter_capacity = 0
	progression.set("progress", 0)
	progression.set("last_awarded_day", START_DAY)
	progression.set("last_daily", {})
	progression.set("last_event", "")
	observations.clear()
	minute_observations.clear()
	bonus_awards = 0
	var person := CitizenData.new()
	person.citizen_id = TEST_PERSON_ID
	person.display_name = TEST_PERSON_ID
	person.population_status = CitizenData.PopulationStatus.RESIDENT
	person.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	person.satisfaction = 0.9
	CitizenManager.add_citizen(person)
	return person

func _inject_payroll_lock_at_midnight(arrival_minute: int) -> void:
	if not injection_armed:
		return
	if arrival_minute == (START_DAY + 1) * 1440:
		injection_armed = false
		injected = true
		# The bulk advance already passed can_advance_time(). This models a
		# synchronous callback raising a real WorkerDatabase transaction guard
		# immediately before the existing new-day flush attempt.
		WorkerDatabase._payroll_settling = true
		_expect(TimeComponentManager._advancing_time and WorkerDatabase.is_world_time_transition_busy(),
			"The simulated payroll lock is raised only after the already-running bulk advance was admitted.")

func _observe_new_day(day: int) -> void:
	var result: Dictionary = CitizenNeedsManager.last_needs_results.get(TEST_PERSON_ID, {})
	observations.append({
		"signal_day": day,
		"settled_day": CitizenNeedsManager.last_processed_day,
		"result_day": int(result.get("day", -1))
	})
	if injected and day == START_DAY + 1 and WorkerDatabase._payroll_settling:
		# This listener was connected after CitizenNeedsManager. Its flush has
		# already failed; clear the simulated transient lock in the same signal loop.
		WorkerDatabase._payroll_settling = false
		lock_released = true

func _observe_midnight_minute(_minute: int) -> void:
	if TimeComponentManager.current_day != START_DAY + 1 or TimeComponentManager.current_hour != 0 or TimeComponentManager.current_minute != 0:
		return
	var result: Dictionary = CitizenNeedsManager.last_needs_results.get(TEST_PERSON_ID, {})
	minute_observations.append({
		"signal_day": TimeComponentManager.current_day,
		"settled_day": CitizenNeedsManager.last_processed_day,
		"result_day": int(result.get("day", -1)),
		"lock_released": not WorkerDatabase._payroll_settling
	})

func _run_case(with_failure: bool) -> Dictionary:
	var person: CitizenData = _reset_case()
	injected = false
	lock_released = false
	injection_armed = with_failure
	if with_failure:
		TimeComponentManager.simulated_minute_started.connect(_inject_payroll_lock_at_midnight)
	TimeComponentManager.new_day_started.connect(_observe_new_day)
	TimeComponentManager.minute_changed.connect(_observe_midnight_minute)
	var accepted: bool = TimeComponentManager.advance_minutes(SKIP_MINUTES)
	_expect(accepted, "The clock accepts the synchronous +3-day advance (failure=%s)." % with_failure)
	var last_daily: Dictionary = progression.get("last_daily")
	var result: Dictionary = {
		"accepted": accepted,
		"satisfaction": person.satisfaction,
		"day": TimeComponentManager.current_day,
		"last_processed_day": CitizenNeedsManager.last_processed_day,
		"last_food_processed_day": CitizenNeedsManager.last_food_processed_day,
		"last_clothing_processed_day": CitizenNeedsManager.last_clothing_processed_day,
		"result_day": int(CitizenNeedsManager.last_needs_results.get(TEST_PERSON_ID, {}).get("day", -1)),
		"progress": int(progression.get("progress")),
		"last_awarded_day": int(progression.get("last_awarded_day")),
		"last_daily": last_daily.duplicate(true),
		"bonus_awards": bonus_awards,
		"observations": observations.duplicate(true),
		"minute_observations": minute_observations.duplicate(true),
		"injected": injected,
		"lock_released": lock_released
	}
	TimeComponentManager.new_day_started.disconnect(_observe_new_day)
	TimeComponentManager.minute_changed.disconnect(_observe_midnight_minute)
	if with_failure:
		TimeComponentManager.simulated_minute_started.disconnect(_inject_payroll_lock_at_midnight)
	return result

func _run() -> void:
	# Let autoloads finish their deferred signal bindings before creating the fixture.
	await get_tree().process_frame
	_ensure_storage()
	_setup_progression_probe()
	var baseline: Dictionary = _run_case(false)
	var interrupted: Dictionary = _run_case(true)
	var final_day: int = START_DAY + 3
	_expect(int(baseline.day) == final_day and int(interrupted.day) == final_day,
		"Both runs end at the same clock day.")
	_near(float(baseline.satisfaction), 0.75, "Uninterrupted Satisfaction after 72 hours")
	_near(float(interrupted.satisfaction), float(baseline.satisfaction), "Injected-failure Satisfaction matches baseline")
	_expect(bool(interrupted.injected) and bool(interrupted.lock_released),
		"The midnight lock was injected after clock entry and released by a same-loop new-day listener.")
	_expect(int(baseline.bonus_awards) == 3 and int(interrupted.bonus_awards) == 3,
		"Each of the three daily bonus ledgers settles once in both runs; baseline=%d interrupted=%d." % [int(baseline.bonus_awards), int(interrupted.bonus_awards)])
	_expect(int(baseline.progress) == 15 and int(interrupted.progress) == 15,
		"All three satisfaction bonuses are counted exactly once in both runs; baseline=%d interrupted=%d." % [int(baseline.progress), int(interrupted.progress)])
	_expect(int(baseline.last_awarded_day) == final_day and int(interrupted.last_awarded_day) == final_day
		and int(baseline.last_daily.get("day", -1)) == final_day and int(interrupted.last_daily.get("day", -1)) == final_day,
		"The exactly-once bonus ledger reaches the final day in both runs.")
	_expect(int(interrupted.last_processed_day) == final_day
		and int(interrupted.last_food_processed_day) == final_day
		and int(interrupted.last_clothing_processed_day) == final_day
		and int(interrupted.result_day) == final_day,
		"All daily service/evaluation cursors reach the final day.")
	var fault_days: Array = interrupted.observations
	_expect(fault_days.size() == 3, "Three new-day boundaries are observed in the injected run.")
	for observation: Dictionary in fault_days:
		if bool(interrupted.injected) and int(observation.signal_day) == START_DAY + 1:
			_expect(int(observation.settled_day) == START_DAY,
				"The intentionally locked new_day_started callback does not settle day %d prematurely." % int(observation.signal_day))
		else:
			_expect(int(observation.settled_day) == int(observation.signal_day)
				and int(observation.result_day) == int(observation.signal_day),
				"Day %d is settled on its new-day boundary (settled=%d, result=%d)." % [int(observation.signal_day), int(observation.settled_day), int(observation.result_day)])
	var midnight_retry: Array = interrupted.minute_observations
	_expect(midnight_retry.size() == 1, "The injected midnight minute_changed boundary is observed once.")
	if not midnight_retry.is_empty():
		var retry_observation: Dictionary = midnight_retry[0]
		_expect(bool(retry_observation.lock_released)
			and int(retry_observation.settled_day) == START_DAY + 1
			and int(retry_observation.result_day) == START_DAY + 1,
			"Day %d settles at minute_changed after the transient lock releases (settled=%d, result=%d)." % [START_DAY + 1, int(retry_observation.settled_day), int(retry_observation.result_day)])
	# Let the deferred retry run and check it neither repairs a missed day late nor
	# awards a duplicate after the synchronous bulk loop has already advanced.
	await get_tree().process_frame
	_expect(CitizenNeedsManager.last_processed_day == final_day and bonus_awards == 3,
		"The deferred retry completes without skipping or duplicating a daily award.")
	print("DailyRetryBulkTest: %s (%d failures) baseline=%s interrupted=%s" % [
		"PASS" if failures == 0 else "FAIL", failures, baseline, interrupted
	])
	get_tree().quit(0 if failures == 0 else 1)
