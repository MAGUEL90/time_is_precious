extends "res://scenes/test_scenes/test_scene_defense_dialogue.gd"

## Two separate engine processes share only this isolated checkpoint.
const TEST_SAVE: String = "user://workshop_resignation_continue/checkpoint.json"
const TEST_JOB: JobData = preload("res://resources/job_data/mudbrick_make.tres")
const FIRST: String = "resignation_save_first"
const REPLACEMENT: String = "resignation_save_replacement"
const LEGACY: String = "resignation_save_unlocated"
const OTHER_REPLACEMENT: String = "resignation_save_other_replacement"

func _run() -> void:
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	await load_content()
	await get_tree().process_frame
	content.get_node("YSortWorld/WorkerRuntime/WorkerVisuals").set_process(false)
	var store: Node = WorkStateRuntime.get_node("CitySave")
	store.disk.path = TEST_SAVE
	var phase: String = "write"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--workshop-resignation-phase="):
			phase = argument.trim_prefix("--workshop-resignation-phase=")
	if phase == "write":
		_write_checkpoint(store)
	elif phase == "read":
		_read_checkpoint(store)
	elif phase == "finish":
		_finish_checkpoint(store)
	else:
		_expect(false, "Unknown checkpoint fixture phase.")
	print("WorkshopResignationContinueTest ", phase, ": ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _make_worker(id: String) -> WorkerData:
	var citizen := CitizenData.new()
	citizen.citizen_id = id
	citizen.display_name = id
	citizen.profession = TEST_JOB.requirement_profession
	citizen.satisfaction = 0.8
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.HIRED
	CitizenManager.citizens_by_id[id] = citizen
	var worker := WorkerData.new()
	worker.worker_id = id
	worker.display_name = id
	worker.profession = citizen.profession
	WorkerDatabase.workers_by_id[id] = worker
	return worker

func _write_checkpoint(store: Node) -> void:
	_expect(not FileAccess.file_exists(TEST_SAVE), "Write uses a fresh isolated checkpoint path.")
	_set_clock_minute(3 * 1440 + 14 * 60 + 50)
	var plot: Node = content.get_node("YSortWorld/WorkshopPlot")
	plot.construction.phase = "built"
	plot._sync_construction()
	var second_plot: Node = content.get_node("YSortWorld/WorkshopPlot2")
	second_plot.construction.phase = "built"
	second_plot._sync_construction()
	var workshop: WorkShop = plot.get_node("BuiltWorkshop")
	var first: WorkerData = _make_worker(FIRST)
	_make_worker(REPLACEMENT)
	var legacy: WorkerData = _make_worker(LEGACY)
	_make_worker(OTHER_REPLACEMENT)
	for item_id: String in TEST_JOB.inputs:
		WorkShopStorage.add_item(item_id, 2 * int(TEST_JOB.inputs[item_id]))
	_expect(workshop.assign_workers([FIRST] as Array[String]) and workshop.start_job_from_storage(TEST_JOB, [FIRST] as Array[String]), "An authored plot starts one real shaping order.")
	var order: WorkOrder = WorkManager.active_orders.get(first.current_order_id)
	if order == null:
		return
	first.physical_approach.position = first.physical_approach.target
	_expect(first.mark_physical_arrival(order.order_id), "The original worker reaches the authored entrance.")
	_expect(TimeComponentManager.advance_minutes(10), "Ten actual paid shift minutes advance.")
	_expect(order.end_time_total_minutes - _clock_minute() == 20, "The batch has twenty minutes left at shift end.")
	CitizenManager.citizens_by_id[FIRST].satisfaction = 0.05
	CityStockManager.shelter_capacity = 0
	var archived_before: int = WorkerDatabase.dismissed_workers.size()
	_expect(TimeComponentManager.advance_minutes(9 * 60), "The real clock crosses midnight after the workshop shift.")
	_expect(is_zero_approx(CitizenManager.citizens_by_id[FIRST].satisfaction), "The missing need reduces Satisfaction from five percent to zero at daily settlement.")
	_expect(WorkerDatabase.dismissed_workers.size() == archived_before + 1, "Daily settlement causes exactly one resignation.")
	_expect(WorkerDatabase.dismissed_workers.has(FIRST) and not WorkerDatabase.has_worker_data(FIRST), "The resignation archives the original worker.")
	_expect(order.current_status == WorkOrder.Status.QUEUED and order.worker_id.is_empty(), "The paid inputs remain attached to a workerless paused order.")
	_expect(order.end_time_total_minutes - _clock_minute() == 20, "All twenty unfinished minutes remain at the midnight resignation.")
	var legacy_id: String = WorkManager.start_job(TEST_JOB, WorkOrder.Worker_Type.NPC, LEGACY, null, WorkShopStorage, WorkShopStorage, TEST_JOB.workshop_fee_amount)
	var unlocated: WorkOrder = WorkManager.active_orders.get(legacy_id)
	_expect(unlocated != null and str(unlocated.get_meta("visual_plot_id", "")).is_empty() and legacy.physical_approach.is_empty(), "A legacy direct order has no inferred workshop identity.")
	CitizenManager.citizens_by_id[LEGACY].satisfaction = 0.0
	WorkerDatabase.resign_idle_workers_at_zero()
	_expect(unlocated != null and unlocated.current_status == WorkOrder.Status.QUEUED and unlocated.worker_id.is_empty(), "The unlocated legacy batch is preserved on resignation.")
	_expect(WorkShopStorage.items.is_empty() and WorkShopStorage.output_lots.is_empty(), "No raw materials are restored or output created by resignation.")
	_expect(store.save_checkpoint(), "A real disk checkpoint saves the paused batch: " + store.last_error)

func _read_checkpoint(store: Node) -> void:
	_expect(store.load_checkpoint(), "A fresh process continues the saved batch: " + store.last_error)
	if WorkManager.active_orders.is_empty():
		_expect(false, "Continue restores the paused work order.")
		return
	var order: WorkOrder
	var unlocated: WorkOrder
	for candidate: WorkOrder in WorkManager.active_orders.values():
		if str(candidate.get_meta("visual_plot_id", "")).is_empty():
			unlocated = candidate
		else:
			order = candidate
	_expect(order != null and unlocated != null, "Continue restores located and unlocated paused batches.")
	if order == null or unlocated == null:
		return
	var order_id: String = order.order_id
	_expect(order.current_status == WorkOrder.Status.QUEUED and order.worker_id.is_empty() and order.end_time_total_minutes - _clock_minute() == 20, "Continue preserves workerless status and exact remaining work.")
	_expect(WorkManager.source_item_store_by_order_id[order_id] == WorkShopStorage and WorkManager.output_item_store_by_order_id[order_id] == WorkShopStorage and int(WorkManager.service_fee_by_order[order_id]) == TEST_JOB.workshop_fee_amount, "Source, destination and original fee survive the disk boundary.")
	var next_shift: int = TimeComponentManager.current_day * 1440 + 7 * 60 + 5
	if next_shift <= _clock_minute():
		next_shift += 1440
	_expect(TimeComponentManager.advance_minutes(next_shift - _clock_minute()), "The time skip to the next shift succeeds.")
	_expect(WorkManager.active_orders.has(order_id) and order.end_time_total_minutes - _clock_minute() == 20 and WorkShopStorage.output_lots.is_empty(), "A paused order remains frozen through the next morning.")
	var plot: Node = content.get_node("YSortWorld/WorkshopPlot")
	var workshop: WorkShop = plot.get_node("BuiltWorkshop")
	var second_plot: Node = content.get_node("YSortWorld/WorkshopPlot2")
	var second_workshop: WorkShop = second_plot.get_node("BuiltWorkshop")
	_expect(workshop.get_paused_orders().has(unlocated) and second_workshop.get_paused_orders().has(unlocated), "An unlocated restored batch can be explicitly adopted at either actual workshop.")
	_expect(second_workshop.resume_paused_job(unlocated.order_id, OTHER_REPLACEMENT) and str(unlocated.get_meta("visual_plot_id", "")) == second_plot.construction.order_id, "The selected second plot adopts the legacy batch and binds its own entrance.")
	_expect(workshop.resume_paused_job(order_id, REPLACEMENT), "The restored order accepts a replacement at its own plot.")
	var replacement: WorkerData = WorkerDatabase.get_worker_data(REPLACEMENT)
	if replacement == null or replacement.physical_approach.is_empty():
		_expect(false, "Replacement owns the restored physical approach.")
		return
	replacement.physical_approach.position = replacement.physical_approach.target
	_expect(replacement.mark_physical_arrival(order_id), "The replacement reaches the plot after Continue.")
	_expect(store.save_checkpoint(), "A second checkpoint preserves the already-resumed worker and route: " + store.last_error)

func _finish_checkpoint(store: Node) -> void:
	_expect(store.load_checkpoint(), "A second fresh process continues the active replacement: " + store.last_error)
	var order: WorkOrder
	for candidate: WorkOrder in WorkManager.active_orders.values():
		if candidate.worker_id == REPLACEMENT:
			order = candidate
	_expect(order != null and order.current_status == WorkOrder.Status.RUNNING, "The active replacement survives the second process boundary.")
	if order == null:
		return
	var order_id: String = order.order_id
	var plot: Node = content.get_node("YSortWorld/WorkshopPlot")
	var workshop: WorkShop = plot.get_node("BuiltWorkshop")
	_expect(not workshop.assigned_worker_ids.has(REPLACEMENT), "The recreated workshop has no transient selection to retain.")
	workshop.assigned_worker_ids.append(REPLACEMENT) # A stale selection during teardown must not count as live.
	workshop.queue_free() # Completion can occur during deferred city-scene teardown.
	_expect(TimeComponentManager.advance_minutes(19) and WorkManager.active_orders.has(order_id) and WorkShopStorage.output_lots.is_empty(), "No output appears before the final remaining minute.")
	_expect(TimeComponentManager.advance_minutes(1) and not WorkManager.active_orders.has(order_id) and WorkShopStorage.output_lots.size() == 1, "Exactly one output lot completes after twenty minutes.")
	var citizen: CitizenData = CitizenManager.get_citizen(REPLACEMENT)
	_expect(citizen != null and citizen.employment_status == CitizenData.EmploymentStatus.HIRED and citizen.can_be_assigned(), "Completion without a live selection releases the worker for another assignment.")
	workshop.free()
	plot._sync_construction()
	workshop = plot.get_node("BuiltWorkshop")
	_expect(workshop._replacement_reason(WorkerDatabase.get_worker_data(REPLACEMENT), TEST_JOB).is_empty(), "The same worker is available to the workshop again.")
	_expect(store.save_checkpoint() and store.load_checkpoint() and WorkShopStorage.output_lots.size() == 1, "A second save and load never duplicates completed output.")
