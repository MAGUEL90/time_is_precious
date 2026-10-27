extends "res://scenes/test_scenes/test_scene_defense_dialogue.gd"

## Run only with isolated APPDATA. Optional write/read phases share that sandbox.
const ARRIVAL_CODEC = preload("res://scenes/new_scenes/save_game/city_save_state.gd")
const ARRIVAL_VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const ARRIVAL_FILE: String = "user://workshop_arrival_schema8_fixture.json"
const ARRIVAL_WORKER: String = "schema8_fixture_worker"
const MANAGED_WORKER: String = "schema8_fixture_managed_worker"
var arrival_plot: Node
var arrival_visuals: Node2D
var arrival_snapshot = ARRIVAL_CODEC.new()

func _run() -> void:
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	await load_content()
	arrival_visuals = content.get_node("YSortWorld/WorkerRuntime/WorkerVisuals")
	arrival_visuals.set_process(false)
	for candidate: Node in get_tree().get_nodes_in_group("workshop_plots"):
		if candidate.construction.order_id == "construction:main_workshop":
			arrival_plot = candidate
	_expect(arrival_plot != null, "Fixture uses the native authored main workshop.")
	if arrival_plot == null:
		_finish_arrival()
		return
	var mode: String = "roundtrip"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--workshop-arrival-phase="):
			mode = arg.trim_prefix("--workshop-arrival-phase=")
	if mode.begins_with("read-"):
		_read_arrival(mode.ends_with("-arrived"), mode.contains("home"))
		_finish_arrival()
		return
	_seed_arrival_worker()
	var construction: Node = arrival_plot.construction
	construction.phase = "uncleared"
	var start: Dictionary = construction.start_clearing([ARRIVAL_WORKER] as Array[String], false)
	_expect(start.success, "Native worker clearing starts.")
	var worker: WorkerData = WorkerDatabase.get_worker_data(ARRIVAL_WORKER)
	_expect(not worker.physical_approach.is_empty() and not worker.physical_approach.arrived, "Clearing initializes a pending physical task synchronously.")
	var pose: Vector2 = worker.physical_approach.position
	TimeComponentManager.advance_minutes(10)
	_expect(not worker.physical_approach.arrived and worker.physical_approach.position == pose and construction.completes_at - construction._latest_time == construction.CLEARING_MINUTES, "Clock jumps without movement frames grant neither arrival nor clearing progress.")
	arrival_visuals.plot_presence.update(arrival_visuals, 0.1)
	_expect(worker.physical_approach.position.distance_to(pose) <= 2.401, "Route motion consumes only the continuous frame distance budget.")
	if mode in ["write-travelling", "write-home-travelling"]:
		_write_arrival(mode.contains("home"))
		_finish_arrival()
		return
	_drive_arrival()
	_expect(worker.physical_approach.arrived, "Clearing begins only after the native route reaches the entry feet.")
	if mode in ["write-arrived", "write-home-arrived"]:
		_write_arrival(mode.contains("home"))
		_finish_arrival()
		return
	TimeComponentManager.advance_minutes(1)
	_expect(construction.completes_at - construction._latest_time == construction.CLEARING_MINUTES - 1, "Arrived paid worker supplies one clearing minute.")
	_assert_schema8_roundtrip()
	_assert_legacy_migrations()
	_assert_invalid_approaches()
	_assert_overlap_accounting()
	_assert_home_route_pause()
	TimeComponentManager.advance_minutes(construction.CLEARING_MINUTES - 1)
	_expect(construction.phase == "empty", "Native clearing releases its worker on completion.")
	for item_id: String in construction.REQUIREMENTS:
		Inventory.add_item(item_id, construction.REQUIREMENTS[item_id])
	_move_actor_to_departure()
	_expect(construction.start_build([ARRIVAL_WORKER] as Array[String]).success, "Native construction consumes its original recipe and starts.")
	var build_duration: int = construction.completes_at - construction.started_at
	TimeComponentManager.advance_minutes(30)
	_expect(not worker.physical_approach.arrived and construction.completes_at - construction._latest_time == build_duration, "Building cannot advance before physical arrival.")
	_drive_arrival()
	TimeComponentManager.advance_minutes(build_duration)
	_expect(construction.phase == "built", "Arrived construction keeps its original duration and finishes.")
	worker.profession = WorkerData.Profession.CRAFTER
	var job: JobData = preload("res://resources/job_data/mudbrick_make.tres")
	worker.profession = job.requirement_profession
	for item_id: String in job.inputs:
		WorkShopStorage.add_item(item_id, int(job.inputs[item_id]))
	_move_actor_to_departure()
	var workshop: Node = arrival_plot.get_node("BuiltWorkshop")
	_expect(workshop.start_job_from_storage(job, [ARRIVAL_WORKER] as Array[String]), "Native workshop production starts with its unchanged recipe.")
	var order: WorkOrder = WorkManager.active_orders.get(worker.current_order_id)
	_expect(order != null and not worker.physical_approach.arrived, "Production binds its pending approach before returning.")
	if order != null:
		var duration: int = order.end_time_total_minutes - order.start_time_total_minutes
		var lots_before: int = WorkShopStorage.output_lots.size()
		var output_before: int = int(WorkShopStorage.items.get("wet_mudbrick", 0))
		TimeComponentManager.advance_minutes(20)
		_expect(WorkManager.active_orders.has(order.order_id) and order.end_time_total_minutes - WorkManager._last_total_minutes == duration, "Production time jump excludes all prearrival time.")
		_expect(WorkShopStorage.output_lots.size() == lots_before and int(WorkShopStorage.items.get("wet_mudbrick", 0)) == output_before, "Prearrival time creates no output lot or stored product.")
		_drive_arrival()
		TimeComponentManager.advance_minutes(duration)
		_expect(not WorkManager.active_orders.has(order.order_id) and WorkShopStorage.output_lots.size() == lots_before + 1, "Only arrived work produces exactly one native held output lot.")
		if WorkShopStorage.output_lots.size() == lots_before + 1:
			var lot: Dictionary = WorkShopStorage.output_lots.back()
			var quantity: int = int(lot.items.get("wet_mudbrick", 0))
			var base: int = int(job.outputs.get("wet_mudbrick", 0))
			var multiplier: float = worker.get_satisfaction_work_multiplier()
			_expect(quantity in [roundi(base * multiplier), roundi(base * multiplier * 0.75)] and not lot.fee_ids.is_empty() and lot.source_id == job.job_id, "Held output retains the native satisfaction/reliability quantity and job fee ownership.")
	_assert_managed_production_expiry(workshop, job)
	_finish_arrival()

