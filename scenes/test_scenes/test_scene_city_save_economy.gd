extends "res://scenes/test_scenes/test_scene_defense_dialogue.gd"

## Main-map economy checkpoint regression. Run in its own Godot process.
const CHECKPOINT_PATH: String = "user://city_save_economy_test/checkpoint.json"
const LABORER_ID: String = "initial_workshop_laborer"
const HAULER_ID: String = "initial_worksite_hauler"
const PRODUCTION_ID: String = "city_save_production_laborer"
const CART_UNIT_ID: String = "initial_worksite_cart"
const GLOVE_UNIT_ID: String = "city_save_laborer_glove"
const WOOD_SITE: StringName = &"WoodSite"
const PROCESS_ID: String = "drying_mudbrick"

var store: Node
var runtime: Node
var city_storage: Node
var wood_storage: Node

func _run() -> void:
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
	# Isolate this fixture before the store's first read or write.
	store.disk.path = CHECKPOINT_PATH
	_clean_files()
	_prepare_city_state()
	if not _hire_and_assign_team():
		await _finish()
		return
	_settle_needs()
	_expect(CitizenNeedsManager.last_processed_day == TimeComponentManager.current_day
		and CitizenNeedsManager.last_clothing_processed_day == TimeComponentManager.current_day,
		"The fixture starts from a completed food, clothing and shelter settlement.")
	_expect(CitizenNeedsManager.clothing_allocations.size() == 3
		and CitizenNeedsManager.last_needs_results.size() == 3,
		"Each resident has one settled needs record and a retained clothing allocation.")
	_expect(_all_needs_fulfilled() and is_equal_approx(CitizenManager.get_citizen(PRODUCTION_ID).satisfaction, 0.55),
		"The hired residents have real fulfilled needs and the resulting satisfaction value.")

	# Assignments begin on the next daily shift. Advance the real clock so the
	# worksite gathers natural output and the real Hauler takes it into cargo.
	var deadline: int = _clock_minute() + 1800
	while (not runtime.daily.hauling.routes.has(HAULER_ID)
		or str(runtime.daily.hauling.routes[HAULER_ID].phase) != "outbound") \
		and _clock_minute() < deadline:
		TimeComponentManager.advance_minutes(1)
	_expect(runtime.daily.hauling.routes.has(HAULER_ID), "The hired Hauler starts a live trip from the assigned resource site.")
	if not runtime.daily.hauling.routes.has(HAULER_ID):
		await _finish()
		return
	var route: Dictionary = runtime.daily.hauling.routes[HAULER_ID]
	_expect(route.phase == "outbound" and route.cargo.item_id == "wood_log"
		and int(route.cargo.quantity) == 3,
		"Save begins with three real wood logs in the outbound Hauler cargo.")
	_expect(int(city_storage.items.get("wood_log", 0)) == 0
		and runtime._daily_output_count(WOOD_SITE) == 0
		and int(runtime.sites[WOOD_SITE].stock) == 69,
		"Gathered stock is represented by the in-flight cargo exactly once.")
	_expect(_wood_total() == 72, "Wood stock, ground output, storage and cargo conserve the site's initial stock.")

	# Start the registered drying process through its real manager and Workshop
	# Storage. StationState.slots then contains an approved ProcessBatch Resource.
	_expect(WorkshopFacilityManager.set_facility_level("drying_yard", 1),
		"The actual facility manager opens one drying-yard station slot.")
	TimeComponentManager.current_weather = "clear"
	TimeComponentManager.emit_time_signal()
	WorkShopStorage.add_item("wet_mudbrick", 20)
	_expect(ProcessManager.start_registered_process(PROCESS_ID, 20),
		"The real drying process consumes twenty Workshop Storage inputs.")
	var station: StationState = ProcessManager.stations["drying_yard"] as StationState
	var batch: ProcessBatch = station.slots[0] as ProcessBatch
	_expect(batch != null and batch.process_id == PROCESS_ID and batch.quantity == 20
		and batch.status == ProcessBatch.BatchStatus.RUNNING,
		"The checkpoint contains a real running ProcessBatch in the station slot.")
	_expect(WorkShopStorage.unpaid_claims_ledger.size() == 1
		and WorkShopStorage.output_lots.is_empty(),
		"The running batch retains its registered fee before output completion.")
	var saved: bool = store.save_checkpoint()
	_expect(saved, "Manual Save writes the economy checkpoint: " + store.last_error)
	if not saved or batch == null:
		await _finish()
		return
	var before: Dictionary = store.snapshot.capture(content)
	_expect(not before.is_empty(), "The saved economy world can be captured through the same snapshot interface.")

	# Let the real route deliver and the real process complete, then load the
	# earlier checkpoint. This tests rollback of stock, cargo, workers and outputs.
	var route_arrival_minutes: int = maxi(int(route.arrival) - _clock_minute() + 1, 1)
	TimeComponentManager.advance_minutes(maxi(batch.duration_minutes, route_arrival_minutes))
	_expect(int(city_storage.items.get("wood_log", 0)) == 3
		and int(runtime.daily.hauling.routes[HAULER_ID].cargo.quantity) == 0
		and WorkShopStorage.items.get("sun_dried_mudbrick", 0) == 20,
		"Advancing naturally delivers the cargo once and completes the drying batch.")
	var production_citizen: CitizenData = CitizenManager.get_citizen(PRODUCTION_ID)
	var laborer: WorkerData = WorkerDatabase.get_worker_data(LABORER_ID)
	production_citizen.satisfaction = 0.2
	laborer.wage_shekel_per_day = 88
	player.focus = 0.1
	_expect(store.load_checkpoint(), "Manual Load restores the earlier economy checkpoint: " + store.last_error)
	var after: Dictionary = store.snapshot.capture(content)
	_expect(_same_snapshot(before, after), "All checkpoint owners round-trip without offline time or repeated delivery.")
	_assert_restored_checkpoint()

	# Continue the restored trip and batch to their real completion boundaries.
	station = ProcessManager.stations["drying_yard"] as StationState
	batch = station.slots[0] as ProcessBatch
	_expect(batch != null and batch.status == ProcessBatch.BatchStatus.RUNNING,
		"Load reconstructs the ProcessBatch Resource inside StationState.slots.")
	route = runtime.daily.hauling.routes.get(HAULER_ID, {})
	var remaining_batch_minutes: int = batch.duration_minutes - batch.progress_minutes
	var remaining_route_minutes: int = maxi(int(route.get("arrival", _clock_minute())) - _clock_minute() + 1, 1)
	TimeComponentManager.advance_minutes(maxi(remaining_batch_minutes, remaining_route_minutes))
	_expect(station.slots[0] == null and int(WorkShopStorage.items.get("sun_dried_mudbrick", 0)) == 20,
		"The resumed drying batch produces its twenty items exactly once.")
	_expect(WorkShopStorage.output_lots.size() == 1
		and WorkShopStorage.unpaid_claims_ledger.size() == 1
		and WorkShopStorage.output_lots[0].items.get("sun_dried_mudbrick", 0) == 20
		and WorkShopStorage.output_lots[0].fee_ids.size() == 1,
		"The resumed output owns exactly one lot linked to its single unpaid fee.")
	_expect(int(city_storage.items.get("wood_log", 0)) == 3
		and runtime.daily.hauling.delivered_on_day(HAULER_ID, TimeComponentManager.current_day) == 3
		and _wood_total() == 72,
		"The restored cargo reaches City Storage once while the site remains conserved.")

	# Save a completed output plus pending ground yield. Let the active worker
	# produce one more log, reload, and continue to prove neither ledger duplicates.
	var ground_deadline: int = _clock_minute() + 240
	while runtime._daily_output_count(WOOD_SITE) == 0 and _clock_minute() < ground_deadline:
		TimeComponentManager.advance_minutes(1)
	_expect(runtime._daily_output_count(WOOD_SITE) == 1,
		"The assigned laborer leaves one real pending ground output after the checkpointed delivery.")
	var completed_snapshot: Dictionary = store.snapshot.capture(content)
	_expect(store.save_checkpoint(), "Completed workshop output and pending ground yield save: " + store.last_error)
	TimeComponentManager.advance_minutes(20)
	_expect(runtime._daily_output_count(WOOD_SITE) == 2, "Natural work adds one new ground output after the completed checkpoint.")
	_expect(store.load_checkpoint(), "Completed output and ground yield reload: " + store.last_error)
	_expect(_same_snapshot(store.snapshot.capture(content), completed_snapshot),
		"Reload restores the one saved ground output and completed fee/output ledger exactly.")
	TimeComponentManager.advance_minutes(20)
	_expect(runtime._daily_output_count(WOOD_SITE) == 2 and _wood_total() == 72,
		"Continuing after Load adds one ground output without losing or duplicating stock.")
	_expect(WorkShopStorage.output_lots.size() == 1
		and WorkShopStorage.unpaid_claims_ledger.size() == 1
		and WorkShopStorage.items.get("sun_dried_mudbrick", 0) == 20,
		"Repeated time after Load does not create a second workshop output or fee.")
	_test_work_order()
	await _finish()

