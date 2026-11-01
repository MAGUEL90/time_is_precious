extends "res://scenes/test_scenes/test_scene_city_save_economy.gd"

## Real city save and separate-process Continue for a pending final shipment.
const RESIGN_CHECKPOINT: String = "user://worksite_resignation_continue/checkpoint.json"
const PARTIAL: float = 19.0
const FAILED_DROP_SITE: StringName = &"ClaySiteA"
const FAILED_DROP_WORKER: String = "resign_failed_drop_worker"
var phase: String = "write"
var restore_notifications: int = 0
var ready_notifications: int = 0

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--resign-phase="):
			phase = argument.trim_prefix("--resign-phase=")
	_expect(phase in ["write", "read"], "A write or read phase is required.")
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	_reset_singletons_before_load()
	await load_content()
	for _frame: int in range(2):
		await get_tree().process_frame
	runtime = content.get_node("YSortWorld/WorkerRuntime")
	city_storage = WorkStateRuntime.get_node("CityToolStorage")
	wood_storage = runtime.get_node("CityStorageArea/DeliveryPoint")
	store = WorkStateRuntime.get_node("CitySave")
	store.disk.path = RESIGN_CHECKPOINT
	if phase == "write":
		_test_write()
	else:
		_test_read()
	await _finish_resign_continue()

func _test_write() -> void:
	_expect(not FileAccess.file_exists(RESIGN_CHECKPOINT), "Use a fresh isolated user-data directory.")
	_prepare_city_state()
	if not _hire_and_assign_team():
		return
	var laborer: WorkerData = WorkerDatabase.get_worker_data(LABORER_ID)
	var hauler: WorkerData = WorkerDatabase.get_worker_data(HAULER_ID)
	var job: Dictionary = runtime.daily.jobs[WOOD_SITE]
	job.progress[LABORER_ID] = PARTIAL
	# One explicit three-log fixture load; the site, pile and later cargo total 72.
	runtime.sites[WOOD_SITE].stock -= 3
	_expect(runtime._drop_daily_output(3, runtime.get_node("WorksiteMarkers/WoodSite")), "Seed three real ground logs.")
	TimeComponentManager.advance_minutes(1)
	var route: Dictionary = runtime.hauling.routes[HAULER_ID]
	_expect(route.phase == "outbound" and int(route.cargo.quantity) == 3 and _wood_total() == 72,
		"The real hauler has one conserved outbound load.")
	var partial_before: float = float(job.progress[LABORER_ID])
	CitizenManager.get_citizen(LABORER_ID).satisfaction = 0.0
	CitizenManager.get_citizen(HAULER_ID).satisfaction = 0.0
	WorkerDatabase.resign_idle_workers_at_zero()
	_expect(not WorkerDatabase.has_worker_data(LABORER_ID) and laborer.profession_xp >= 0
		and runtime.daily.jobs[WOOD_SITE].ids == [HAULER_ID]
		and is_equal_approx(float(runtime.daily.pending_progress[WOOD_SITE][0]), partial_before),
		"The laborer resigns immediately and leaves its exact incomplete item at the site.")
	_expect(hauler.resignation_pending and bool(route.resigning) and bool(route.removing)
		and int(route.cargo.quantity) == 3 and city_storage.has_equipped(HAULER_ID, "cart"),
		"The loaded hauler remains pending with its one shipment and allocated cart.")
	Inventory.add_item("shekel", 1)
	var wallet_before: int = int(Inventory.items.get("shekel", 0))
	_expect(wallet_before >= 1 and not WorkerDatabase.renew_contract(HAULER_ID, 3)
		and int(Inventory.items.get("shekel", 0)) == wallet_before,
		"A pending hauler cannot renew or pay for another contract before Save.")
	var failed_worker := WorkerData.new()
	failed_worker.worker_id = FAILED_DROP_WORKER
	failed_worker.display_name = "Failed drop worker"
	failed_worker.satisfaction = 0.8
	WorkerDatabase.workers_by_id[FAILED_DROP_WORKER] = failed_worker
	_expect(runtime.daily.toggle(FAILED_DROP_SITE, FAILED_DROP_WORKER)
		and runtime.daily.start(FAILED_DROP_SITE, func(_quantity: int) -> bool: return false),
		"Start a second site's failed-drop fixture.")
	runtime.sites[FAILED_DROP_SITE].stock -= 2
	runtime.daily.jobs[FAILED_DROP_SITE].units = 2
	failed_worker.resignation_pending = true
	_expect(runtime.daily.request_resignation(FAILED_DROP_WORKER)
		and int(runtime.daily.pending_output[FAILED_DROP_SITE].quantity) == 2,
		"The last worker's completed but undroppable output has a separate owner.")
	WorkerDatabase.resign_idle_workers_at_zero()
	var raw_sites: Dictionary = store.snapshot._sites.capture(runtime)
	var corrupt: Dictionary = raw_sites.duplicate(true)
	corrupt.routes[HAULER_ID].resigning = false
	_expect(not store.snapshot._sites.validate(corrupt, runtime, WorkerDatabase.workers_by_id, WorkerDatabase.dismissed_workers),
		"A pending worker and non-resigning route cannot be loaded.")
	corrupt = raw_sites.duplicate(true)
	corrupt.pending_progress[str(WOOD_SITE)] = [float(runtime.sites[WOOD_SITE].minutes_per_unit)]
	_expect(not store.snapshot._sites.validate(corrupt, runtime, WorkerDatabase.workers_by_id, WorkerDatabase.dismissed_workers),
		"A complete item cannot masquerade as saved partial progress.")
	_expect(store.save_checkpoint(), "Save the pending real-city worksite: " + store.last_error)

