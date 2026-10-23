extends Node

## Controlled output fixture; this is not a normal player journey or balance claim.
## It loads the actual content scene, pays each fixture Laborer through WorkerDatabase,
## disables commute and player needs to isolate authored worksite capacity, and records
## the observed daily stats and site-stock deltas. Authored rates, natural stock bounds, and caps are untouched;
## each independent day case restores the authored 72-unit opening stock.

const CONTENT_SCENE: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const RESULTS_DIR: String = "user://contract_output_sample"
const RESULTS_PATH: String = RESULTS_DIR + "/results.json"
const CONTRACT_DAYS: int = 3
const LABORER_PACKAGE_PRICE: int = 1
const SAMPLE_CASES: Array[Dictionary] = [
	{"label": "07:00", "minute_of_day": 7 * 60},
	{"label": "08:01", "minute_of_day": 8 * 60 + 1},
	{"label": "14:00", "minute_of_day": 14 * 60},
	{"label": "15:00", "minute_of_day": 15 * 60},
]
const SITE_IDS: Array[StringName] = [&"ClaySiteA", &"WoodSite", &"ReedSite", &"StrawSite", &"WaterSite"]
const EXPECTED_CASE_COUNT: int = 20
const FIXTURE_BASE_DAY: int = 120

var failures: int = 0
var completed_case_count: int = 0
var results: Array[Dictionary] = []
var content: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	get_tree().paused = false
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	_set_clock(FIXTURE_BASE_DAY, 6, 50)

	content = CONTENT_SCENE.instantiate()
	get_tree().root.add_child(content)
	await get_tree().process_frame
	await get_tree().process_frame

	var runtime: Node = content.get_node_or_null("YSortWorld/WorkerRuntime")
	var player: Player = content.get_node_or_null("YSortWorld/Player") as Player
	_check(runtime != null and player != null, "The actual content scene exposes its WorkerRuntime and Player.")
	if runtime == null or player == null:
		_finish()
		return
	_check(runtime.sites.size() == SITE_IDS.size(), "The actual main map exposes all five authored resource sites.")
	# These are fixture-only isolation controls. No gathering rate, stock, or worksite cap is edited.
	runtime.enable_worker_commute = false
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true

	for site_id: StringName in SITE_IDS:
		_check(runtime.sites.has(site_id), "Actual main-map site exists: " + str(site_id))
		if runtime.sites.has(site_id):
			var session: RefCounted = runtime.sites[site_id]
			var resolved_stock_min: int = int(session.daily_stock_min) if session.daily_stock_min >= 0 else int(runtime.daily.stock_min)
			var resolved_stock_max: int = int(session.daily_stock_max) if session.daily_stock_max >= 0 else int(runtime.daily.stock_max)
			_check(session.stock == 72 and resolved_stock_min == 72 and resolved_stock_max == 72,
				"Authored daily stock is exactly 72 for " + str(site_id))
			_check(float(session.minutes_per_unit) > 0.0, "Authored minutes-per-unit is positive for " + str(site_id))

	var case_index: int = 0
	for site_id: StringName in SITE_IDS:
		if not runtime.sites.has(site_id):
			case_index += SAMPLE_CASES.size()
			continue
		for sample_case: Dictionary in SAMPLE_CASES:
			_run_case(runtime, site_id, sample_case, case_index)
			case_index += 1

	_check(completed_case_count == EXPECTED_CASE_COUNT,
		"Sentinel requires all %d site/time cases to complete; completed %d." % [EXPECTED_CASE_COUNT, completed_case_count])
	_check(results.size() == EXPECTED_CASE_COUNT,
		"Results file must contain all %d site/time cases; found %d." % [EXPECTED_CASE_COUNT, results.size()])
	_finish()


