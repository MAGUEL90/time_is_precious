extends "res://scenes/test_scenes/test_scene_defense_dialogue.gd"

## Main-map economy checkpoint regression. Run in its own Godot process.
const CHECKPOINT_PATH: String = "user://city_save_economy_test/checkpoint.json"
const LABORER_ID: String = "initial_workshop_laborer"
const HAULER_ID: String = "initial_worksite_hauler"
const PRODUCTION_ID: String = "city_save_production_laborer"
const CITY_HAULER_ID: String = "initial_city_storage_hauler"
const RESIDENT_IDS: Array[String] = [LABORER_ID, HAULER_ID, CITY_HAULER_ID, PRODUCTION_ID]
const CART_UNIT_ID: String = "initial_worksite_cart"
const GLOVE_UNIT_ID: String = "city_save_laborer_glove"
const WOOD_SITE: StringName = &"WoodSite"
const PROCESS_ID: String = "drying_mudbrick"
const MIGRATION_VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const MIGRATION_FIXTURE = preload("res://scenes/test_scenes/legacy_reliability_fixture.gd")

var store: Node
var runtime: Node
var city_storage: Node
var wood_storage: Node
var initial_wood_stock: int = 0
var needs_settled_minute: int = -1

func _run() -> void:
	if not _isolated_profile_is_safe():
		_expect(false, "Economy fixture requires distinct absolute XDG directories under the sibling citysave_suite_qa directory; no checkpoint files were touched.")
		get_tree().quit(1)
		return
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	_reset_singletons_before_load()
	CitizenNeedsManager.food_coverage_until.clear()
	CitizenNeedsManager.satisfaction_last_minute.clear()
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
	_prepare_city_state(RESIDENT_IDS.size())
	initial_wood_stock = int(runtime.sites[WOOD_SITE].stock)
	_expect(runtime.sites[WOOD_SITE].finite_resource
		and initial_wood_stock == int(runtime.sites[WOOD_SITE].deposit_capacity)
		and initial_wood_stock > 3 and _wood_total() == initial_wood_stock
		and int(city_storage.items.get("wood_log", 0)) == 0
		and runtime._daily_output_count(WOOD_SITE) == 0
		and runtime.daily.hauling.routes.is_empty(),
		"The fixture starts with a full configured finite wood deposit and no existing stored, ground, or in-flight logs.")
	var food_points_before_hires: int = int(city_storage.get_food_supply_points())
	if failures > 0 or not _hire_and_assign_team():
		await _finish()
		return
	needs_settled_minute = _clock_minute()
	_settle_needs()
	_expect(CitizenNeedsManager.last_processed_day == TimeComponentManager.current_day
		and CitizenNeedsManager.last_clothing_processed_day == TimeComponentManager.current_day,
		"The fixture starts from a completed food, clothing and shelter settlement.")
	_expect(_has_exact_resident_keys(CitizenManager.citizens_by_id)
		and _has_exact_resident_keys(CitizenNeedsManager.clothing_allocations)
		and _has_exact_resident_keys(CitizenNeedsManager.last_needs_results),
		"All four residents, including the unhired city Hauler, have exactly one needs record and clothing allocation.")
	_expect(food_points_before_hires - int(city_storage.get_food_supply_points()) == RESIDENT_IDS.size()
		and CitizenNeedsManager.last_food_fulfilled_count == RESIDENT_IDS.size()
		and int(city_storage.items.get("simple_clothes", 0)) == 0
		and not WorkerDatabase.has_worker_data(CITY_HAULER_ID),
		"Four residents consume exactly four food points and four garments; linked workers are not charged again and the city Hauler remains unhired.")
	_expect(_all_needs_fulfilled() and is_equal_approx(CitizenManager.get_citizen(PRODUCTION_ID).satisfaction, 0.5),
		"Real supplies fulfill all residents' needs without an immediate Satisfaction jump at the same minute.")
	var settled_snapshot: Dictionary = store.snapshot.capture(content)
	_settle_needs()
	_expect(not settled_snapshot.is_empty() and _same_snapshot(settled_snapshot, store.snapshot.capture(content)),
		"Repeating same-day settlement neither consumes more supplies nor advances Satisfaction.")
	if failures > 0:
		await _finish()
		return

	# Hires and assignments begin during today's shift. Advance the real clock so
	# the worksite gathers natural output and the real Hauler takes it into cargo.
	var visuals: Node = runtime.get_node("WorkerVisuals")
	var deadline: int = (TimeComponentManager.current_day * 1440) + 15 * 60
	while (not runtime.daily.hauling.routes.has(HAULER_ID)
		or str(runtime.daily.hauling.routes[HAULER_ID].phase) != "outbound") \
		and _clock_minute() < deadline:
		# Output begins only after the authored walk marks physical arrival.
		for _frame: int in range(20):
			visuals._process(0.05)
		TimeComponentManager.advance_minutes(1)
	var approaching_laborer: WorkerData = WorkerDatabase.get_worker_data(LABORER_ID)
	_expect(approaching_laborer != null and not approaching_laborer.physical_approach.is_empty() and approaching_laborer.physical_approach.arrived,
		"The resource Laborer reaches the Wood Site before the cargo is gathered.")
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
		and int(runtime.sites[WOOD_SITE].stock) == initial_wood_stock - 3,
		"Gathered stock is represented by the in-flight cargo exactly once.")
	_expect(_wood_total() == initial_wood_stock, "Wood stock, ground output, storage and cargo conserve the site's measured initial stock.")
	var expected_satisfaction: float = 0.5 + float(_clock_minute() - needs_settled_minute) * 0.05 / 1440.0
	_expect(absf(CitizenManager.get_citizen(PRODUCTION_ID).satisfaction - expected_satisfaction) < 0.0000000001,
		"The fully supplied producer gains only the current gradual Satisfaction amount for actual elapsed minutes.")
	if failures > 0:
		await _finish()
		return

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
	if before.is_empty():
		await _finish()
		return
	_test_fractional_migration(before)
	_test_v10_migration(before)
	if failures > 0:
		await _finish()
		return

	# Let the real route deliver and the real process complete, then load the
	# earlier checkpoint. This tests rollback of stock, cargo, workers and outputs.
	# Restore replaces route dictionaries and ProcessBatch resources. Reacquire
	# their live owners instead of continuing through a pre-migration reference.
	route = runtime.daily.hauling.routes[HAULER_ID]
	station = ProcessManager.stations["drying_yard"] as StationState
	batch = station.slots[0] as ProcessBatch
	var gathered_before_delivery: int = _gathered_output()
	var stored_before_delivery: int = int(city_storage.items.get("wood_log", 0))
	var route_arrival_minutes: int = maxi(int(route.arrival) - _clock_minute() + 1, 1)
	var completion_minutes: int = maxi(batch.duration_minutes - batch.progress_minutes, route_arrival_minutes)
	TimeComponentManager.advance_minutes(completion_minutes)
	_assert_delivery_and_production(gathered_before_delivery, stored_before_delivery)
	_expect(station.slots[0] == null and WorkShopStorage.items.get("sun_dried_mudbrick", 0) == 20,
		"Advancing to the actual completion boundaries finishes the drying batch.")
	var continued_snapshot: Dictionary = store.snapshot.capture(content)
	var production_citizen: CitizenData = CitizenManager.get_citizen(PRODUCTION_ID)
	var laborer: WorkerData = WorkerDatabase.get_worker_data(LABORER_ID)
	production_citizen.satisfaction = 0.2
	laborer.wage_shekel_per_day = 88
	player.hunger = 0.9
	var loaded: bool = store.load_checkpoint()
	_expect(loaded, "Manual Load restores the earlier economy checkpoint: " + store.last_error)
	if not loaded:
		await _finish()
		return
	var after: Dictionary = store.snapshot.capture(content)
	_expect(_same_snapshot(before, after), "All checkpoint owners round-trip without offline time or repeated delivery.")
	_assert_restored_checkpoint(before)

	# Continue the restored trip and batch to their real completion boundaries.
	station = ProcessManager.stations["drying_yard"] as StationState
	batch = station.slots[0] as ProcessBatch
	_expect(batch != null and batch.status == ProcessBatch.BatchStatus.RUNNING,
		"Load reconstructs the ProcessBatch Resource inside StationState.slots.")
	if batch == null:
		await _finish()
		return
	route = runtime.daily.hauling.routes.get(HAULER_ID, {})
	var remaining_batch_minutes: int = batch.duration_minutes - batch.progress_minutes
	var remaining_route_minutes: int = maxi(int(route.get("arrival", _clock_minute())) - _clock_minute() + 1, 1)
	_expect(maxi(remaining_batch_minutes, remaining_route_minutes) == completion_minutes,
		"Load restores the same remaining process and transport completion interval.")
	TimeComponentManager.advance_minutes(maxi(remaining_batch_minutes, remaining_route_minutes))
	_expect(station.slots[0] == null and int(WorkShopStorage.items.get("sun_dried_mudbrick", 0)) == 20,
		"The resumed drying batch produces its twenty items exactly once.")
	_expect(WorkShopStorage.output_lots.size() == 1
		and WorkShopStorage.unpaid_claims_ledger.size() == 1
		and WorkShopStorage.output_lots[0].items.get("sun_dried_mudbrick", 0) == 20
		and WorkShopStorage.output_lots[0].fee_ids.size() == 1,
		"The resumed output owns exactly one lot linked to its single unpaid fee.")
	_assert_delivery_and_production(gathered_before_delivery, stored_before_delivery)
	_expect(_same_snapshot(continued_snapshot, store.snapshot.capture(content)),
		"Replaying the same elapsed minutes after Load reproduces every economy owner without duplicate delivery, production, or needs effects.")

	# After Continue, new worker output goes directly to the city. Save alongside
	# the completed workshop output and prove that both ledgers resume only once.
	var city_before: int = int(city_storage.items.get("wood_log", 0))
	var output_deadline: int = _clock_minute() + 240
	while int(city_storage.items.get("wood_log", 0)) == city_before and _clock_minute() < output_deadline:
		TimeComponentManager.advance_minutes(1)
	_expect(int(city_storage.items.get("wood_log", 0)) == city_before + 1
		and runtime._daily_output_count(WOOD_SITE) == 0,
		"The assigned laborer sends the next completed log directly to City Storage.")
	var completed_snapshot: Dictionary = store.snapshot.capture(content)
	_expect(store.save_checkpoint(), "Completed workshop output and City Storage stock save: " + store.last_error)
	TimeComponentManager.advance_minutes(20)
	_expect(int(city_storage.items.get("wood_log", 0)) == city_before + 2, "Natural work adds one city-owned log after the completed checkpoint.")
	_expect(store.load_checkpoint(), "Completed output and City Storage stock reload: " + store.last_error)
	_expect(_same_snapshot(store.snapshot.capture(content), completed_snapshot),
		"Reload restores the saved city stock and completed fee/output ledger exactly.")
	TimeComponentManager.advance_minutes(20)
	_expect(int(city_storage.items.get("wood_log", 0)) == city_before + 2
		and runtime._daily_output_count(WOOD_SITE) == 0 and _wood_total() == initial_wood_stock,
		"Continuing after Load adds one city-owned log without losing or duplicating stock.")
	_expect(WorkShopStorage.output_lots.size() == 1
		and WorkShopStorage.unpaid_claims_ledger.size() == 1
		and WorkShopStorage.items.get("sun_dried_mudbrick", 0) == 20,
		"Repeated time after Load does not create a second workshop output or fee.")
	_test_work_order()
	await _finish()

