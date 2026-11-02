extends "res://scenes/test_scenes/test_scene_city_save_economy.gd"

## The v10-shaped documents below come from a real city snapshot and are
## deliberately skewed for fault injection; they are not historical captures.
const SKEW_PATH: String = "user://v10_skew_save_test/checkpoint.json"
const BUILDER_ID: String = "v10_skew_builder"
const LEGACY_ERROR_PREFIX: String = "Legacy checkpoint has unsynchronized times."

var skew_plot: Node
var skew_plot_id: String
var shaping_order_id: String

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
	store.disk.path = SKEW_PATH
	_clean_skew_files()
	_prepare_city_state()
	if not _hire_and_assign_team() or not _hire_builder():
		await _finish_skew_test()
		return
	_settle_needs()
	skew_plot = content.get_node("YSortWorld/WorkshopPlot2").construction
	skew_plot_id = str(skew_plot.name)
	_test_idle_legacy_cursors()
	if not _start_active_fixture():
		await _finish_skew_test()
		return
	# Settle the current worksite ledger before testing the clock boundaries.
	_expect(TimeComponentManager.advance_minutes(1), "The active fixture advances one normal minute before saving.")

	# Save the settled current world through the production disk boundary.
	var saved: bool = store.save_checkpoint()
	_expect(saved, "The current fixture saves: " + store.last_error)
	if not saved:
		await _finish_skew_test()
		return
	var current_bytes: PackedByteArray = FileAccess.get_file_as_bytes(SKEW_PATH)
	var current: Dictionary = JSON.parse_string(current_bytes.get_string_from_utf8())
	var current_raw: Dictionary = MIGRATION_VALUES.new().decode(current.state)
	var before: Dictionary = store.snapshot.capture(content)
	_expect(current.schema_version == store.snapshot.VERSION and _settled_active(current_raw),
		"The current control has a live shaping order, drying batch, building plot, and settled cursors.")
	_assert_valid_continue(current_bytes, before, "current")

	# Starting from the same real state, construct the exact older field shape.
	var legacy: Dictionary = _legacy_document(current, current_raw)
	var legacy_bytes: PackedByteArray = _document_bytes(legacy)
	var source_codec = MIGRATION_VALUES.new()
	source_codec.allow_legacy_resignation_field = true
	var legacy_raw: Dictionary = source_codec.decode(legacy.state)
	var source_is_legacy: bool = source_codec.error.is_empty() and int(legacy.schema_version) == 10
	for old_plot: Dictionary in legacy_raw.plots.values():
		source_is_legacy = source_is_legacy and not old_plot.has("worker_capacity") and not old_plot.has("work_total_units")
	var old_workers: Array = MIGRATION_FIXTURE.city_objects(legacy.state, "WorkerData")
	source_is_legacy = source_is_legacy and not old_workers.is_empty()
	for object: Dictionary in old_workers:
		source_is_legacy = source_is_legacy and not object.fields.has("resignation_pending")
	for route: Dictionary in legacy_raw.worksites.routes.values():
		source_is_legacy = source_is_legacy and not route.has("resigning")
	source_is_legacy = source_is_legacy and legacy_raw.worksites.schema_version == 1 \
		and not legacy_raw.worksites.has("pending_output") and not legacy_raw.worksites.has("pending_progress")
	source_is_legacy = source_is_legacy and not legacy_raw.plots.has("WorkshopConstruction_" + "citizen_house_1".sha256_text())
	_expect(source_is_legacy, "The synthesized v10 control uses only historical worker, plot, and worksite fields.")
	var migrated_expected: Dictionary = before.duplicate(true)
	var migrated_raw: Dictionary = current_raw.duplicate(true)
	for route: Dictionary in migrated_raw.worksites.routes.values():
		route.removing = true
		route.legacy_final = true
	var house_id: String = "WorkshopConstruction_" + "citizen_house_1".sha256_text()
	migrated_raw.plots[house_id]._latest_time = int(migrated_raw.clock.current_day) * 1440 + int(migrated_raw.clock.current_hour) * 60 + int(migrated_raw.clock.current_minute)
	migrated_expected.state = MIGRATION_VALUES.new().encode(migrated_raw)
	_assert_valid_continue(legacy_bytes, migrated_expected, "v10")
	_test_active_cursor_skew(current, current_raw)
	_test_recovery_cursor_skew(current, current_raw, legacy_bytes, migrated_expected)
	await _finish_skew_test()