func _seed_arrival_worker() -> void:
	var person := CitizenData.new()
	person.citizen_id = ARRIVAL_WORKER
	person.display_name = "Arrival fixture"
	person.population_status = CitizenData.PopulationStatus.RESIDENT
	person.employment_status = CitizenData.EmploymentStatus.HIRED
	person.profession = WorkerData.Profession.LABORER
	CitizenManager.citizens_by_id[ARRIVAL_WORKER] = person
	var worker := WorkerData.new()
	worker.worker_id = ARRIVAL_WORKER
	worker.profession = person.profession
	WorkerDatabase.workers_by_id[ARRIVAL_WORKER] = worker

func _move_actor_to_departure(worker_id: String = ARRIVAL_WORKER) -> void:
	var runtime: Node = arrival_visuals.get_parent()
	var marker: Node2D = runtime.get_node("WorkerDeparture").get_child(0)
	arrival_visuals.ensure_actor(worker_id, marker.global_position - Vector2(0, 16)).global_position = marker.global_position - Vector2(0, 16)

func _drive_arrival(worker_id: String = ARRIVAL_WORKER) -> void:
	var worker: WorkerData = WorkerDatabase.get_worker_data(worker_id)
	for _frame: int in range(4000):
		if worker.physical_approach.get("arrived", false):
			return
		arrival_visuals.plot_presence.update(arrival_visuals, 0.1)