func _test_fractional_migration(original: Dictionary) -> void:
	# Force a nearly complete item for a physically arrived, paid Laborer.
	# Both checkpoint versions must resume the same partial work at low Satisfaction.
	var session = runtime.sites[WOOD_SITE]
	var threshold: float = float(session.minutes_per_unit)
	CitizenManager.get_citizen(LABORER_ID).satisfaction = 0.2
	runtime.daily.jobs[WOOD_SITE].progress[LABORER_ID] = threshold - 0.65
	_expect(store.save_checkpoint(), "A current city checkpoint saves fractional gathering work.")
	var current: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	var values = MIGRATION_VALUES.new()
	var current_raw: Dictionary = values.decode(current.state)
	var legacy: Dictionary = current.duplicate(true)
	legacy.schema_version = 9
	legacy.state = MIGRATION_FIXTURE.encode_city(values, current_raw)
	for document: Dictionary in [current, legacy]:
		var bytes: String = JSON.stringify(document, "", true, true)
		var file := FileAccess.open(CHECKPOINT_PATH, FileAccess.WRITE)
		file.store_string(bytes)
		file.close()
		_expect(store.load_checkpoint(), "The fractional city checkpoint loads: v%d" % document.schema_version)
		_expect(FileAccess.get_file_as_string(CHECKPOINT_PATH) == bytes, "Loading leaves the checkpoint bytes intact: v%d" % document.schema_version)
		var job: Dictionary = runtime.daily.jobs[WOOD_SITE]
		_expect(is_equal_approx(float(job.progress[LABORER_ID]), threshold - 0.65), "Fractional progress survives disk: v%d" % document.schema_version)
		if document.schema_version == 9:
			var record: Dictionary = CitizenNeedsManager.last_needs_results[LABORER_ID]
			_expect(not record.has("reliability") and not record.has("reliability_delta"), "The restored v9 same-day needs record is sanitized.")
			_expect(store.save_checkpoint(), "The explicit next save upgrades v9 to the current schema.")
			_expect(FileAccess.get_file_as_string(CHECKPOINT_PATH + ".bak") == bytes, "The v9 bytes remain in the normal backup.")
			_expect(JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH)).schema_version == store.snapshot.VERSION, "The upgraded city checkpoint uses the current schema.")
		var stock_before: int = int(session.stock)
		var output_before: int = int(job.stats[LABORER_ID].output)
		TimeComponentManager.advance_minutes(1)
		_expect(int(session.stock) == stock_before - 1 and int(job.stats[LABORER_ID].output) == output_before + 1 and is_equal_approx(float(job.progress[LABORER_ID]), 0.2), "Continued low-Satisfaction gathering completes exactly one item: v%d" % document.schema_version)
	var restore_file := FileAccess.open(CHECKPOINT_PATH, FileAccess.WRITE)
	restore_file.store_string(JSON.stringify(original, "", true, true))
	restore_file.close()
	_expect(store.load_checkpoint() and _same_snapshot(original, store.snapshot.capture(content)), "The economy fixture restores its original checkpoint after migration probes.")