func _hire_builder() -> bool:
	var person := CitizenData.new()
	person.citizen_id = BUILDER_ID
	person.display_name = "Cursor test builder"
	person.population_status = CitizenData.PopulationStatus.RESIDENT
	person.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	person.satisfaction = 0.8
	person.visual_profile = VisualProfile.new()
	CitizenManager.add_citizen(person)
	Inventory.add_item("shekel", WorkerDatabase.get_contract_price(WorkerData.Profession.LABORER, 3))
	var registered: bool = CitizenManager.register_applicant(BUILDER_ID, WorkerData.Profession.LABORER)
	var worker: WorkerData = WorkerDatabase.hire_applicant(BUILDER_ID)
	_expect(registered and worker != null, "A fourth resident is hired for actual workshop construction.")
	return registered and worker != null

func _test_idle_legacy_cursors() -> void:
	var current: Dictionary = store.snapshot.capture(content)
	var raw: Dictionary = MIGRATION_VALUES.new().decode(current.state)
	_expect(raw.work.active_orders.is_empty(), "The idle-cursor fixture has no shaping orders.")
	var inactive: Dictionary = raw.plots[skew_plot_id]
	_expect(inactive.phase not in ["building", "clearing"], "The idle-cursor fixture has an inactive workshop plot.")
	var expected_accounts: Variant = _accounts()
	raw.work._last_total_minutes = -1
	raw.process._last_total_minutes = -1
	inactive._latest_time = maxi(0, _clock_minute() - 10)
	var legacy: Dictionary = _legacy_document(current, raw)
	var bytes: PackedByteArray = _document_bytes(legacy)
	_write_skew_bytes(bytes)
	var files_before: Dictionary = _skew_files()
	for attempt: int in range(2):
		_expect(store.load_checkpoint(), "Idle v10 cursors load (attempt %d): " % attempt + store.last_error)
		_expect(_same_snapshot(expected_accounts, _accounts()) and skew_plot._latest_time == inactive._latest_time,
			"Idle -1 and an inactive stale plot preserve saved accounts (attempt %d)." % attempt)
		_expect(_skew_files() == files_before and FileAccess.get_file_as_bytes(SKEW_PATH) == bytes,
			"Idle v10 Continue preserves all file bytes (attempt %d)." % attempt)

func _start_active_fixture() -> bool:
	# Actual paid construction, shaping, and passive drying coexist in one save.
	skew_plot.phase = "empty"
	skew_plot.clearing_remaining = 0
	for item_id: String in skew_plot.REQUIREMENTS:
		Inventory.add_item(item_id, int(skew_plot.REQUIREMENTS[item_id]))
	var builders: Array[String] = [BUILDER_ID]
	var build: Dictionary = skew_plot.start_build(builders)
	_expect(bool(build.get("success", false)), "The paid builder starts real construction.")
	if not bool(build.get("success", false)):
		return false
	var builder: WorkerData = WorkerDatabase.get_worker_data(BUILDER_ID)
	builder.physical_approach.position = builder.physical_approach.target
	var arrived: bool = builder.mark_physical_arrival(skew_plot.order_id + ":building")
	_expect(arrived, "The construction worker reaches the plot entry.")
	if not arrived:
		return false
	var job: JobData = preload("res://resources/job_data/mudbrick_make.tres")
	for item_id: String in job.inputs:
		WorkShopStorage.add_item(item_id, int(job.inputs[item_id]))
	shaping_order_id = WorkManager.start_job(job, WorkOrder.Worker_Type.NPC, PRODUCTION_ID,
		null, WorkShopStorage, WorkShopStorage, 5)
	_expect(not shaping_order_id.is_empty(), "A paid worker starts a real shaping order: " + WorkManager.last_start_job_error)
	if shaping_order_id.is_empty():
		return false
	_expect(WorkshopFacilityManager.set_facility_level("drying_yard", 1), "The fixture opens one drying slot.")
	TimeComponentManager.current_weather = "clear"
	TimeComponentManager.emit_time_signal()
	WorkShopStorage.add_item("wet_mudbrick", 20)
	var started: bool = ProcessManager.start_registered_process(PROCESS_ID, 20)
	_expect(started, "The fixture starts a real drying batch.")
	return started

