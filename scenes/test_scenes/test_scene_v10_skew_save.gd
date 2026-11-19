extends "res://scenes/test_scenes/test_scene_city_save_economy.gd"

## The v10-shaped documents below come from a real city snapshot and are
## deliberately skewed for fault injection; they are not historical captures.
const SKEW_PATH: String = "user://v10_skew_save_test/checkpoint.json"
const BUILDER_ID: String = "v10_skew_builder"
const LEGACY_ERROR_PREFIX: String = "Legacy checkpoint has unsynchronized times."
const EXPECTED_RESIDENT_IDS: Array[String] = [LABORER_ID, HAULER_ID, CITY_HAULER_ID, PRODUCTION_ID, BUILDER_ID]
const EXPECTED_WORKER_IDS: Array[String] = [LABORER_ID, HAULER_ID, PRODUCTION_ID, BUILDER_ID]
const ORACLE_MINUTES_PER_DAY: int = 1440
const ORACLE_SATISFACTION_DAILY_STEP: float = 0.05
const ORACLE_MINUTE_STEP: float = 0.05 / 1440.0

var skew_plot: Node
var skew_plot_id: String
var shaping_order_id: String

func _run() -> void:
	if not _isolated_profile_is_safe():
		_expect(false, "V10 skew fixture requires the disposable isolated economy QA profile; no checkpoint files were touched.")
		print("V10SkewSaveTest: FAIL (%d)" % maxi(1, failures))
		get_tree().quit(1)
		return
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
	var fixture_snapshot: Dictionary = store.snapshot.capture(content)
	var fixture_raw: Dictionary = MIGRATION_VALUES.new().decode(fixture_snapshot.state)
	if not _assert_five_resident_fixture(fixture_raw, "Initial v10 skew fixture"):
		await _finish_skew_test()
		return
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
	if not _assert_five_resident_fixture(current_raw, "Saved v10 skew fixture"):
		await _finish_skew_test()
		return
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
	# Decode a separate detached snapshot: deep Dictionary duplication would still
	# share the CitizenData/WorkerData Resources held by current_raw.
	var migrated_raw: Dictionary = MIGRATION_VALUES.new().decode(current.state)
	for route: Dictionary in migrated_raw.worksites.routes.values():
		route.removing = true
		route.legacy_final = true
	var house_id: String = "WorkshopConstruction_" + "citizen_house_1".sha256_text()
	migrated_raw.plots[house_id]._latest_time = int(migrated_raw.clock.current_day) * 1440 + int(migrated_raw.clock.current_hour) * 60 + int(migrated_raw.clock.current_minute)
	_expected_legacy_timing(migrated_raw)
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
	_expect(registered and worker != null, "A fifth resident is hired for actual workshop construction.")
	return registered and worker != null