func _reset_singletons_before_load() -> void:
	CitizenManager.citizens_by_id.clear()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	Inventory.items.clear()
	WorkShopStorage.items.clear()
	WorkShopStorage.max_load = 1000.0
	WorkShopStorage.claimable_outputs.clear()
	WorkShopStorage.unpaid_claims_ledger.clear()
	WorkShopStorage.output_lots.clear()
	WorkShopStorage._next_fee_sequence = 1
	WorkShopStorage._next_output_lot_sequence = 1
	WorkManager.active_orders.clear()
	WorkManager.source_item_store_by_order_id.clear()
	WorkManager.output_item_store_by_order_id.clear()
	WorkManager.service_fee_by_order.clear()
	WorkManager.service_fee_currency_by_order.clear()
	ProcessManager._auto_pull_batch_size.clear()
	WorkshopFacilityManager.reset_facilities()
	CityStockManager.food_supply = 0
	CityStockManager.clothing_supply = 0
	CityStockManager.treasury_shekel = 0
	CityStockManager.shelter_capacity = 0
	CitizenNeedsManager.clothing_allocations.clear()
	CitizenNeedsManager.last_needs_results.clear()
	CitizenNeedsManager.last_processed_day = -1
	CitizenNeedsManager.last_food_processed_day = -1
	CitizenNeedsManager.last_clothing_processed_day = -1
	CitizenNeedsManager.last_food_fulfilled_count = 0
	CitizenNeedsManager.last_food_unfulfilled_count = 0
	CitizenNeedsManager.last_clothing_fulfilled_count = 0
	CitizenNeedsManager.last_clothing_unfulfilled_count = 0
	CitizenNeedsManager.last_shelter_capacity_fulfilled_count = 0
	CitizenNeedsManager.last_shelter_capacity_unfulfilled_count = 0
	var existing_storage: Node = WorkStateRuntime.get_node_or_null("CityToolStorage")
	if existing_storage != null:
		existing_storage.items.clear()
		existing_storage.food_portions.clear()
		existing_storage.units.clear()

