extends Node

const JOB: JobData = preload("res://resources/job_data/mudbrick_make.tres")
const STORAGE_SCRIPT: Script = preload("res://scripts/autoload/workshop_storage/workshop_storage.gd")
const DAILY: Script = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_daily.gd")
const HAULING: Script = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_hauling.gd")
const SESSION: Script = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_session.gd")
const CITY_TOOLS: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")
const STOCKPILE: PackedScene = preload("res://scenes/content_scene/worksites/worksite_stockpile.tscn")
const WORKSITE_ID: StringName = &"SatisfactionCargoSite"
const HAULER_ID: String = "satisfaction_zero_cargo_hauler"
const PRODUCTION_CASES: Array[Dictionary] = [
	{"name": "just below 40%", "satisfaction": 0.399999, "multiplier": 0.85, "output": 17},
	{"name": "40% boundary", "satisfaction": 0.4, "multiplier": 1.0, "output": 20},
	{"name": "50% reference", "satisfaction": 0.5, "multiplier": 1.0, "output": 20},
	{"name": "just below 75%", "satisfaction": 0.749999, "multiplier": 1.0, "output": 20},
	{"name": "75% boundary", "satisfaction": 0.75, "multiplier": 1.05, "output": 21},
]

var failures: int = 0
var storage: Node
var now_total: int = 100 * 1440 + 8 * 60
var daily
var hauling
var site_session
var city_tools: Node
var endpoint: StorageDestination
var available_output: int = 0
var resignation_ready_ids: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = true
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	CitizenManager.citizens_by_id.clear()
	WorkManager.active_orders.clear()
	WorkManager._last_total_minutes = now_total
	storage = STORAGE_SCRIPT.new()
	storage.max_load = 100000.0
	add_child(storage)

	_test_workshop_production_thresholds()
	_test_zero_satisfaction_blocks_new_work()
	_test_loaded_hauler_resigns_after_receipt()
	_cleanup()

	print("SatisfactionThresholdTransportTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _test_workshop_production_thresholds() -> void:
	_expect(int(JOB.outputs.get("wet_mudbrick", 0)) == 20 and JOB.base_duration_minutes > 0,
		"The real Shape recipe supplies the 20-unit baseline for threshold cases.")
	for case_index: int in range(PRODUCTION_CASES.size()):
		var test_case: Dictionary = PRODUCTION_CASES[case_index]
		var worker_id: String = "satisfaction_threshold_%d" % case_index
		var worker: WorkerData = WorkerData.new()
		worker.worker_id = worker_id
		worker.profession = JOB.requirement_profession
		worker.satisfaction = float(test_case.satisfaction)
		WorkerDatabase.workers_by_id[worker_id] = worker
		_expect(is_equal_approx(worker.get_satisfaction_work_multiplier(), float(test_case.multiplier)),
			"%s uses the configured Satisfaction multiplier." % test_case.name)

		for item_id: String in JOB.inputs:
			storage.add_item(item_id, int(JOB.inputs[item_id]))
		var lots_before: int = storage.output_lots.size()
		var order_id: String = WorkManager.start_job(JOB, WorkOrder.Worker_Type.NPC,
			worker_id, null, storage, storage, JOB.workshop_fee_amount)
		_expect(not order_id.is_empty(), "%s starts the real production order: %s" %
			[test_case.name, WorkManager.get_last_start_job_error()])
		if order_id.is_empty():
			WorkerDatabase.workers_by_id.erase(worker_id)
			continue

		now_total = _after_shift_minutes(now_total, JOB.base_duration_minutes)
		WorkManager.on_time_changed(floori(float(now_total) / 1440.0),
			floori(float(now_total % 1440) / 60.0), now_total % 60)
		_expect(not WorkManager.active_orders.has(order_id) and not worker.is_reserved(),
			"%s completes the production order and releases its worker." % test_case.name)
		_expect(storage.output_lots.size() == lots_before + 1,
			"%s creates exactly one output lot." % test_case.name)
		if storage.output_lots.size() == lots_before + 1:
			var lot: Dictionary = storage.output_lots.back()
			_expect(int(lot.items.get("wet_mudbrick", 0)) == int(test_case.output),
				"%s produces exactly %d mudbricks." % [test_case.name, int(test_case.output)])
		WorkerDatabase.workers_by_id.erase(worker_id)


func _test_zero_satisfaction_blocks_new_work() -> void:
	storage.items.clear()
	var worker := WorkerData.new()
	worker.worker_id = "satisfaction_zero_blocked_worker"
	worker.profession = JOB.requirement_profession
	worker.satisfaction = 0.0
	WorkerDatabase.workers_by_id[worker.worker_id] = worker
	_expect(is_equal_approx(worker.get_satisfaction_work_multiplier(), 0.85),
		"Zero Satisfaction retains the low-tier multiplier as a pure value.")
	for item_id: String in JOB.inputs:
		storage.add_item(item_id, int(JOB.inputs[item_id]))
	var inputs_before: Dictionary = storage.items.duplicate(true)
	var order_id: String = WorkManager.start_job(JOB, WorkOrder.Worker_Type.NPC,
		worker.worker_id, null, storage, storage, JOB.workshop_fee_amount)
	_expect(order_id.is_empty() and not worker.is_reserved() and storage.items == inputs_before,
		"A zero-Satisfaction worker cannot start a new batch or consume its inputs.")
	WorkerDatabase.workers_by_id.erase(worker.worker_id)


func _test_loaded_hauler_resigns_after_receipt() -> void:
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	CitizenManager.citizens_by_id.clear()
	TimeComponentManager.current_day = 0
	TimeComponentManager.current_hour = 7
	TimeComponentManager.current_minute = 0
	available_output = 3
	resignation_ready_ids.clear()

	var citizen: CitizenData = CitizenData.new()
	citizen.citizen_id = HAULER_ID
	citizen.display_name = "Satisfaction cargo hauler"
	citizen.profession = WorkerData.Profession.HAULER
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.HIRED
	citizen.satisfaction = 0.5
	CitizenManager.citizens_by_id[HAULER_ID] = citizen
	var worker: WorkerData = WorkerData.new()
	worker.worker_id = HAULER_ID
	worker.display_name = citizen.display_name
	worker.profession = WorkerData.Profession.HAULER
	worker.satisfaction = 0.5
	WorkerDatabase.workers_by_id[HAULER_ID] = worker

	city_tools = CITY_TOOLS.new()
	add_child(city_tools)
	_expect(city_tools.add_tool_unit("satisfaction_cargo_cart", "cart", "Test Cart")
		and city_tools.allocate("satisfaction_cargo_cart", HAULER_ID),
		"The hauler receives its unique fixture cart.")
	endpoint = STOCKPILE.instantiate()
	endpoint.position = Vector2(30, 0)
	add_child(endpoint)

	site_session = SESSION.new()
	site_session.minutes_per_unit = 10.0
	site_session.stock = 1000
	daily = DAILY.new()
	daily.setup({WORKSITE_ID: site_session})
	daily.equipment_storage = city_tools
	hauling = HAULING.new()
	hauling.speed = 10.0
	hauling.origin_provider = func(_site_id: StringName, _worker_id: String) -> Vector2: return Vector2.ZERO
	hauling.assigned_destination_provider = func(_path: NodePath): return endpoint
	hauling.item_provider = func(_site_id: StringName) -> String: return "clay_lump"
	hauling.output_count = func(_site_id: StringName) -> int: return available_output
	hauling.take_output = _take_output
	hauling.return_output = _return_output
	daily.hauling = hauling
	daily.hauler_ready = func(_site_id: StringName, _count: int) -> String: return ""
	daily.resignation_ready.connect(_on_resignation_ready)

	_expect(daily.select_hauler(WORKSITE_ID, HAULER_ID, NodePath("Destination"), "City Storage", 3)
		and daily.start(WORKSITE_ID, _drop_output),
		"The real worksite scheduler starts the assigned Hauler route.")
	_advance_site(1)
	var route: Dictionary = hauling.routes.get(HAULER_ID, {})
	_expect(int(route.get("cargo", {}).get("quantity", 0)) == 3 and available_output == 0
		and int(endpoint.get_storage().get("quantity")) == 0,
		"Pickup transfers exactly one three-item load into the outbound route.")

	citizen.satisfaction = 0.0
	WorkerDatabase.resign_idle_workers_at_zero()
	route = hauling.routes.get(HAULER_ID, {})
	_expect(worker.resignation_pending and WorkerDatabase.has_worker_data(HAULER_ID)
		and bool(route.get("resigning", false)) and bool(route.get("removing", false))
		and int(route.get("cargo", {}).get("quantity", 0)) == 3,
		"Zero Satisfaction starts resignation but retains the hauler and cargo until receipt.")

	_advance_site(3)
	var destination_stock: int = int(endpoint.get_storage().get("quantity"))
	_expect(destination_stock == 3 and not hauling.routes.has(HAULER_ID)
		and not daily.jobs.has(WORKSITE_ID),
		"The original cargo reaches City Storage before the worksite releases its assignment.")
	_expect(not WorkerDatabase.has_worker_data(HAULER_ID)
		and WorkerDatabase.dismissed_workers.get(HAULER_ID) == worker
		and citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED
		and not city_tools.has_equipped(HAULER_ID, "cart")
		and resignation_ready_ids == [HAULER_ID],
		"The worker resigns once after delivery, retains the same citizen, and releases its cart.")
	_advance_site(6)
	_expect(int(endpoint.get_storage().get("quantity")) == 3
		and resignation_ready_ids == [HAULER_ID],
		"Later worksite ticks cannot redeliver cargo or repeat resignation.")


func _take_output(_site_id: StringName, maximum: int) -> int:
	var taken: int = mini(available_output, maximum)
	available_output -= taken
	return taken


func _return_output(_site_id: StringName, quantity: int) -> bool:
	available_output += quantity
	return true


func _drop_output(_quantity: int) -> bool:
	return true


func _advance_site(minutes: int) -> void:
	for _index: int in range(minutes):
		var total: int = daily.now() + 1
		TimeComponentManager.current_day = total / 1440
		TimeComponentManager.current_hour = (total % 1440) / 60
		TimeComponentManager.current_minute = total % 60
		daily.tick()


func _on_resignation_ready(worker_id: String) -> void:
	_expect(not daily.is_settlement_busy(), "Resignation readiness is emitted after the worksite transaction ends.")
	_expect(not daily.jobs.has(WORKSITE_ID) or not daily.jobs[WORKSITE_ID].ids.has(worker_id),
		"The worker assignment is released before resignation readiness.")
	_expect(not hauling.routes.has(worker_id), "The route is gone before resignation readiness.")
	resignation_ready_ids.append(worker_id)


func _after_shift_minutes(start: int, minutes: int) -> int:
	var cursor: int = start
	var remaining: int = minutes
	while remaining > 0:
		var minute: int = cursor % 1440
		if minute < 7 * 60:
			cursor += 7 * 60 - minute
		elif minute >= 15 * 60:
			cursor += 1440 - minute + 7 * 60
		else:
			var worked: int = mini(remaining, 15 * 60 - minute)
			cursor += worked
			remaining -= worked
	return cursor


func _cleanup() -> void:
	if daily != null:
		daily.cleanup()
		daily = null
	if is_instance_valid(endpoint):
		endpoint.queue_free()
	if is_instance_valid(city_tools):
		city_tools.queue_free()
	if is_instance_valid(storage):
		storage.queue_free()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	CitizenManager.citizens_by_id.clear()