func _run_case(runtime: Node, site_id: StringName, sample_case: Dictionary, case_index: int) -> void:
	var failures_before: int = failures
	var label: String = str(sample_case.label)
	var requested_minute: int = int(sample_case.minute_of_day)
	var case_day: int = FIXTURE_BASE_DAY + case_index + 1
	var preassignment_minute: int = requested_minute - 10
	var preassignment_global: int = case_day * 1440 + preassignment_minute
	_set_clock_from_global_minute(preassignment_global)

	var schedule = runtime.daily
	schedule.last_tick = preassignment_global
	schedule.ledger_day = case_day
	schedule.last_stock_day = case_day
	schedule.minutes_by_worker.clear()
	var session: RefCounted = runtime.sites[site_id]
	# Restore only the authored 72-unit daily stock between independent day cases.
	session.stock = 72
	var stock_before_assignment: int = session.stock
	TimeComponentManager.advance_minutes(10)
	_check(_now() == case_day * 1440 + requested_minute, "%s reaches its exact requested assignment time." % label)
	_check(session.stock == stock_before_assignment,
		"No unassigned output is harvested during the ten-minute preassignment window at %s on %s." % [label, site_id])
	_check(not schedule.jobs.has(site_id), "No worker job exists before assignment at %s on %s." % [label, site_id])

	var worker_id: String = "contract_output_sample_%02d_%s" % [case_index, str(site_id)]
	_check(not WorkerDatabase.has_worker_data(worker_id), "Fixture worker ID is unique: " + worker_id)
	var worker := WorkerData.new()
	worker.worker_id = worker_id
	worker.display_name = "Paid output fixture"
	worker.profession = WorkerData.Profession.LABORER
	worker.efficiency = 1.0
	worker.reliability = 1.0
	worker.food_fulfilled = true
	worker.clothing_fulfilled = true
	worker.shelter_fulfilled = true
	worker.satisfaction = 0.5
	WorkerDatabase.workers_by_id[worker_id] = worker

	var wallet_before: int = int(Inventory.items.get("shekel", 0))
	Inventory.add_item("shekel", LABORER_PACKAGE_PRICE)
	var wallet_with_fixture_payment: int = int(Inventory.items.get("shekel", 0))
	var paid: bool = WorkerDatabase.renew_contract(worker_id, CONTRACT_DAYS)
	var wallet_after: int = int(Inventory.items.get("shekel", 0))
	var paid_contract_valid: bool = (
		paid
		and wallet_with_fixture_payment - wallet_after == LABORER_PACKAGE_PRICE
		and worker.payroll_paid_start_minute == _now()
		and worker.payroll_paid_from_day == case_day
		and worker.payroll_paid_until_day == case_day + CONTRACT_DAYS
		and worker.payroll_contract_days == CONTRACT_DAYS
		and worker.payroll_period_rate == LABORER_PACKAGE_PRICE
		and not worker.is_payroll_blocked()
	)
	_check(paid_contract_valid,
		"Each explicit Laborer receives a paid three-day wallet contract costing one Shekel.")
	if not paid_contract_valid:
		results.append({"case": case_index, "site": str(site_id), "assignment_time": label,
			"worker_id": worker_id, "wallet_before_fixture_grant": wallet_before,
			"wallet_after_payment": wallet_after, "complete": false, "failure_count_at_case_end": failures})
		WorkerDatabase.workers_by_id.erase(worker_id)
		return
	var selected: bool = schedule.toggle(site_id, worker_id)
	_check(selected, "Paid fixture Laborer can be assigned to " + str(site_id))
	var started: bool = selected and schedule.start(site_id, runtime._drop_daily_output.bind(runtime.get_node("WorksiteMarkers/" + str(site_id))))
	_check(started,
		"Daily worksite assignment starts for " + str(site_id) + " at " + label)
	if not started or not schedule.jobs.has(site_id) or not schedule.jobs[site_id].stats.has(worker_id):
		_check(false, "A complete daily job record exists for " + worker_id)
		results.append({"case": case_index, "site": str(site_id), "assignment_time": label,
			"worker_id": worker_id, "complete": false, "failure_count_at_case_end": failures})
		WorkerDatabase.workers_by_id.erase(worker_id)
		return

	var assigned_global: int = case_day * 1440 + requested_minute
	var expected_start: int = assigned_global if requested_minute < 15 * 60 else (case_day + 1) * 1440 + 7 * 60
	var job: Dictionary = schedule.jobs.get(site_id, {})
	var actual_start: int = int(job.get("starts", {}).get(worker_id, -1))
	_check(actual_start == expected_start,
		"Assignment at %s starts on the expected workday for %s (expected %d, got %d)." % [label, site_id, expected_start, actual_start])

	var minutes_per_unit: float = float(session.minutes_per_unit)
	var available_same_day: int = maxi(0, 15 * 60 - requested_minute) if requested_minute < 15 * 60 else 0
	var expected_same_day_output: int = mini(72, floori(float(available_same_day) / minutes_per_unit))
	var followup_next_day_minutes: int = 0
	var output_at_case_end: int = 0
	var output_after_nextday_start: int = 0
	if requested_minute < 15 * 60:
		TimeComponentManager.advance_minutes(available_same_day)
		output_at_case_end = int(schedule.jobs[site_id].stats[worker_id].output)
		_check(_now() == case_day * 1440 + 15 * 60, "Shift measurement ends at 15:00 for " + str(site_id))
		_check(int(schedule.minutes_by_worker.get(worker_id, 0)) <= available_same_day,
			"Recorded worker minutes do not exceed the shift for " + str(site_id))
		_check(output_at_case_end == expected_same_day_output,
			"Observed output matches authored rate and 72-unit stock cap for %s at %s (expected %d, got %d)." % [site_id, label, expected_same_day_output, output_at_case_end])
	else:
		output_at_case_end = int(schedule.jobs[site_id].stats[worker_id].output)
		_check(output_at_case_end == 0 and session.stock == 72,
			"15:00 assignment produces nothing on its assignment day for " + str(site_id))
		_set_clock(case_day + 1, 7, 0)
		schedule.last_tick = _now()
		_check(int(schedule.jobs[site_id].starts[worker_id]) == (case_day + 1) * 1440 + 7 * 60,
			"15:00 assignment remains scheduled for next-day 07:00 for " + str(site_id))
		_check(int(schedule.jobs[site_id].stats[worker_id].output) == 0 and session.stock == 72,
			"No output appears merely from placing the fixture clock at next-day 07:00 for " + str(site_id))
		followup_next_day_minutes = ceili(minutes_per_unit)
		TimeComponentManager.advance_minutes(followup_next_day_minutes)
		output_after_nextday_start = int(schedule.jobs[site_id].stats[worker_id].output)
		_check(output_after_nextday_start == 1,
			"Next-day 07:00 assignment produces its first full unit after %d work minutes for %s." % [followup_next_day_minutes, str(site_id)])

	var stock_after: int = session.stock
	var observed_output: int = int(schedule.jobs[site_id].stats[worker_id].output)
	var worker_minutes: int = int(schedule.minutes_by_worker.get(worker_id, 0))
	var stock_delta: int = 72 - stock_after
	_check(stock_after >= 0 and stock_after <= 72,
		"Site stock remains within the nonnegative 72-unit daily cap for " + str(site_id))
	_check(stock_delta == observed_output,
		"Daily stats output equals the actual site-stock delta for " + str(site_id))
	_check(worker_minutes <= 480, "Per-worker ledger stays within the 480-minute daily limit for " + str(site_id))

	var sample: Dictionary = {
		"case": case_index,
		"site": str(site_id),
		"assignment_time": label,
		"clock_day": case_day,
		"worker_id": worker_id,
		"worker_profession": "Laborer",
		"resource_item_id": str(session.item_id),
		"contract_days": CONTRACT_DAYS,
		"contract_price_shekel": LABORER_PACKAGE_PRICE,
		"wallet_before_fixture_grant": wallet_before,
		"wallet_after_payment": wallet_after,
		"contract_paid_start_minute": worker.payroll_paid_start_minute,
		"scheduled_start_global_minute": actual_start,
		"minutes_per_unit": minutes_per_unit,
		"authored_daily_stock_cap": 72,
		"initial_stock": 72,
		"available_same_day_shift_minutes": available_same_day,
		"expected_same_day_output_units": expected_same_day_output,
		"observed_same_day_output_units": output_at_case_end,
		"observed_output_at_case_end_units": observed_output,
		"followup_nextday_work_minutes": followup_next_day_minutes,
		"output_after_nextday_start_units": output_after_nextday_start,
		"actual_worker_minutes_recorded": worker_minutes,
		"stock_after_case": stock_after,
		"stock_delta_units": stock_delta,
		"commute_disabled_for_isolation": true,
		"player_needs_and_fatigue_disabled_for_isolation": true,
		"complete": failures == failures_before,
	}
	results.append(sample)
	if failures == failures_before:
		completed_case_count += 1

	# Capture first, then release the isolated worker and its standing assignment.
	schedule.withdraw(site_id, worker_id)
	WorkerDatabase.workers_by_id.erase(worker_id)