func _test_read() -> void:
	var stockpile: Node = runtime.get_node("WoodStorage/Storage")
	stockpile.changed.connect(_on_restored_stockpile_changed)
	runtime.daily.resignation_ready.connect(func(id: String):
		if id == HAULER_ID:
			ready_notifications += 1
	)
	_expect(store.load_checkpoint(), "Continue the pending shipment in a fresh process: " + store.last_error)
	var worker: WorkerData = WorkerDatabase.get_worker_data(HAULER_ID)
	var route: Dictionary = runtime.hauling.routes.get(HAULER_ID, {})
	_expect(restore_notifications == 1, "Storage observers run only after the route, worker and site progress are restored.")
	_expect(worker != null and worker.resignation_pending and bool(route.get("resigning", false))
		and int(route.get("cargo", {}).get("quantity", 0)) == 3 and _wood_total() == 72,
		"Continue restores the same pending cargo and worker without duplication.")
	_expect(not WorkerDatabase.has_worker_data(LABORER_ID)
		and is_equal_approx(float(runtime.daily.pending_progress[WOOD_SITE][0]), PARTIAL),
		"Continue restores the departed gatherer's partial item at its site.")
	_expect(int(runtime.daily.pending_output[FAILED_DROP_SITE].quantity) == 2,
		"Continue restores completed output which could not previously be dropped.")
	var wallet_before: int = int(Inventory.items.get("shekel", 0))
	_expect(wallet_before >= 1 and not WorkerDatabase.renew_contract(HAULER_ID, 3)
		and int(Inventory.items.get("shekel", 0)) == wallet_before,
		"The pending hauler still cannot renew or pay after Continue.")
	CitizenManager.get_citizen(HAULER_ID).satisfaction = 0.8
	var remaining: int = maxi(1, int(route.arrival) - _clock_minute())
	TimeComponentManager.advance_minutes(remaining)
	_expect(int(city_storage.items.get("wood_log", 0)) == 3 and _wood_total() == 72
		and not WorkerDatabase.has_worker_data(HAULER_ID) and ready_notifications == 1,
		"The original load is accepted once and the hauler resigns synchronously despite recovery.")
	_expect(not runtime.daily.pending_output.has(FAILED_DROP_SITE)
		and runtime._daily_output_count(FAILED_DROP_SITE) == 2,
		"Previously undroppable output reaches the restored ground exactly once.")
	_expect(not city_storage.has_equipped(HAULER_ID, "cart")
		and int(WorkerDatabase.dismissed_workers[HAULER_ID].profession_xp) == 3,
		"Delivery XP and released city equipment survive the final departure.")
	TimeComponentManager.advance_minutes(3)
	_expect(int(city_storage.items.get("wood_log", 0)) == 3 and ready_notifications == 1,
		"Further no-frame time advancement does not deliver or resign twice.")
	_expect(runtime.daily.toggle(WOOD_SITE, PRODUCTION_ID)
		and runtime.daily.start(WOOD_SITE, runtime._drop_daily_output.bind(runtime.get_node("WorksiteMarkers/WoodSite"))),
		"A paid replacement can take the worksite assignment.")
	_expect(not runtime.daily.pending_progress.has(WOOD_SITE)
		and is_equal_approx(float(runtime.daily.jobs[WOOD_SITE].progress[PRODUCTION_ID]), PARTIAL),
		"The replacement claims the restored partial item once.")

func _on_restored_stockpile_changed() -> void:
	var worker: WorkerData = WorkerDatabase.get_worker_data(HAULER_ID)
	var route: Dictionary = runtime.hauling.routes.get(HAULER_ID, {})
	if worker != null and worker.resignation_pending and bool(route.get("resigning", false)) \
		and int(route.get("cargo", {}).get("quantity", 0)) == 3 and runtime.daily.pending_progress.has(WOOD_SITE):
		restore_notifications += 1
	else:
		_expect(false, "A stockpile restore observer saw incomplete or mixed worksite state.")

func _finish_resign_continue() -> void:
	if is_instance_valid(content):
		content.queue_free()
		await get_tree().process_frame
	_restore_clock()
	print("WorksiteResignationContinueTest ", phase, ": ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