func _test_v10_migration(original: Dictionary) -> void:
	var plots: Dictionary = store.snapshot.plots(content)
	var plot_view: Node = content.get_node("YSortWorld/WorkshopPlot2")
	var plot: Node = plot_view.construction
	var plot_id: String = str(plot.name)
	_expect(plots.get(plot_id) == plot, "The v10 fixture has the authored workshop construction plot.")
	if plots.get(plot_id) != plot:
		return
	# Start an actual paid construction job with the otherwise idle third hire.
	plot.phase = "empty"
	plot.clearing_remaining = 0
	for item_id: String in plot.REQUIREMENTS:
		Inventory.add_item(item_id, int(plot.REQUIREMENTS[item_id]))
	var worker: WorkerData = WorkerDatabase.get_worker_data(PRODUCTION_ID)
	var citizen: CitizenData = CitizenManager.get_citizen(PRODUCTION_ID)
	worker.profession_xp = 17
	citizen.experience = 12.5
	var ids: Array[String] = [PRODUCTION_ID]
	var started: Dictionary = plot.start_build(ids)
	_expect(bool(started.get("success", false)), "A hired worker starts the construction migration fixture.")
	if not bool(started.get("success", false)):
		_restore_migration_original(original)
		return
	worker.physical_approach.position = worker.physical_approach.target
	_expect(worker.mark_physical_arrival(plot.order_id + ":building"), "The construction worker reaches the authored entry.")
	TimeComponentManager.advance_minutes(1)
	var values = MIGRATION_VALUES.new()
	var current: Dictionary = store.snapshot.capture(content)
	var raw: Dictionary = values.decode(current.state)
	var old_plot: Dictionary = raw.plots[plot_id].duplicate(true)
	var old_worker: WorkerData = raw.workers.workers_by_id[PRODUCTION_ID]
	var old_citizen: CitizenData = raw.citizens.citizens_by_id[PRODUCTION_ID]
	var old_route: Dictionary = raw.worksites.routes[HAULER_ID].duplicate(true)
	var legacy: Dictionary = current.duplicate(true)
	legacy.schema_version = 10
	legacy.state = MIGRATION_FIXTURE.encode_v10(values, raw)
	var source_codec = MIGRATION_VALUES.new()
	source_codec.allow_legacy_resignation_field = true
	var source_raw: Dictionary = source_codec.decode(legacy.state)
	var objects: Array = MIGRATION_FIXTURE.city_objects(legacy.state, "WorkerData")
	var source_shape_valid: bool = not objects.is_empty()
	for object: Dictionary in objects:
		source_shape_valid = source_shape_valid and not object.fields.has("resignation_pending")
	for saved_plot: Dictionary in source_raw.plots.values():
		source_shape_valid = source_shape_valid and not saved_plot.has("worker_capacity") and not saved_plot.has("work_total_units")
	for route: Dictionary in source_raw.worksites.routes.values():
		source_shape_valid = source_shape_valid and not route.has("resigning") and not route.has("legacy_final")
	for pile: Dictionary in source_raw.worksites.ground:
		source_shape_valid = source_shape_valid and not pile.has("legacy_stockpile")
	_expect(source_shape_valid and source_raw.worksites.schema_version == 1 and not source_raw.worksites.has("pending_output")
		and not source_raw.worksites.has("pending_progress"),
		"The v10 source genuinely omits all v11 and nested worksite v2 fields.")
	var legacy_bytes: PackedByteArray = (JSON.stringify(legacy, "\t", true, true) + "\n").to_utf8_buffer()
	_write_checkpoint_bytes(legacy_bytes)
	var files_before: Dictionary = _migration_files()
	_expect(store.load_checkpoint() and store.load_checkpoint(), "The v10 checkpoint loads repeatedly through the real disk boundary: " + store.last_error)
	_expect(_migration_files() == files_before and FileAccess.get_file_as_bytes(CHECKPOINT_PATH) == legacy_bytes,
		"Continue preserves the exact source bytes and all recovery files.")
	var restored_worker: WorkerData = WorkerDatabase.get_worker_data(PRODUCTION_ID)
	var restored_citizen: CitizenData = CitizenManager.get_citizen(PRODUCTION_ID)
	var same_contract: bool = true
	var all_pending_default: bool = true
	for group: Dictionary in [WorkerDatabase.workers_by_id, WorkerDatabase.dismissed_workers]:
		for restored: WorkerData in group.values():
			all_pending_default = all_pending_default and not restored.resignation_pending
	for field: String in MIGRATION_VALUES.PAYROLL_FIELDS + MIGRATION_VALUES.CONTRACT_FIELDS:
		same_contract = same_contract and restored_worker.get(field) == old_worker.get(field)
	_expect(restored_worker.worker_id == old_worker.worker_id and restored_worker.display_name == old_worker.display_name
		and restored_worker.profession_xp == 17 and all_pending_default and same_contract
		and restored_citizen.citizen_id == old_citizen.citizen_id and restored_citizen.display_name == old_citizen.display_name
		and is_equal_approx(restored_citizen.experience, 12.5),
		"Continue retains worker and citizen identity, XP, every contract field, and defaults pending resignation to false.")
	var restored_plot: Dictionary = MIGRATION_VALUES.new().decode(store.snapshot.capture(content).state).plots[plot_id]
	var old_fields_preserved: bool = true
	for field: String in old_plot:
		if field not in ["worker_capacity", "work_total_units"]:
			old_fields_preserved = old_fields_preserved and _same_snapshot(restored_plot[field], old_plot[field])
	_expect(old_fields_preserved and restored_plot.worker_capacity == old_plot.worker_ids.size()
		and restored_plot.work_total_units == (old_plot.completes_at - old_plot.started_at) * old_plot.worker_ids.size(),
		"Continue retains every old building field and reconstructs the original team capacity and total work.")
	var restored_route: Dictionary = store.snapshot._sites.capture(runtime).routes[HAULER_ID]
	old_route["resigning"] = false
	old_route["removing"] = true
	old_route["legacy_final"] = true
	_expect(_same_snapshot(restored_route, old_route) and not runtime.daily.hauling.routes[HAULER_ID].resigning
		and runtime.daily.pending_output.is_empty() and runtime.daily.pending_progress.is_empty(),
		"The old worksite retains its route and cargo for one final delivery, with no pending output or progress.")
	var migrated_state: Dictionary = store.snapshot.capture(content)
	_expect(store.save_checkpoint(), "A later explicit save upgrades the v10 checkpoint: " + store.last_error)
	var upgraded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	_expect(upgraded.get("schema_version") == store.snapshot.VERSION and FileAccess.get_file_as_bytes(CHECKPOINT_PATH + ".bak") == legacy_bytes,
		"The upgraded checkpoint keeps the exact v10 source bytes in its normal backup.")
	var upgraded_files: Dictionary = _migration_files()
	_expect(store.load_checkpoint() and store.load_checkpoint() and _same_snapshot(migrated_state, store.snapshot.capture(content))
		and _migration_files() == upgraded_files, "The upgraded checkpoint loads repeatedly without changing state or files: " + store.last_error)
	_test_shift_sentinel_boundary(current)
	var remaining_before: int = plot.completes_at - plot._latest_time
	TimeComponentManager.advance_minutes(1)
	_expect(plot.completes_at - plot._latest_time == remaining_before - 1,
		"The restored paid construction worker continues the saved job.")
	_test_malformed_v11(current, raw, plot_id)
	_restore_migration_original(original)
	_test_v10_clearing(original, plot_id)