func _prepare_city_state() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.current_hour = 6
	TimeComponentManager.current_minute = 0
	TimeComponentManager.current_weather = "clear"
	TimeComponentManager._timer = 0.0
	TimeComponentManager.emit_time_signal()
	runtime.daily.last_tick = _clock_minute()
	runtime.daily.last_stock_day = TimeComponentManager.current_day
	_expect(runtime.city_tools == city_storage, "Main-map worksites use the shared City Tool Storage owner.")
	_expect(city_storage.units.has(CART_UNIT_ID), "Initial city supplies include the real Worksite Cart.")
	_expect(city_storage.add_tool_unit(GLOVE_UNIT_ID, "basic_glove", "Basic Glove"),
		"A valid city glove is added through City Tool Storage.")
	Inventory.add_item("barley_bread", 12)
	Inventory.add_item("simple_clothes", 3)
	_expect(Inventory.has_item("barley_bread", 12) and Inventory.has_item("simple_clothes", 3),
		"Fixture supplies use registered food and clothing items.")
	var deposit: Dictionary = city_storage.deposit_items_from_inventory({
		"barley_bread": 12,
		"simple_clothes": 3
	})
	_expect(bool(deposit.get("ok", false)), "Food and clothing enter City Storage through its transaction API.")
	CityStockManager.add_food_supply(7)
	CityStockManager.add_clothing_supply(4)
	CityStockManager.add_shekel(19)
	CityStockManager.add_shelter_capacity(3)