func _assert_managed_production_expiry(workshop: Node, job: JobData) -> void:
	# A fixture-only applicant buys the real three-day contract at the existing
	# profession quote. The existing workshop API supplies its nine-day option.
	var next_open: int = (TimeComponentManager.current_day + 1) * 1440 + 8 * 60
	TimeComponentManager.advance_minutes(next_open - _clock_minute())
	var person := CitizenData.new()
	person.citizen_id = MANAGED_WORKER
	person.display_name = "Managed arrival fixture"
	person.profession = job.requirement_profession
	person.population_status = CitizenData.PopulationStatus.RESIDENT
	person.employment_status = CitizenData.EmploymentStatus.APPLICANT
	CitizenManager.citizens_by_id[MANAGED_WORKER] = person
	var price: int = WorkerDatabase.get_contract_price(person.profession, 3)
	_expect(price > 0, "Managed arrival case uses the configured profession package price.")
	if price <= 0:
		return
	Inventory.add_item("shekel", price * 3)
	var wallet_before: int = int(Inventory.items.get("shekel", 0))
	var worker: WorkerData = WorkerDatabase.hire_applicant(MANAGED_WORKER, 1, 3)
	_expect(worker != null and int(Inventory.items.get("shekel", 0)) == wallet_before - price, "Real hiring creates managed entitlement and debits its quote once.")
	if worker == null:
		return
	for item_id: String in job.inputs:
		WorkShopStorage.add_item(item_id, int(job.inputs[item_id]))
	_move_actor_to_departure(MANAGED_WORKER)
	_expect(workshop.start_job_from_storage(job, [MANAGED_WORKER] as Array[String], 9), "Managed worker starts the unchanged native recipe with the existing nine-day duration option.")
	var order: WorkOrder = WorkManager.active_orders.get(worker.current_order_id)
	if order == null:
		_expect(false, "Managed arrival case owns a native production order.")
		return
	var duration: int = order.end_time_total_minutes - order.start_time_total_minutes
	var pose: Vector2 = worker.physical_approach.position
	var lots_before: int = WorkShopStorage.output_lots.size()
	var expired_at: int = worker.get_paid_end_minute() + 15
	TimeComponentManager.advance_minutes(expired_at - _clock_minute())
	arrival_visuals.plot_presence.update(arrival_visuals, 1.0)
	_expect(worker.is_payroll_blocked() and not worker.physical_approach.arrived and worker.physical_approach.position == pose and worker.current_work_status != WorkerData.WorkStatus.WORKING, "A pending managed worker cannot walk or work after actual contract expiry.")
	_expect(order.end_time_total_minutes - WorkManager._last_total_minutes == duration and WorkShopStorage.output_lots.size() == lots_before, "Overlapping prearrival and unpaid intervals grant no progress or output.")
	wallet_before = int(Inventory.items.get("shekel", 0))
	var treasury_before: int = CityStockManager.treasury_shekel
	var renewed: bool = WorkerDatabase.renew_contract(MANAGED_WORKER, 3)
	_expect(renewed and worker.payroll_paid_start_minute == _clock_minute() and int(Inventory.items.get("shekel", 0)) == wallet_before - price and CityStockManager.treasury_shekel == treasury_before, "Real pending renewal starts now and debits only its current wallet quote once.")
	_expect(not worker.physical_approach.arrived and worker.physical_approach.position == pose and order.end_time_total_minutes - WorkManager._last_total_minutes == duration, "Renewal preserves the pending pose and cannot backfill prearrival time.")
	TimeComponentManager.advance_minutes(2)
	_expect(order.end_time_total_minutes - WorkManager._last_total_minutes == duration, "Newly paid minutes still cannot count while the route has no movement frames.")
	_drive_arrival(MANAGED_WORKER)
	_expect(worker.physical_approach.arrived, "The renewed pending worker reaches entry by the actual retained route.")
	TimeComponentManager.advance_minutes(1)
	_expect(order.end_time_total_minutes - WorkManager._last_total_minutes == duration - 1, "Only the subsequent arrived paid minute advances production.")
	var remaining: int = order.end_time_total_minutes - WorkManager._last_total_minutes
	var previous: int = _clock_minute()
	var second_expiry: int = worker.get_paid_end_minute()
	TimeComponentManager.advance_minutes(second_expiry + 15 - previous)
	arrival_visuals.plot_presence.update(arrival_visuals, 1.0)
	var expected_remaining: int = remaining - (second_expiry - previous)
	_expect(worker.is_payroll_blocked() and worker.physical_approach.arrived and worker.current_work_status != WorkerData.WorkStatus.WORKING and order.end_time_total_minutes - WorkManager._last_total_minutes == expected_remaining, "An arrived managed worker contributes only through expiry and then stops working.")
	wallet_before = int(Inventory.items.get("shekel", 0))
	var arrival_minute: int = worker.physical_approach.arrival_minute
	renewed = WorkerDatabase.renew_contract(MANAGED_WORKER, 3)
	_expect(renewed and int(Inventory.items.get("shekel", 0)) == wallet_before - price and worker.physical_approach.arrival_minute == arrival_minute and order.end_time_total_minutes - WorkManager._last_total_minutes == expected_remaining, "Arrived renewal debits once, preserves historical arrival, and does not backfill its unpaid gap.")
	arrival_visuals.plot_presence.update(arrival_visuals, 0.0)
	TimeComponentManager.advance_minutes(1)
	_expect(worker.current_work_status == WorkerData.WorkStatus.WORKING and order.end_time_total_minutes - WorkManager._last_total_minutes == expected_remaining - 1 and WorkShopStorage.output_lots.size() == lots_before, "Arrived renewal resumes precisely one paid production minute without a duplicate completion.")