func _settled_active(raw: Dictionary) -> bool:
	var now: int = int(raw.clock.current_day) * 1440 + int(raw.clock.current_hour) * 60 + int(raw.clock.current_minute)
	var station: StationState = raw.process.stations.get("drying_yard")
	return raw.work.active_orders.has(shaping_order_id) and station != null and station.slots[0] != null \
		and raw.plots[skew_plot_id].phase == "building" and raw.plots[skew_plot_id]._latest_time == now \
		and raw.work._last_total_minutes == now and raw.process._last_total_minutes == now \
		and raw.worksites.ledger.last_tick == now and not raw.worksites.routes.has(HAULER_ID)

func _assert_valid_continue(bytes: PackedByteArray, expected: Dictionary, label: String) -> void:
	_write_skew_bytes(bytes)
	var files_before: Dictionary = _skew_files()
	for attempt: int in range(2):
		var loaded: bool = store.load_checkpoint()
		_expect(loaded, "%s Continue loads (attempt %d): " % [label, attempt] + store.last_error)
		if not loaded:
			return
		_expect(_same_snapshot(expected, store.snapshot.capture(content)),
			"%s Continue preserves every saved owner, job, need, and resource (attempt %d)." % [label, attempt])
		_expect(_skew_files() == files_before and FileAccess.get_file_as_bytes(SKEW_PATH) == bytes,
			"%s Continue leaves the source and recovery bytes unchanged (attempt %d)." % [label, attempt])
	_assert_one_minute_of_work(label)
	_expect(store.load_checkpoint() and _same_snapshot(expected, store.snapshot.capture(content)),
		"%s Continue rolls the single elapsed minute back without duplication." % label)
	_expect(_skew_files() == files_before, "%s reloading after advancement leaves files unchanged." % label)

func _assert_one_minute_of_work(label: String) -> void:
	var order: WorkOrder = WorkManager.active_orders.get(shaping_order_id)
	var batch: ProcessBatch = (ProcessManager.stations["drying_yard"] as StationState).slots[0] as ProcessBatch
	_expect(order != null and batch != null, "%s still has its active order and batch." % label)
	if order == null or batch == null:
		return
	var now: int = _clock_minute()
	var work_remaining: int = order.end_time_total_minutes - now
	var building_remaining: int = skew_plot.completes_at - skew_plot._latest_time
	var progress: int = batch.progress_minutes
	var accounts: Variant = _accounts()
	TimeComponentManager.advance_minutes(1)
	order = WorkManager.active_orders.get(shaping_order_id)
	batch = (ProcessManager.stations["drying_yard"] as StationState).slots[0] as ProcessBatch
	_expect(order != null and order.end_time_total_minutes - _clock_minute() == work_remaining - 1
		and batch != null and batch.progress_minutes == progress + 1
		and skew_plot.completes_at - skew_plot._latest_time == building_remaining - 1,
		"%s advances paid shaping, drying, and construction once after Continue." % label)
	_expect(_same_snapshot(accounts, _accounts()),
		"%s one-minute continuation does not repeat needs, materials, fees, or outputs." % label)