func _test_shift_sentinel_boundary(current: Dictionary) -> void:
	var values = MIGRATION_VALUES.new()
	var boundary_raw: Dictionary = values.decode(current.state)
	var departing: WorkerData = boundary_raw.workers.workers_by_id[PRODUCTION_ID]
	departing.physical_approach.arrived = false
	departing.physical_approach.arrival_minute = WorkerData.PLOT_DEPARTURE_PENDING
	departing.current_work_status = WorkerData.WorkStatus.TRAVELLING
	var v11: Dictionary = current.duplicate(true)
	v11.schema_version = 11
	v11.state = MIGRATION_FIXTURE.encode_v11(values, boundary_raw)
	var sentinel: Dictionary = store.snapshot.capture(content)
	_expect(store.snapshot.prepare(v11, content), "The shift-departure sentinel validates in v11: " + store.snapshot.error)
	var v10: Dictionary = current.duplicate(true)
	v10.schema_version = 10
	v10.state = MIGRATION_FIXTURE.encode_v10(values, boundary_raw)
	var bytes: PackedByteArray = (JSON.stringify(v10, "\t", true, true) + "\n").to_utf8_buffer()
	_write_checkpoint_bytes(bytes)
	var files_before: Dictionary = _migration_files()
	_expect(not store.load_checkpoint() and not store.save_checkpoint(), "The v11 shift-departure sentinel is rejected in v10.")
	_expect(_migration_files() == files_before and FileAccess.get_file_as_bytes(CHECKPOINT_PATH) == bytes
		and _same_snapshot(sentinel, store.snapshot.capture(content)),
		"A rejected legacy sentinel preserves every file and the live world.")