func _assert_schema8_roundtrip() -> void:
	var before: Dictionary = arrival_snapshot.capture(content)
	_expect(not before.is_empty() and before.schema_version == 8, "Active writer explicitly writes schema8.")
	if before.is_empty():
		return
	var document: Dictionary = JSON.parse_string(JSON.stringify(before, "", true, true))
	_expect(arrival_snapshot.prepare(document, content), "Schema8 validates its saved arrived state: " + arrival_snapshot.error)
	if not arrival_snapshot.prepared.is_empty():
		var restored: WorkerData = arrival_snapshot.prepared.workers.workers_by_id[ARRIVAL_WORKER]
		_expect(restored.physical_approach == WorkerDatabase.get_worker_data(ARRIVAL_WORKER).physical_approach, "Saved position, task, target, and historical arrival survive JSON exactly.")

func _assert_legacy_migrations() -> void:
	var document: Dictionary = arrival_snapshot.capture(content)
	for version: int in range(1, 8):
		var values = ARRIVAL_VALUES.new()
		var raw: Dictionary = values.decode(document.state)
		if version < 7:
			raw.raid.erase("notification_seen_keys")
		if version < 6:
			for plot: Dictionary in raw.plots.values():
				plot.erase("payroll_work_remainder")
		if version < 4:
			raw.erase("pickup_sources")
			if version == 3:
				raw["date_palms"] = arrival_snapshot._legacy_palms.capture()
		var legacy: Dictionary = {"schema_version": version, "scenario": "city_mvp", "location": "city", "state": values.encode(raw)}
		if version == 1:
			legacy.erase("location")
		_strip_worker_fields(legacy.state, version)
		_expect(arrival_snapshot.prepare(legacy, content), "Strict v%d migration accepts exactly its historical worker fields: %s" % [version, arrival_snapshot.error])
		if not arrival_snapshot.prepared.is_empty():
			var restored: WorkerData = arrival_snapshot.prepared.workers.workers_by_id[ARRIVAL_WORKER]
			_expect(restored.physical_approach.is_empty() and restored.current_order_id == WorkerDatabase.get_worker_data(ARRIVAL_WORKER).current_order_id, "Legacy active task preserves its previous inside interpretation and reservation.")
			_expect(arrival_snapshot.prepared.inventory.items == raw.inventory.items and arrival_snapshot.prepared.plots == _migrated_plots(raw.plots), "Legacy migration preserves inventory and construction progress.")