func _test_active_cursor_skew(current: Dictionary, current_raw: Dictionary) -> void:
	var now: int = int(current_raw.clock.current_day) * 1440 + int(current_raw.clock.current_hour) * 60 + int(current_raw.clock.current_minute)
	_expect(posmod(now, 1440) > 0 and posmod(now, 1440) < 1439,
		"Both worksite cursor probes remain on the saved ledger day.")
	for owner: String in ["work", "process", "plot", "worksite"]:
		var cursors: Array[int] = [now - 1, now + 1]
		if owner in ["work", "process"]:
			cursors.append(-1)
		for cursor: int in cursors:
			var raw: Dictionary = current_raw.duplicate(true)
			match owner:
				"work": raw.work._last_total_minutes = cursor
				"process": raw.process._last_total_minutes = cursor
				"plot": raw.plots[skew_plot_id]._latest_time = cursor
				"worksite": raw.worksites.ledger.last_tick = cursor
			var legacy: Dictionary = _legacy_document(current, raw)
			var bytes: PackedByteArray = _document_bytes(legacy)
			_write_skew_bytes(bytes)
			var files_before: Dictionary = _skew_files()
			var sentinel: Dictionary = store.snapshot.capture(content)
			var label: String = "%s = %d" % [owner, cursor]
			for attempt: int in range(2):
				var rejected: bool = not store.load_checkpoint()
				_expect(rejected and store.last_error.begins_with(LEGACY_ERROR_PREFIX),
					"v10 rejects the ambiguous %s cursor (attempt %d): " % [label, attempt] + store.last_error)
				_expect(_same_snapshot(sentinel, store.snapshot.capture(content)) and _skew_files() == files_before,
					"Rejected %s preserves every live owner and save file (attempt %d)." % [label, attempt])
			_expect(not store.save_checkpoint(), "Save cannot overwrite a rejected %s checkpoint." % label)
			_expect(_skew_files() == files_before and FileAccess.get_file_as_bytes(SKEW_PATH) == bytes
				and _same_snapshot(sentinel, store.snapshot.capture(content)),
				"Rejected %s retains exact source bytes, backup files, needs, materials, and outputs." % label)