func _test_v10_clearing(original: Dictionary, plot_id: String) -> void:
	var plot: Node = store.snapshot.plots(content)[plot_id]
	var ids: Array[String] = [PRODUCTION_ID]
	var started: Dictionary = plot.start_clearing(ids, false)
	_expect(bool(started.get("success", false)), "A hired worker starts the v10 clearing fixture.")
	if bool(started.get("success", false)):
		var values = MIGRATION_VALUES.new()
		var current: Dictionary = store.snapshot.capture(content)
		var raw: Dictionary = values.decode(current.state)
		var old_plot: Dictionary = raw.plots[plot_id].duplicate(true)
		var v10: Dictionary = current.duplicate(true)
		v10.schema_version = 10
		v10.state = MIGRATION_FIXTURE.encode_v10(values, raw)
		var bytes: PackedByteArray = (JSON.stringify(v10, "\t", true, true) + "\n").to_utf8_buffer()
		_write_checkpoint_bytes(bytes)
		var files_before: Dictionary = _migration_files()
		_expect(store.load_checkpoint(), "A v10 worker-clearing checkpoint loads: " + store.last_error)
		var migrated: Dictionary = values.decode(store.snapshot.capture(content).state).plots[plot_id]
		var old_fields_preserved: bool = true
		for field: String in old_plot:
			if field not in ["worker_capacity", "work_total_units"]:
				old_fields_preserved = old_fields_preserved and _same_snapshot(migrated[field], old_plot[field])
		_expect(old_fields_preserved and migrated.worker_capacity == 1 and migrated.work_total_units == plot.CLEARING_MINUTES
			and _migration_files() == files_before and FileAccess.get_file_as_bytes(CHECKPOINT_PATH) == bytes,
			"The clearing migration retains its original fields, restores defaults, and leaves all files untouched.")
	_restore_migration_original(original)