func _hire_and_assign_team() -> bool:
	var laborer: WorkerData = WorkerDatabase.hire_applicant(LABORER_ID, 4)
	var hauler: WorkerData = WorkerDatabase.hire_applicant(HAULER_ID, 5)
	var applicant := CitizenData.new()
	applicant.citizen_id = PRODUCTION_ID
	applicant.display_name = "Workshop Laborer"
	applicant.population_status = CitizenData.PopulationStatus.RESIDENT
	applicant.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	applicant.satisfaction = 0.5
	applicant.reliability = 0.99
	applicant.visual_profile = VisualProfile.new()
	CitizenManager.add_citizen(applicant)
	var registered: bool = CitizenManager.register_applicant(PRODUCTION_ID, WorkerData.Profession.LABORER)
	var producer: WorkerData = WorkerDatabase.hire_applicant(PRODUCTION_ID, 6)
	_expect(laborer != null and hauler != null and producer != null and registered,
		"Three valid applicants become hired workers through the employment API.")
	if laborer == null or hauler == null or producer == null or not registered:
		return false
	for id: String in [LABORER_ID, HAULER_ID, PRODUCTION_ID]:
		var citizen: CitizenData = CitizenManager.get_citizen(id)
		citizen.satisfaction = 0.5
		citizen.reliability = 0.99
	_expect(city_storage.allocate(CART_UNIT_ID, HAULER_ID), "The real city Cart is allocated to the hired Hauler.")
	_expect(city_storage.allocate(GLOVE_UNIT_ID, LABORER_ID), "The city glove is allocated to the hired resource Laborer.")
	_expect(runtime.daily.toggle(WOOD_SITE, LABORER_ID), "The hired Laborer joins the Wood Site assignment.")
	_expect(runtime.daily.select_hauler(WOOD_SITE, HAULER_ID,
		runtime.get_path_to(wood_storage), wood_storage.display_name, 3),
		"The hired Hauler joins the same site with a real storage destination and target.")
	var marker: Node = runtime.get_node("WorksiteMarkers/WoodSite")
	var started: bool = runtime.daily.start(WOOD_SITE, runtime._drop_daily_output.bind(marker))
	_expect(started, "The valid Worker and Hauler team starts its actual daily worksite job.")
	return started

func _settle_needs() -> void:
	CitizenNeedsManager.process_daily_needs()
	# The next day is reached by real minute signals before the assigned shift.

func _all_needs_fulfilled() -> bool:
	for id: String in [LABORER_ID, HAULER_ID, PRODUCTION_ID]:
		var result: Dictionary = CitizenNeedsManager.last_needs_results.get(id, {})
		if not bool(result.get("food", false)) or not bool(result.get("clothing", false)) or not bool(result.get("shelter", false)):
			return false
	return true

func _assert_restored_checkpoint() -> void:
	var route: Dictionary = runtime.daily.hauling.routes.get(HAULER_ID, {})
	_expect(runtime.daily.jobs.has(WOOD_SITE)
		and runtime.daily.jobs[WOOD_SITE].ids == [LABORER_ID, HAULER_ID],
		"Load restores both hired workers at the real Wood Site.")
	_expect(route.get("phase", "") == "outbound"
		and int(route.get("cargo", {}).get("quantity", 0)) == 3
		and int(city_storage.items.get("wood_log", 0)) == 0,
		"Load restores the same in-flight cargo without pre-crediting City Storage.")
	_expect(runtime.sites[WOOD_SITE].stock == 69 and _wood_total() == 72,
		"Resource stock and cargo restore without duplication or loss.")
	_expect(city_storage.has_equipped(HAULER_ID, "cart")
		and city_storage.has_equipped(LABORER_ID, "basic_glove"),
		"Allocated city tools survive Save and Load.")
	_expect(CitizenManager.get_citizen(LABORER_ID).employment_status == CitizenData.EmploymentStatus.HIRED
		and CitizenManager.get_citizen(HAULER_ID).employment_status == CitizenData.EmploymentStatus.HIRED,
		"Hired citizen status restores alongside each worker's active worksite assignment.")
	_expect(WorkerDatabase.get_worker_data(PRODUCTION_ID).wage_shekel_per_day == 6
		and is_equal_approx(CitizenManager.get_citizen(PRODUCTION_ID).satisfaction, 0.60),
		"Worker wages and settled satisfaction restore from the checkpoint.")
	_expect(CitizenNeedsManager.last_processed_day == TimeComponentManager.current_day
		and CitizenNeedsManager.last_clothing_processed_day == TimeComponentManager.current_day
		and CitizenNeedsManager.clothing_allocations.size() == 3
		and _all_needs_fulfilled(),
		"Settled needs results and clothing allocations restore without reprocessing the day.")
	var batch: ProcessBatch = (ProcessManager.stations["drying_yard"] as StationState).slots[0] as ProcessBatch
	_expect(batch != null and batch.quantity == 20 and batch.progress_minutes == 0
		and WorkShopStorage.unpaid_claims_ledger.size() == 1
		and WorkShopStorage.output_lots.is_empty(),
		"Load restores one pending process batch and its pre-completion fee ledger.")