func _set_clock(day: int, hour: int, minute: int) -> void:
	TimeComponentManager.current_day = day
	TimeComponentManager.current_hour = hour
	TimeComponentManager.current_minute = minute
	TimeComponentManager.current_weather = "clear"
	TimeComponentManager._timer = 0.0
	TimeComponentManager.emit_time_signal()


func _set_clock_from_global_minute(global_minute: int) -> void:
	var day: int = floori(float(global_minute) / 1440.0)
	var minute_of_day: int = global_minute % 1440
	_set_clock(day, minute_of_day / 60, minute_of_day % 60)


func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute


func _finish() -> void:
	if is_instance_valid(content):
		content.queue_free()
	var status: String = "PASS" if failures == 0 and completed_case_count == EXPECTED_CASE_COUNT and results.size() == EXPECTED_CASE_COUNT else "FAIL"
	var document: Dictionary = {
		"status": status,
		"scope": "Controlled actual-content-site fixture; not a normal player journey or an economy-balance claim.",
		"scene": "res://scenes/content_scene/content_scene.tscn",
		"laborer_contract_days": CONTRACT_DAYS,
		"laborer_wallet_price_shekel": LABORER_PACKAGE_PRICE,
		"commute_disabled_for_isolation": true,
		"player_needs_and_fatigue_disabled_for_isolation": true,
		"authored_stock_cap": 72,
		"expected_case_count": EXPECTED_CASE_COUNT,
		"completed_case_count": completed_case_count,
		"record_count": results.size(),
		"failure_count": failures,
		"cases": results,
	}
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RESULTS_DIR))
	_check(directory_error == OK or directory_error == ERR_ALREADY_EXISTS, "Create isolated result directory: " + RESULTS_DIR)
	var file: FileAccess = FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	_check(file != null, "Write results JSON to " + RESULTS_PATH)
	if file != null:
		# Rebuild the envelope after the directory/file checks so the persisted sentinel is authoritative.
		document.status = "PASS" if failures == 0 and completed_case_count == EXPECTED_CASE_COUNT and results.size() == EXPECTED_CASE_COUNT else "FAIL"
		document.completed_case_count = completed_case_count
		document.record_count = results.size()
		document.failure_count = failures
		file.store_string(JSON.stringify(document, "\t", true, true))
		file.close()
	print("ContractOutputSample: ", document.status, " cases=", completed_case_count, "/", EXPECTED_CASE_COUNT, " results=", RESULTS_PATH)
	get_tree().quit(0 if document.status == "PASS" else 1)