func _test_recovery_cursor_skew(current: Dictionary, current_raw: Dictionary, valid_bytes: PackedByteArray, expected: Dictionary) -> void:
	var raw: Dictionary = current_raw.duplicate(true)
	raw.process._last_total_minutes -= 1
	var skew_bytes: PackedByteArray = _document_bytes(_legacy_document(current, raw))
	for suffix: String in [".tmp", ".pending"]:
		_clean_skew_files()
		_write_skew_file(SKEW_PATH + suffix, skew_bytes)
		_write_skew_file(SKEW_PATH + ".bak", valid_bytes)
		store.refresh_checkpoint_slot()
		var files_before: Dictionary = _skew_files()
		var sentinel: Dictionary = store.snapshot.capture(content)
		_expect(not store.save_checkpoint() and store.last_error.begins_with(LEGACY_ERROR_PREFIX),
			"A save cannot skip the ambiguous %s recovery candidate." % suffix)
		for attempt: int in range(2):
			_expect(not store.load_checkpoint() and store.last_error.begins_with(LEGACY_ERROR_PREFIX),
				"Continue does not silently fall back past ambiguous %s (attempt %d)." % [suffix, attempt])
			_expect(_skew_files() == files_before and _same_snapshot(sentinel, store.snapshot.capture(content)),
				"Rejected %s recovery preserves every live owner and recovery file." % suffix)
		_expect(not store.save_checkpoint() and _skew_files() == files_before,
			"Save cannot overwrite recovery files after rejecting %s." % suffix)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SKEW_PATH + suffix))
		var backup_only: Dictionary = _skew_files()
		_expect(store.load_checkpoint() and _same_snapshot(expected, store.snapshot.capture(content)),
			"An unambiguous backup still loads after %s is removed: " % suffix + store.last_error)
		_expect(_skew_files() == backup_only, "Loading the valid backup leaves its bytes unchanged.")
	# A candidate invalid for another v10 rule was never a recoverable checkpoint;
	# its incidental skew must not prevent the normal fallback to a valid backup.
	_clean_skew_files()
	raw.pickup_sources = {}
	_write_skew_file(SKEW_PATH + ".tmp", _document_bytes(_legacy_document(current, raw)))
	_write_skew_file(SKEW_PATH + ".bak", valid_bytes)
	store.refresh_checkpoint_slot()
	var invalid_candidate: Dictionary = _skew_files()
	_expect(store.load_checkpoint() and _same_snapshot(expected, store.snapshot.capture(content)),
		"An otherwise invalid recovery candidate does not block a valid backup.")
	_expect(_skew_files() == invalid_candidate, "Fallback keeps the invalid candidate and valid backup unchanged.")
	for suffix: String in [".tmp", ".pending", ".bak"]:
		_clean_skew_files()
		_write_skew_file(SKEW_PATH, valid_bytes)
		_write_skew_file(SKEW_PATH + suffix, skew_bytes)
		store.refresh_checkpoint_slot()
		var files_before: Dictionary = _skew_files()
		var sentinel: Dictionary = store.snapshot.capture(content)
		_expect(not store.load_checkpoint() and store.last_error.begins_with(LEGACY_ERROR_PREFIX),
			"A valid primary cannot hide ambiguous %s recovery data." % suffix)
		_expect(not store.save_checkpoint() and _skew_files() == files_before
			and _same_snapshot(sentinel, store.snapshot.capture(content)),
			"No file or live owner changes while %s is ambiguous." % suffix)
	_clean_skew_files()
	_write_skew_file(SKEW_PATH + ".tmp", valid_bytes)
	_write_skew_file(SKEW_PATH + ".pending", skew_bytes)
	store.refresh_checkpoint_slot()
	var later_pending: Dictionary = _skew_files()
	_expect(not store.load_checkpoint() and store.last_error.begins_with(LEGACY_ERROR_PREFIX),
		"A valid temporary file cannot hide an ambiguous pending file.")
	_expect(not store.save_checkpoint() and _skew_files() == later_pending,
		"A later save cannot overwrite the ambiguous pending file.")

func _accounts() -> Variant:
	var raw: Dictionary = MIGRATION_VALUES.new().decode(store.snapshot.capture(content).state)
	return MIGRATION_VALUES.new().encode({"inventory": raw.inventory, "city_storage": raw.city_storage,
		"stock": raw.stock, "citizens": raw.citizens, "needs": raw.needs,
		"workshop_storage": raw.workshop_storage})

func _legacy_document(current: Dictionary, raw: Dictionary) -> Dictionary:
	var legacy: Dictionary = current.duplicate(true)
	legacy.schema_version = 10
	legacy.state = MIGRATION_FIXTURE.encode_v10(MIGRATION_VALUES.new(), raw)
	return legacy

func _document_bytes(document: Dictionary) -> PackedByteArray:
	return (JSON.stringify(document, "\t", true, true) + "\n").to_utf8_buffer()

func _write_skew_bytes(bytes: PackedByteArray) -> void:
	_write_skew_file(SKEW_PATH, bytes)

func _write_skew_file(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SKEW_PATH).get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

func _skew_files() -> Dictionary:
	var result: Dictionary = {}
	for suffix: String in ["", ".bak", ".tmp", ".pending"]:
		var path: String = SKEW_PATH + suffix
		result[suffix] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	return result

func _clean_skew_files() -> void:
	for suffix: String in ["", ".bak", ".tmp", ".pending"]:
		if FileAccess.file_exists(SKEW_PATH + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SKEW_PATH + suffix))

func _finish_skew_test() -> void:
	_clean_skew_files()
	if is_instance_valid(content):
		content.queue_free()
		await get_tree().process_frame
	_restore_clock()
	print("V10SkewSaveTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