func _test_malformed_v11(current: Dictionary, raw: Dictionary, plot_id: String) -> void:
	var sentinel: Dictionary = store.snapshot.capture(content)
	var v11: Dictionary = current.duplicate(true)
	v11.schema_version = 11
	v11.state = MIGRATION_FIXTURE.encode_v11(MIGRATION_VALUES.new(), raw)
	var baseline_valid: bool = store.snapshot.prepare(v11, content)
	_expect(baseline_valid, "The unmodified v11 source validates before corruption probes: " + store.snapshot.error)
	if not baseline_valid:
		return
	for invalid_case: String in ["worker_pending_missing", "worker_pending_type", "plot_capacity_missing", "plot_capacity_negative", "plot_work_missing", "plot_work_zero", "pending_output_missing", "pending_output_invalid", "pending_progress_missing", "pending_progress_invalid", "route_resigning_missing", "route_resigning_type", "route_resigning_invalid", "worksite_cursor_ahead", "worksite_cursor_behind", "work_cursor_ahead", "work_cursor_behind", "process_cursor_ahead", "process_cursor_behind", "plot_cursor_ahead", "plot_cursor_behind"]:
		var bad_raw: Dictionary = raw.duplicate(true)
		var clock_minute: int = raw.clock.current_day * 1440 + raw.clock.current_hour * 60 + raw.clock.current_minute
		match invalid_case:
			"plot_capacity_missing": bad_raw.plots[plot_id].erase("worker_capacity")
			"plot_capacity_negative": bad_raw.plots[plot_id].worker_capacity = -1
			"plot_work_missing": bad_raw.plots[plot_id].erase("work_total_units")
			"plot_work_zero": bad_raw.plots[plot_id].work_total_units = 0
			"pending_output_missing": bad_raw.worksites.erase("pending_output")
			"pending_output_invalid": bad_raw.worksites.pending_output = {"WoodSite": 0}
			"pending_progress_missing": bad_raw.worksites.erase("pending_progress")
			"pending_progress_invalid": bad_raw.worksites.pending_progress = {"WoodSite": [0.0]}
			"route_resigning_missing": bad_raw.worksites.routes[HAULER_ID].erase("resigning")
			"route_resigning_type": bad_raw.worksites.routes[HAULER_ID].resigning = "false"
			"route_resigning_invalid": bad_raw.worksites.routes[HAULER_ID].resigning = true
			"worksite_cursor_ahead": bad_raw.worksites.ledger.last_tick = clock_minute + 1
			"worksite_cursor_behind": bad_raw.worksites.ledger.last_tick = clock_minute - 1
			"work_cursor_ahead": bad_raw.work._last_total_minutes = clock_minute + 1
			"work_cursor_behind": bad_raw.work._last_total_minutes = clock_minute - 1
			"process_cursor_ahead": bad_raw.process._last_total_minutes = clock_minute + 1
			"process_cursor_behind": bad_raw.process._last_total_minutes = clock_minute - 1
			"plot_cursor_ahead": bad_raw.plots[plot_id]._latest_time = clock_minute + 1
			"plot_cursor_behind": bad_raw.plots[plot_id]._latest_time = clock_minute - 1
		var bad: Dictionary = v11.duplicate(true)
		bad.state = MIGRATION_FIXTURE.encode_v11(MIGRATION_VALUES.new(), bad_raw)
		if invalid_case.begins_with("worker_pending"):
			for object: Dictionary in MIGRATION_FIXTURE.city_objects(bad.state, "WorkerData"):
				if object.fields.worker_id == PRODUCTION_ID:
					if invalid_case.ends_with("missing"):
						object.fields.erase("resignation_pending")
					else:
						object.fields.resignation_pending = "false"
					break
		var bad_bytes: PackedByteArray = (JSON.stringify(bad, "\t", true, true) + "\n").to_utf8_buffer()
		_write_checkpoint_bytes(bad_bytes)
		var files_before: Dictionary = _migration_files()
		_expect(not store.load_checkpoint() and not store.save_checkpoint(), "Malformed v11 data blocks Load and Save: " + invalid_case)
		_expect(_migration_files() == files_before and FileAccess.get_file_as_bytes(CHECKPOINT_PATH) == bad_bytes
			and _same_snapshot(sentinel, store.snapshot.capture(content)),
			"Rejected v11 data preserves every save file and the live world: " + invalid_case)