func _test_idle_legacy_cursors() -> void:
	var current: Dictionary = store.snapshot.capture(content)
	var raw: Dictionary = MIGRATION_VALUES.new().decode(current.state)
	if not _assert_five_resident_fixture(raw, "Idle legacy cursor fixture"):
		return
	_expect(raw.work.active_orders.is_empty(), "The idle-cursor fixture has no shaping orders.")
	var inactive: Dictionary = raw.plots[skew_plot_id]
	_expect(inactive.phase not in ["building", "clearing"], "The idle-cursor fixture has an inactive workshop plot.")
	# Derive the expected migrated account owners from a separate decoded snapshot,
	# not from the current live Resources or from the legacy converter.
	var expected_raw: Dictionary = MIGRATION_VALUES.new().decode(current.state)
	_expected_legacy_timing(expected_raw)
	var expected_accounts: Variant = _accounts_from_raw(expected_raw)
	raw.work._last_total_minutes = -1
	raw.process._last_total_minutes = -1
	inactive._latest_time = maxi(0, _clock_minute() - 10)
	var legacy: Dictionary = _legacy_document(current, raw)
	var bytes: PackedByteArray = _document_bytes(legacy)
	_write_skew_bytes(bytes)
	var files_before: Dictionary = _skew_files()
	for attempt: int in range(2):
		_expect(store.load_checkpoint(), "Idle v10 cursors load (attempt %d): " % attempt + store.last_error)
		var actual_snapshot: Dictionary = store.snapshot.capture(content)
		_expect(_same_snapshot(expected_accounts, _accounts_from_snapshot(actual_snapshot)) and skew_plot._latest_time == inactive._latest_time,
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
	var before_snapshot: Dictionary = store.snapshot.capture(content)
	var before_raw: Dictionary = MIGRATION_VALUES.new().decode(before_snapshot.state)
	var expected_raw: Dictionary = MIGRATION_VALUES.new().decode(before_snapshot.state)
	if not _assert_five_resident_fixture(before_raw, "%s one-minute source" % label):
		return
	var minute_of_day: int = posmod(now, MINUTES_PER_DAY)
	var cursor_state_is_exact: bool = _has_exact_satisfaction_cursors(before_raw, now)
	var has_no_expiry: bool = _has_no_food_or_clothing_expiry_through_next_minute(before_raw, now)
	var legacy_history_is_absent: bool = label == "v10"
	var oracle_source_is_exact: bool = _one_minute_oracle_source_is_valid(before_raw, now, legacy_history_is_absent)
	var oracle_target_is_bounded: bool = _one_minute_oracle_targets_are_bounded(before_raw)
	_expect(minute_of_day > 0 and minute_of_day < MINUTES_PER_DAY - 1,
		"%s one-minute needs oracle begins away from midnight." % label)
	_expect(cursor_state_is_exact, "%s starts with exactly five satisfaction cursors at the saved minute." % label)
	_expect(oracle_source_is_exact,
		"%s starts with exactly five named satisfaction owners and legal exact-bit accumulator history." % label)
	_expect(oracle_target_is_bounded,
		"%s fixture needs are more than one daily-step minute from each satisfaction target." % label)
	_expect(has_no_expiry,
		"%s has no food or clothing expiry through the next minute." % label)
	if minute_of_day <= 0 or minute_of_day >= MINUTES_PER_DAY - 1 or not cursor_state_is_exact \
		or not oracle_source_is_exact or not oracle_target_is_bounded or not has_no_expiry:
		return
	var expected_needs_ok: bool = _expected_one_minute_needs(expected_raw, now, legacy_history_is_absent)
	_expect(expected_needs_ok, "%s independent one-minute oracle produced a legal five-owner result." % label)
	if not expected_needs_ok:
		return
	var expected_accounts: Variant = _accounts_from_raw(expected_raw)
	TimeComponentManager.advance_minutes(1)
	order = WorkManager.active_orders.get(shaping_order_id)
	batch = (ProcessManager.stations["drying_yard"] as StationState).slots[0] as ProcessBatch
	_expect(order != null and order.end_time_total_minutes - _clock_minute() == work_remaining - 1
		and batch != null and batch.progress_minutes == progress + 1
		and skew_plot.completes_at - skew_plot._latest_time == building_remaining - 1,
		"%s advances paid shaping, drying, and construction once after Continue." % label)
	var after_snapshot: Dictionary = store.snapshot.capture(content)
	_expect(_same_snapshot(expected_accounts, _accounts_from_snapshot(after_snapshot)),
		"%s one-minute continuation matches the independent needs oracle; all other account fields remain exact." % label)

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

func _accounts_from_snapshot(snapshot: Dictionary) -> Variant:
	var raw: Dictionary = MIGRATION_VALUES.new().decode(snapshot.state)
	return _accounts_from_raw(raw)

func _accounts_from_raw(raw: Dictionary) -> Variant:
	return MIGRATION_VALUES.new().encode({"inventory": raw.inventory, "city_storage": raw.city_storage,
		"stock": raw.stock, "citizens": raw.citizens, "needs": raw.needs,
		"workshop_storage": raw.workshop_storage})

func _assert_five_resident_fixture(raw: Dictionary, label: String) -> bool:
	var people: Dictionary = raw.get("citizens", {}).get("citizens_by_id", {})
	var workers: Dictionary = raw.get("workers", {}).get("workers_by_id", {})
	var valid: bool = people.size() == EXPECTED_RESIDENT_IDS.size() \
		and workers.size() == EXPECTED_WORKER_IDS.size()
	for id: String in EXPECTED_RESIDENT_IDS:
		var person: Variant = people.get(id)
		valid = valid and people.has(id) and person is CitizenData \
			and person.citizen_id == id and person.population_status == CitizenData.PopulationStatus.RESIDENT
	for id: String in EXPECTED_WORKER_IDS:
		var worker: Variant = workers.get(id)
		var linked_person: Variant = people.get(id)
		valid = valid and workers.has(id) and worker is WorkerData \
			and worker.worker_id == id and linked_person is CitizenData \
			and linked_person.population_status == CitizenData.PopulationStatus.RESIDENT
	valid = valid and not workers.has(CITY_HAULER_ID)
	_expect(valid, "%s contains exactly five named residents and only workers linked to that roster." % label)
	return valid

## Independently reconstruct the v10 timing seed for this five-resident fixture.
## Only the needs timing ledgers are replaced; the source raw snapshot is detached.
func _expected_legacy_timing(raw: Dictionary) -> void:
	var needs: Dictionary = raw.needs
	var clock: Dictionary = raw.clock
	var day: int = int(clock.current_day)
	var now: int = day * MINUTES_PER_DAY + int(clock.current_hour) * 60 + int(clock.current_minute)
	var coverage: Dictionary = {}
	var people: Dictionary = raw.citizens.citizens_by_id
	if int(needs.last_food_processed_day) == day:
		var next_midnight: int = (day + 1) * MINUTES_PER_DAY
		for id: String in EXPECTED_RESIDENT_IDS:
			var person: CitizenData = people[id]
			if person.food_fulfilled:
				coverage[id] = next_midnight
	var satisfaction_cursors: Dictionary = {}
	for id: String in EXPECTED_RESIDENT_IDS:
		satisfaction_cursors[id] = now
	needs.food_coverage_until = coverage
	needs.satisfaction_last_minute = satisfaction_cursors
	needs.satisfaction_accumulators = {}

## Apply one bounded fixture minute without using the production planner or codec.
## Existing history is accepted only when its exact binary64 anchor reconstructs
## the current value and its cursor is the saved minute. Legacy history starts
## from the saved Satisfaction value with zero elapsed minutes.
func _expected_one_minute_needs(raw: Dictionary, now: int, allow_empty_legacy_history: bool) -> bool:
	if not _one_minute_oracle_source_is_valid(raw, now, allow_empty_legacy_history) \
		or not _one_minute_oracle_targets_are_bounded(raw):
		return false
	var people: Dictionary = raw.citizens.citizens_by_id
	var needs: Dictionary = raw.needs
	var old_accumulators: Dictionary = needs.satisfaction_accumulators.duplicate(true)
	var expected_accumulators: Dictionary = {}
	for id: String in EXPECTED_RESIDENT_IDS:
		var person: CitizenData = people[id]
		var fulfilled: int = int(person.food_fulfilled) + int(person.clothing_fulfilled) + int(person.shelter_fulfilled)
		var target: float = 0.33 * float(fulfilled)
		var current: float = person.satisfaction
		var anchor: float = current
		var signed_minutes: int = 0
		if old_accumulators.has(id):
			var prior: Dictionary = old_accumulators[id]
			anchor = float(_oracle_decode_float64_hex(str(prior.anchor_bits)))
			signed_minutes = int(prior.minutes)
		var direction: int
		if target > current:
			direction = 1
		elif target < current:
			direction = -1
		else:
			return false
		signed_minutes += direction
		var value: float = anchor + ORACLE_SATISFACTION_DAILY_STEP * float(signed_minutes) / float(ORACLE_MINUTES_PER_DAY)
		# This fixture is deliberately far from both target saturation and the
		# outer [0, 1] boundary; fail if that precondition ever stops holding.
		if (direction > 0 and value >= target) or (direction < 0 and value <= target) \
			or value < 0.0 or value > 1.0:
			return false
		person.satisfaction = value
		needs.satisfaction_last_minute[id] = now + 1
		expected_accumulators[id] = {
			"anchor_bits": _oracle_float64_hex(anchor),
			"minutes": signed_minutes,
			"cursor": now + 1
		}
	needs.satisfaction_accumulators = expected_accumulators
	return _one_minute_oracle_source_is_valid(raw, now + 1, false)

func _one_minute_oracle_targets_are_bounded(raw: Dictionary) -> bool:
	var people: Dictionary = raw.get("citizens", {}).get("citizens_by_id", {})
	if people.size() != EXPECTED_RESIDENT_IDS.size():
		return false
	for id: String in EXPECTED_RESIDENT_IDS:
		if not people.has(id) or not people[id] is CitizenData:
			return false
		var person: CitizenData = people[id]
		var fulfilled: int = int(person.food_fulfilled) + int(person.clothing_fulfilled) + int(person.shelter_fulfilled)
		var target: float = 0.33 * float(fulfilled)
		if not is_finite(person.satisfaction) or person.satisfaction < 0.0 or person.satisfaction > 1.0 \
			or absf(target - person.satisfaction) <= ORACLE_MINUTE_STEP:
			return false
	return true

func _one_minute_oracle_source_is_valid(raw: Dictionary, now: int, allow_empty_legacy_history: bool) -> bool:
	var people: Dictionary = raw.get("citizens", {}).get("citizens_by_id", {})
	var needs: Variant = raw.get("needs", null)
	if people.size() != EXPECTED_RESIDENT_IDS.size() or not needs is Dictionary:
		return false
	var cursors: Variant = needs.get("satisfaction_last_minute", null)
	var accumulators: Variant = needs.get("satisfaction_accumulators", null)
	if not cursors is Dictionary or cursors.size() != EXPECTED_RESIDENT_IDS.size() or not accumulators is Dictionary:
		return false
	var has_empty_history: bool = accumulators.is_empty()
	if allow_empty_legacy_history:
		if not has_empty_history:
			return false
	elif accumulators.size() != EXPECTED_RESIDENT_IDS.size():
		return false
	for id: String in EXPECTED_RESIDENT_IDS:
		if not people.has(id) or not people[id] is CitizenData:
			return false
		if not cursors.has(id) or not cursors[id] is int or int(cursors[id]) != now:
			return false
		if has_empty_history:
			continue
		if not accumulators.has(id):
			return false
		var record: Variant = accumulators[id]
		if not record is Dictionary or record.size() != 3 or not record.has("anchor_bits") \
			or not record.has("minutes") or not record.has("cursor"):
			return false
		if typeof(record.anchor_bits) != TYPE_STRING or not record.minutes is int or not record.cursor is int:
			return false
		if int(record.cursor) != now or int(record.cursor) != int(cursors[id]):
			return false
		var anchor_value: Variant = _oracle_decode_float64_hex(str(record.anchor_bits))
		var minute_limit: int = int(float(ORACLE_MINUTES_PER_DAY) / ORACLE_SATISFACTION_DAILY_STEP)
		if anchor_value == null or float(anchor_value) < 0.0 or float(anchor_value) > 1.0 \
			or int(record.minutes) < -minute_limit or int(record.minutes) > minute_limit:
			return false
		var reconstructed: float = float(anchor_value) + ORACLE_SATISFACTION_DAILY_STEP \
			* float(record.minutes) / float(ORACLE_MINUTES_PER_DAY)
		var current: float = float((people[id] as CitizenData).satisfaction)
		if not is_finite(reconstructed) or reconstructed < 0.0 or reconstructed > 1.0 \
			or _oracle_float64_hex(reconstructed) != _oracle_float64_hex(current):
			return false
	return true

func _oracle_float64_bytes(value: float) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes

func _oracle_float64_hex(value: float) -> String:
	return _oracle_float64_bytes(value).hex_encode()

func _oracle_decode_float64_hex(hex_value: String) -> Variant:
	if hex_value.length() != 16:
		return null
	for index: int in range(hex_value.length()):
		if not "0123456789abcdef".contains(hex_value.substr(index, 1)):
			return null
	var bytes: PackedByteArray = hex_value.hex_decode()
	if bytes.size() != 8:
		return null
	var value: float = bytes.decode_double(0)
	return value if is_finite(value) else null

func _has_exact_satisfaction_cursors(raw: Dictionary, expected_minute: int) -> bool:
	var cursors: Dictionary = raw.needs.satisfaction_last_minute
	if cursors.size() != EXPECTED_RESIDENT_IDS.size():
		return false
	for id: String in EXPECTED_RESIDENT_IDS:
		if not cursors.has(id) or int(cursors[id]) != expected_minute:
			return false
	return true

func _has_no_food_or_clothing_expiry_through_next_minute(raw: Dictionary, now: int) -> bool:
	var needs: Dictionary = raw.needs
	for expiry: Variant in needs.food_coverage_until.values():
		if int(expiry) <= now + 1:
			return false
	var end_of_next_minute: int = now + 1
	for allocation: Variant in needs.clothing_allocations.values():
		if allocation is Dictionary and allocation.get("expires_day") is int:
			var expires_at: int = (int(allocation.expires_day) + 1) * MINUTES_PER_DAY
			if expires_at <= end_of_next_minute:
				return false
	return true

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