func _wood_total() -> int:
	var total: int = int(city_storage.items.get("wood_log", 0))
	total += runtime._daily_output_count(WOOD_SITE)
	total += int(runtime.sites[WOOD_SITE].stock)
	if runtime.daily.hauling.routes.has(HAULER_ID):
		total += int(runtime.daily.hauling.routes[HAULER_ID].cargo.quantity)
	return total

func _clean_files() -> void:
	for suffix: String in ["", ".bak", ".tmp", ".pending"]:
		if FileAccess.file_exists(CHECKPOINT_PATH + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(CHECKPOINT_PATH + suffix))

func _finish() -> void:
	if is_instance_valid(content):
		content.queue_free()
		await get_tree().process_frame
	_clean_files()
	_restore_clock()
	print("CitySaveEconomyTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _same_snapshot(left: Variant, right: Variant) -> bool:
	# Godot's JSON reader can shift a float by one ULP, even with full_precision.
	# Keep counts, IDs, int64 RNG state and collection structure exact.
	if typeof(left) != typeof(right):
		return false
	if left is float:
		return absf(left - right) < 0.0000000001
	if left is Dictionary:
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not _same_snapshot(left[key], right[key]):
				return false
		return true
	if left is Array:
		if left.size() != right.size():
			return false
		for index: int in left.size():
			if not _same_snapshot(left[index], right[index]):
				return false
		return true
	return left == right

func _test_work_order() -> void:
	var job: JobData = preload("res://resources/job_data/mudbrick_make.tres")
	for item_id: String in job.inputs:
		WorkShopStorage.add_item(item_id, int(job.inputs[item_id]))
	var order_id: String = WorkManager.start_job(job, WorkOrder.Worker_Type.NPC,
		PRODUCTION_ID, null, WorkShopStorage, WorkShopStorage, 5)
	_expect(not order_id.is_empty(), "An actual NPC workshop order starts: " + WorkManager.last_start_job_error)
	if order_id.is_empty():
		return
	var before: Dictionary = store.snapshot.capture(content)
	var saved: bool = store.save_checkpoint()
	_expect(saved, "An active NPC order saves with its material and fee ownership: " + store.last_error)
	if not saved:
		return
	TimeComponentManager.advance_minutes(job.base_duration_minutes)
	_expect(not WorkManager.active_orders.has(order_id), "The original NPC order completes normally.")
	var loaded: bool = store.load_checkpoint()
	_expect(loaded, "The active NPC order reloads: " + store.last_error)
	if not loaded:
		return
	_expect(_same_snapshot(before, store.snapshot.capture(content)), "The order and all owners return to their saved state.")
	_expect(WorkManager.source_item_store_by_order_id.get(order_id) == WorkShopStorage
		and WorkManager.output_item_store_by_order_id.get(order_id) == WorkShopStorage,
		"Load reconnects both order stores to the existing Workshop Storage owner.")
	_expect(WorkerDatabase.get_worker_data(PRODUCTION_ID).current_order_id == order_id,
		"The NPC retains the same active order after Load.")
	var lots_before: int = WorkShopStorage.output_lots.size()
	var fees_before: int = WorkShopStorage.unpaid_claims_ledger.size()
	TimeComponentManager.advance_minutes(job.base_duration_minutes)
	_expect(not WorkManager.active_orders.has(order_id)
		and WorkShopStorage.output_lots.size() == lots_before + 1
		and WorkShopStorage.unpaid_claims_ledger.size() == fees_before + 1,
		"The restored NPC finishes once with one additional output lot and fee.")
	TimeComponentManager.advance_minutes(job.base_duration_minutes)
	_expect(WorkShopStorage.output_lots.size() == lots_before + 1
		and WorkShopStorage.unpaid_claims_ledger.size() == fees_before + 1,
		"Further time cannot finalize the restored NPC order a second time.")