func _write_checkpoint_bytes(bytes: PackedByteArray) -> void:
	var file := FileAccess.open(CHECKPOINT_PATH, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

func _migration_files() -> Dictionary:
	var result: Dictionary = {}
	for suffix: String in ["", ".bak", ".tmp", ".pending"]:
		var path: String = CHECKPOINT_PATH + suffix
		result[suffix] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	return result

func _restore_migration_original(original: Dictionary) -> void:
	_write_checkpoint_bytes(JSON.stringify(original, "", true, true).to_utf8_buffer())
	_expect(store.load_checkpoint() and _same_snapshot(original, store.snapshot.capture(content)),
		"The economy fixture restores the original checkpoint after the v10 probes.")

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

func _prepare_city_state(needs_recipient_count: int = 3) -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.current_hour = 8
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
	Inventory.add_item("simple_clothes", needs_recipient_count)
	_expect(Inventory.has_item("barley_bread", 12) and Inventory.has_item("simple_clothes", needs_recipient_count),
		"Fixture supplies use registered food and clothing items.")
	# The three explicit three-day hires each cost one shekel from the Player wallet.
	Inventory.add_item("shekel", 3)
	_expect(Inventory.has_item("shekel", 3), "The fixture funds all three hires from the Player wallet.")
	var deposit: Dictionary = city_storage.deposit_items_from_inventory({
		"barley_bread": 12,
		"simple_clothes": needs_recipient_count
	})
	_expect(bool(deposit.get("ok", false)), "Food and clothing enter City Storage through its transaction API.")
	CityStockManager.add_food_supply(7)
	CityStockManager.add_clothing_supply(4)
	CityStockManager.add_shekel(19)
	# The economy scenario supplies its explicit four-person roster. Keep the
	# existing three-person default for inherited shortage/resignation fixtures.
	CityStockManager.add_shelter_capacity(needs_recipient_count)

func _hire_and_assign_team() -> bool:
	# This fixture explicitly constructs a pre-removal delivery scenario.
	# Normal gameplay keeps new worksite Hauler assignments disabled.
	runtime.daily.allow_haulers = true
	var laborer: WorkerData = WorkerDatabase.hire_applicant(LABORER_ID, 4)
	var hauler: WorkerData = WorkerDatabase.hire_applicant(HAULER_ID, 5)
	# Reconstruct a paid legacy Hauler for this pre-removal delivery fixture;
	# ordinary recruitment no longer creates Haulers.
	if hauler != null:
		hauler.profession = WorkerData.Profession.HAULER
		CitizenManager.get_citizen(HAULER_ID).profession = WorkerData.Profession.HAULER
	var applicant := CitizenData.new()
	applicant.citizen_id = PRODUCTION_ID
	applicant.display_name = "Workshop Laborer"
	applicant.population_status = CitizenData.PopulationStatus.RESIDENT
	applicant.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	applicant.satisfaction = 0.5
	applicant.visual_profile = VisualProfile.new()
	CitizenManager.add_citizen(applicant)
	var registered: bool = CitizenManager.register_applicant(PRODUCTION_ID, WorkerData.Profession.LABORER)
	var producer: WorkerData = WorkerDatabase.hire_applicant(PRODUCTION_ID, 6)
	_expect(laborer != null and hauler != null and producer != null and registered,
		"Three paid hires are made before reconstructing the legacy Hauler.")
	if laborer == null or hauler == null or producer == null or not registered:
		return false
	_expect(not Inventory.has_item("shekel", 1) and CityStockManager.treasury_shekel == 19,
		"The three upfront contract charges use the Player wallet and leave City Treasury unchanged.")
	for id: String in [LABORER_ID, HAULER_ID, PRODUCTION_ID]:
		var citizen: CitizenData = CitizenManager.get_citizen(id)
		citizen.satisfaction = 0.5
	_expect(city_storage.allocate(CART_UNIT_ID, HAULER_ID), "The real city Cart is allocated to the hired Hauler.")
	_expect(city_storage.allocate(GLOVE_UNIT_ID, LABORER_ID), "The city glove is allocated to the hired resource Laborer.")
	_expect(runtime.daily.toggle(WOOD_SITE, LABORER_ID), "The hired Laborer joins the Wood Site assignment.")
	_expect(runtime.daily.select_hauler(WOOD_SITE, HAULER_ID,
		runtime.get_path_to(wood_storage), wood_storage.display_name, 3),
		"The hired Hauler joins the same site with a real storage destination and target.")
	var marker: Node = runtime.get_node("WorksiteMarkers/WoodSite")
	var started: bool = runtime.daily.start(WOOD_SITE, runtime._drop_daily_output.bind(marker))
	_expect(started, "The valid Worker and Hauler team starts its actual daily worksite job.")
	_expect(started and runtime.daily.jobs.has(WOOD_SITE)
		and int(runtime.daily.jobs[WOOD_SITE].starts.get(LABORER_ID, -1)) == _clock_minute()
		and int(runtime.daily.jobs[WOOD_SITE].starts.get(HAULER_ID, -1)) == _clock_minute(),
		"Hiring at 08:00 permits both assigned workers to start on the same day.")
	return started

func _settle_needs() -> void:
	CitizenNeedsManager.process_daily_needs()
	# The fixture settles needs explicitly before advancing today's active shift.

func _all_needs_fulfilled() -> bool:
	for id: String in RESIDENT_IDS:
		var result: Dictionary = CitizenNeedsManager.last_needs_results.get(id, {})
		if not bool(result.get("food", false)) or not bool(result.get("clothing", false)) or not bool(result.get("shelter", false)):
			return false
	return true

func _has_exact_resident_keys(records: Dictionary) -> bool:
	if records.size() != RESIDENT_IDS.size():
		return false
	for id: String in RESIDENT_IDS:
		if not records.has(id):
			return false
	return true

func _assert_restored_checkpoint(checkpoint: Dictionary) -> void:
	var saved_raw: Dictionary = MIGRATION_VALUES.new().decode(checkpoint.state)
	var route: Dictionary = runtime.daily.hauling.routes.get(HAULER_ID, {})
	_expect(runtime.daily.jobs.has(WOOD_SITE)
		and runtime.daily.jobs[WOOD_SITE].ids == [LABORER_ID, HAULER_ID],
		"Load restores both hired workers at the real Wood Site.")
	_expect(route.get("phase", "") == "outbound"
		and int(route.get("cargo", {}).get("quantity", 0)) == 3
		and int(city_storage.items.get("wood_log", 0)) == 0,
		"Load restores the same in-flight cargo without pre-crediting City Storage.")
	_expect(runtime.sites[WOOD_SITE].stock == initial_wood_stock - 3 and _wood_total() == initial_wood_stock,
		"Resource stock and cargo restore without duplication or loss.")
	_expect(city_storage.has_equipped(HAULER_ID, "cart")
		and city_storage.has_equipped(LABORER_ID, "basic_glove"),
		"Allocated city tools survive Save and Load.")
	_expect(CitizenManager.get_citizen(LABORER_ID).employment_status == CitizenData.EmploymentStatus.HIRED
		and CitizenManager.get_citizen(HAULER_ID).employment_status == CitizenData.EmploymentStatus.HIRED,
		"Hired citizen status restores alongside each worker's active worksite assignment.")
	_expect(WorkerDatabase.get_worker_data(PRODUCTION_ID).wage_shekel_per_day == 6
		and absf(CitizenManager.get_citizen(PRODUCTION_ID).satisfaction
			- saved_raw.citizens.citizens_by_id[PRODUCTION_ID].satisfaction) < 0.0000000001,
		"Worker wages and the exact saved gradual Satisfaction restore from the checkpoint.")
	_expect(CitizenNeedsManager.last_processed_day == TimeComponentManager.current_day
		and CitizenNeedsManager.last_clothing_processed_day == TimeComponentManager.current_day
		and _has_exact_resident_keys(CitizenNeedsManager.clothing_allocations)
		and _has_exact_resident_keys(CitizenNeedsManager.last_needs_results)
		and _all_needs_fulfilled()
		and _same_snapshot(CitizenNeedsManager.clothing_allocations, saved_raw.needs.clothing_allocations)
		and _same_snapshot(CitizenNeedsManager.last_needs_results, saved_raw.needs.last_needs_results)
		and _same_snapshot(CitizenNeedsManager.food_coverage_until, saved_raw.needs.food_coverage_until)
		and _same_snapshot(CitizenNeedsManager.satisfaction_last_minute, saved_raw.needs.satisfaction_last_minute),
		"All four residents' needs results, clothing allocations and timing ledgers restore exactly without reprocessing the day.")
	var batch: ProcessBatch = (ProcessManager.stations["drying_yard"] as StationState).slots[0] as ProcessBatch
	_expect(batch != null and batch.quantity == 20 and batch.progress_minutes == 0
		and WorkShopStorage.unpaid_claims_ledger.size() == 1
		and WorkShopStorage.output_lots.is_empty(),
		"Load restores one pending process batch and its pre-completion fee ledger.")

func _gathered_output() -> int:
	return int(runtime.daily.jobs[WOOD_SITE].stats[LABORER_ID].output)

func _assert_delivery_and_production(gathered_before: int, stored_before: int) -> void:
	var new_output: int = _gathered_output() - gathered_before
	# Continue retires new worksite hauling. The retained shipment delivers
	# once, while the Laborer's subsequent output goes directly to City Storage.
	_expect(new_output >= 0
		and int(city_storage.items.get("wood_log", 0)) == stored_before + 3 + new_output
		and int(runtime.daily.hauling.routes[HAULER_ID].cargo.quantity) == 0
		and runtime.daily.hauling.delivered_on_day(HAULER_ID, TimeComponentManager.current_day) == 3
		and runtime._daily_output_count(WOOD_SITE) == 0
		and _wood_total() == initial_wood_stock,
		"Exactly three cargo logs arrive once; additional laborer output is counted separately and total wood is conserved.")

func _wood_total() -> int:
	var total: int = int(city_storage.items.get("wood_log", 0))
	total += runtime._daily_output_count(WOOD_SITE)
	total += int(runtime.sites[WOOD_SITE].stock)
	if runtime.daily.hauling.routes.has(HAULER_ID):
		total += int(runtime.daily.hauling.routes[HAULER_ID].cargo.quantity)
	return total

func _clean_files() -> void:
	if not _isolated_profile_is_safe():
		_expect(false, "Refusing checkpoint cleanup outside the disposable economy QA profile.")
		return
	for suffix: String in ["", ".bak", ".tmp", ".pending"]:
		if FileAccess.file_exists(CHECKPOINT_PATH + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(CHECKPOINT_PATH + suffix))

func _isolated_profile_is_safe() -> bool:
	var qa_root: String = ProjectSettings.globalize_path("res://../citysave_suite_qa").simplify_path()
	var homes: Array[String] = []
	for variable: String in ["XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
		var home: String = OS.get_environment(variable).simplify_path()
		if home.is_empty() or not home.is_absolute_path() or not DirAccess.dir_exists_absolute(home) \
			or not home.begins_with(qa_root + "/") or homes.has(home):
			return false
		homes.append(home)
	return ProjectSettings.globalize_path("user://").simplify_path().begins_with(homes[0] + "/")

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