func _migrated_plots(source: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	for plot: Dictionary in result.values():
		if not plot.has("payroll_work_remainder"):
			plot["payroll_work_remainder"] = 0
	return result

func _strip_worker_fields(value: Variant, version: int) -> void:
	if value is Array:
		for child: Variant in value:
			_strip_worker_fields(child, version)
	elif value is Dictionary:
		if value.get("class") == "WorkerData":
			value.fields.erase("physical_approach")
			if version < 7:
				for field: String in ARRIVAL_VALUES.CONTRACT_FIELDS:
					value.fields.erase(field)
			if version < 5:
				for field: String in ARRIVAL_VALUES.PAYROLL_FIELDS:
					value.fields.erase(field)
		for child: Variant in value.values():
			_strip_worker_fields(child, version)

func _assert_invalid_approaches() -> void:
	var worker: WorkerData = WorkerDatabase.get_worker_data(ARRIVAL_WORKER)
	var valid: Dictionary = worker.physical_approach.duplicate(true)
	for invalid: String in ["extra", "bad_type", "nonfinite", "out_of_bounds", "unsafe_task", "missing_owner", "unknown_task", "wrong_target", "future_arrival"]:
		worker.physical_approach = valid.duplicate(true)
		match invalid:
			"extra": worker.physical_approach["script"] = "unapproved"
			"bad_type": worker.physical_approach.arrived = 1
			"nonfinite": worker.physical_approach.position = Vector2(INF, 0)
			"out_of_bounds": worker.physical_approach.position = Vector2(2000000, 0)
			"unsafe_task": worker.physical_approach.task = "res://unapproved"
			"missing_owner": worker.physical_approach.owner = "unknown_plot"
			"unknown_task": worker.physical_approach.task = "unknown_task"
			"wrong_target":
				worker.physical_approach.target += Vector2(100, 0)
				worker.physical_approach.position = worker.physical_approach.target
			"future_arrival": worker.physical_approach.arrival_minute += 100000
		_expect(arrival_snapshot.capture(content).is_empty(), "Schema8 rejects invalid physical approach: " + invalid)
	worker.physical_approach = valid

func _assert_overlap_accounting() -> void:
	var worker := WorkerData.new()
	worker.payroll_start_day = 0
	worker.payroll_paid_from_day = 0
	worker.payroll_paid_until_day = 0
	worker.payroll_paid_start_minute = 500
	worker.begin_physical_approach("plot", "fixture_task", "fixture_plot", Vector2.ZERO, Vector2.ZERO)
	worker.physical_approach.arrived = true
	worker.physical_approach.arrival_minute = 550
	_expect(worker.get_arrived_paid_minutes(450, 600, "plot", "fixture_task", "fixture_plot") == 50, "Overlapping unpaid and prearrival spans count their union once.")
	worker.payroll_paid_start_minute = 575
	_expect(worker.get_arrived_paid_minutes(450, 600, "plot", "fixture_task", "fixture_plot") == 25, "Renewal beginning after arrival cannot backfill unpaid travel/work.")
	worker.physical_approach.arrived = false
	worker.physical_approach.arrival_minute = -1
	_expect(worker.get_arrived_paid_minutes(450, 600, "plot", "fixture_task", "fixture_plot") == 0, "Renewal while travelling grants no prearrival work.")

func _assert_home_route_pause() -> void:
	var worker: WorkerData = WorkerDatabase.get_worker_data(ARRIVAL_WORKER)
	var construction: Node = arrival_plot.construction
	var store: Node = WorkStateRuntime.get_node("CitySave")
	# Put the fixture on an actual pending route, then use the native parking
	# handoff. Removing the plot from the tree models its disappearance at home.
	_move_actor_to_departure()
	arrival_plot.begin_worker_approach(ARRIVAL_WORKER, construction.order_id + ":" + construction.phase)
	arrival_visuals.plot_presence.states.clear()
	var world: Node = content.get_node("YSortWorld")
	_expect(store.prepare_home_departure(content, arrival_snapshot.HOME_PATH), "Native home handoff retains the worker visual owner.")
	world.remove_child(arrival_plot)
	var pose: Vector2 = worker.physical_approach.position
	TimeComponentManager.is_paused = true
	arrival_visuals.plot_presence.update(arrival_visuals, 1.0)
	_expect(worker.physical_approach.position == pose and not worker.physical_approach.arrived, "Paused clock blocks offscreen travel.")
	TimeComponentManager.is_paused = false
	get_tree().paused = true
	arrival_visuals.plot_presence.update(arrival_visuals, 1.0)
	_expect(worker.physical_approach.position == pose and not worker.physical_approach.arrived, "Paused tree blocks offscreen travel.")
	get_tree().paused = false
	arrival_visuals.plot_presence.update(arrival_visuals, 0.1)
	_expect(worker.physical_approach.position != pose and not worker.physical_approach.arrived, "Retained owner advances a bounded route while its plot is absent.")
	_drive_arrival()
	_expect(worker.physical_approach.arrived, "Persistent construction identity records offscreen actual arrival.")
	world.add_child(arrival_plot)
	store.cancel_home_departure()

func _home_fixture() -> Node:
	var store: Node = WorkStateRuntime.get_node("CitySave")
	_expect(store.prepare_home_departure(content, arrival_snapshot.HOME_PATH), "Home checkpoint uses the native retained-runtime handoff.")
	arrival_plot.free()
	var home: Node = preload("res://scenes/player_home_interior/player_home_interior.tscn").instantiate()
	add_child(home)
	return home

func _write_arrival(at_home: bool = false) -> void:
	var location: Node = _home_fixture() if at_home else content
	var document: Dictionary = arrival_snapshot.capture(location)
	_expect(not document.is_empty(), "Cross-process fixture captures pending or arrived state: " + arrival_snapshot.error)
	if document.is_empty():
		return
	_expect(not at_home or document.get("location") == "home", "Home checkpoint records its explicit location.")
	var file := FileAccess.open(ARRIVAL_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify(document, "", true, true))
	file.close()

func _read_arrival(expected_arrived: bool, from_home: bool = false) -> void:
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ARRIVAL_FILE))
	_expect(arrival_snapshot.prepare(document, content), "Fresh-process schema8 checkpoint validates: " + arrival_snapshot.error)
	if arrival_snapshot.prepared.is_empty():
		return
	arrival_snapshot.apply_prepared(content, false)
	_expect(not from_home or arrival_snapshot.prepared_location == "home", "Fresh process retains the saved home location.")
	var home: Node = _home_fixture() if from_home else null
	var worker: WorkerData = WorkerDatabase.get_worker_data(ARRIVAL_WORKER)
	var saved: Dictionary = worker.physical_approach.duplicate(true)
	arrival_visuals.plot_presence.update(arrival_visuals, 0.0)
	_expect(worker.physical_approach == saved and saved.arrived == expected_arrived, "Continue retains exact saved travelling/arrived pose without resetting inside.")
	if home != null:
		_expect(not arrival_snapshot.capture(home).is_empty(), "Restored home checkpoint can be recaptured with the same persistent route owner.")
	if not expected_arrived:
		_drive_arrival()
		_expect(worker.physical_approach.arrived, "Restored pending route can reach its entry without teleporting.")

func _finish_arrival() -> void:
	print("WorkshopArrivalSchema8Test: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
