extends "res://scenes/test_scenes/test_scene_satisfaction_condition_save.gd"

## Read the real v16 checkpoint written by the unmodified baseline test, then
## save and reload the current checkpoint using only a disposable APPDATA profile.
func _same_satisfaction(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size():
		return false
	for id: Variant in expected:
		if not actual.has(id) or absf(float(actual[id]) - float(expected[id])) > 0.000000000001:
			return false
	return true

func _run() -> void:
	phase = "read"
	var profile: String = OS.get_environment("APPDATA").replace("\\", "/").to_lower().trim_suffix("/")
	var user_root: String = ProjectSettings.globalize_path("user://").replace("\\", "/").to_lower()
	_expect(not profile.is_empty() and user_root.begins_with(profile + "/"), "The migration test uses isolated APPDATA.")
	_expect(FileAccess.file_exists(SAVE_PATH), "An isolated baseline writer has produced the source checkpoint.")
	if failures > 0:
		_finish()
		return
	initial_bytes = FileAccess.get_file_as_bytes(SAVE_PATH)
	initial_document = _parse_document(initial_bytes)
	_expect(initial_document.get("schema_version") == 16, "The source was actually written by the version 16 baseline.")
	var codec = SAVE_VALUES.new()
	var decoded: Variant = codec.decode(initial_document.get("state"))
	_expect(codec.error.is_empty() and decoded is Dictionary, "The baseline state decodes cleanly.")
	if failures > 0:
		_finish()
		return
	initial_state = decoded
	await _open_session(true)
	if not launched:
		_finish()
		return
	var now: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	var end_of_day: int = (TimeComponentManager.current_day + 1) * 1440
	_expect(TimeComponentManager.current_hour == 23 and TimeComponentManager.current_minute == 59, "Continue restores the exact legacy minute.")
	_expect(FileAccess.get_file_as_bytes(SAVE_PATH) == initial_bytes, "Migrating Continue never rewrites the v16 source.")
	for id: String in [LINKED_ID, RESIDENT_ID, LEGACY_WORKER_ID]:
		_expect(int(CitizenNeedsManager.satisfaction_last_minute.get(id, -1)) == now,
			"Legacy satisfaction starts at the checkpoint minute for " + id)
	var source_needs: Dictionary = initial_state.needs
	for id: String in [LINKED_ID, RESIDENT_ID, LEGACY_WORKER_ID]:
		var result: Dictionary = source_needs.last_needs_results.get(id, {})
		var expected_expiry: int = end_of_day if bool(result.get("food", false)) else -1
		_expect(int(CitizenNeedsManager.food_coverage_until.get(id, -1)) == expected_expiry,
			"Only already-consumed legacy food is covered until midnight for " + id)
	var progression: Node = WorkStateRuntime.get_node("CityProgression")
	var old_progress: int = progression.progress
	var old_day: int = progression.last_awarded_day
	var old_daily: Dictionary = progression.last_daily.duplicate(true)
	var old_satisfaction: Dictionary = _all_satisfactions()
	var old_coverage: Dictionary = CitizenNeedsManager.food_coverage_until.duplicate(true)
	var storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var old_items: Dictionary = storage.items.duplicate(true)
	_expect(store.load_checkpoint(), "The unmodified v16 checkpoint can be loaded repeatedly: " + store.last_error)
	_expect(FileAccess.get_file_as_bytes(SAVE_PATH) == initial_bytes and storage.items == old_items
		and _all_satisfactions() == old_satisfaction and CitizenNeedsManager.food_coverage_until == old_coverage,
		"Repeated legacy loads do not change source bytes, stock, Satisfaction, or ration coverage.")
	CitizenNeedsManager.needs_changed.emit()
	_expect(progression.progress == old_progress and progression.last_awarded_day == old_day and progression.last_daily == old_daily,
		"A refresh after legacy Continue cannot award the city bonus twice.")
	_expect(TimeComponentManager.advance_minutes(1), "The migrated checkpoint advances across midnight.")
	for id: String in [LINKED_ID, RESIDENT_ID, LEGACY_WORKER_ID]:
		var after: float = float(_person_summary(id).get("satisfaction", -1.0))
		_expect(absf(after - float(old_satisfaction[id])) <= 0.05 / 1440.0 + 0.000002,
			"Midnight applies at most one elapsed minute, with no old daily jump, for " + id)
	var after_progress: int = progression.progress
	var after_day: int = progression.last_awarded_day
	var after_daily: Dictionary = progression.last_daily.duplicate(true)
	CitizenNeedsManager.needs_changed.emit()
	CitizenNeedsManager.process_daily_needs()
	_expect(progression.progress == after_progress and progression.last_awarded_day == after_day and progression.last_daily == after_daily,
		"Repeated needs notifications after midnight do not duplicate city progress.")
	_expect(store.save_checkpoint(), "The migrated state saves as a new checkpoint: " + store.last_error)
	var v17_bytes: PackedByteArray = FileAccess.get_file_as_bytes(SAVE_PATH)
	var v17: Dictionary = _parse_document(v17_bytes)
	_expect(v17.get("schema_version") == store.snapshot.VERSION and FileAccess.get_file_as_bytes(SAVE_PATH + ".bak") == initial_bytes,
		"The new version is written and the exact original v16 bytes are kept as its backup.")
	var saved_satisfaction: Dictionary = _all_satisfactions()
	var saved_coverage: Dictionary = CitizenNeedsManager.food_coverage_until.duplicate(true)
	var saved_cursors: Dictionary = CitizenNeedsManager.satisfaction_last_minute.duplicate(true)
	var saved_stock: Dictionary = storage.items.duplicate(true)
	_expect(store.load_checkpoint(), "The new checkpoint loads: " + store.last_error)
	if FileAccess.get_file_as_bytes(SAVE_PATH) != v17_bytes or not _same_satisfaction(_all_satisfactions(), saved_satisfaction) or CitizenNeedsManager.food_coverage_until != saved_coverage or CitizenNeedsManager.satisfaction_last_minute != saved_cursors or storage.items != saved_stock:
		print("MIGRATION_DIAG bytes=", FileAccess.get_file_as_bytes(SAVE_PATH) == v17_bytes,
			" sat_before=", saved_satisfaction, " sat_after=", _all_satisfactions(),
			" coverage_before=", saved_coverage, " coverage_after=", CitizenNeedsManager.food_coverage_until,
			" cursors_before=", saved_cursors, " cursors_after=", CitizenNeedsManager.satisfaction_last_minute,
			" stock_before=", saved_stock, " stock_after=", storage.items)
		var after_satisfaction: Dictionary = _all_satisfactions()
		for id: String in [LINKED_ID, RESIDENT_ID, LEGACY_WORKER_ID]:
			print("MIGRATION_FLOAT ", id, " before=%.17f after=%.17f difference=%.17f" % [float(saved_satisfaction[id]), float(after_satisfaction[id]), float(after_satisfaction[id]) - float(saved_satisfaction[id])])
		print("MIGRATION_EQUAL sat=", after_satisfaction == saved_satisfaction,
			" coverage=", CitizenNeedsManager.food_coverage_until == saved_coverage,
			" cursors=", CitizenNeedsManager.satisfaction_last_minute == saved_cursors,
			" stock=", storage.items == saved_stock)
	_expect(FileAccess.get_file_as_bytes(SAVE_PATH) == v17_bytes and _same_satisfaction(_all_satisfactions(), saved_satisfaction)
		and CitizenNeedsManager.food_coverage_until == saved_coverage
		and CitizenNeedsManager.satisfaction_last_minute == saved_cursors and storage.items == saved_stock,
		"Reloading v17 preserves satisfaction, cursor, entitlement and inventory without rewriting or extra consumption.")
	# A malformed timing ledger must be rejected in the staging phase, before
	# it can touch any live owner or the checkpoint on disk.
	var v17_now: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	for kind: String in ["unknown", "future_cursor", "long_ration"]:
		var read_codec = SAVE_VALUES.new()
		var bad_state: Dictionary = read_codec.decode(v17.state)
		if kind == "unknown":
			bad_state.needs.food_coverage_until["unknown_person"] = v17_now + 1
		elif kind == "future_cursor":
			bad_state.needs.satisfaction_last_minute[RESIDENT_ID] = v17_now + 1
		else:
			bad_state.needs.food_coverage_until[RESIDENT_ID] = v17_now + 1441
		var write_codec = SAVE_VALUES.new()
		var corrupt: Dictionary = v17.duplicate(true)
		corrupt.state = write_codec.encode(bad_state)
		_expect(read_codec.error.is_empty() and write_codec.error.is_empty()
			and not store.snapshot.prepare(corrupt, city), "A malformed " + kind + " timing ledger is rejected.")
		_expect(FileAccess.get_file_as_bytes(SAVE_PATH) == v17_bytes and _same_satisfaction(_all_satisfactions(), saved_satisfaction)
			and storage.items == saved_stock, "Rejecting " + kind + " leaves live data and disk bytes intact.")
	# A checkpoint can legitimately contain stock alongside an uncovered person
	# (for example an older save before daily service, or a save before a deferred
	# transaction callback). A snapshot broadcast must not itself consume food.
	_expect(store.load_checkpoint(), "Restore a clean v17 state for the stock-on-load probe.")
	CitizenNeedsManager.food_coverage_until.clear()
	for id: String in [LINKED_ID, RESIDENT_ID, LEGACY_WORKER_ID]:
		var person: Variant = CitizenManager.get_citizen(id)
		if person == null:
			person = WorkerDatabase.get_worker_data(id)
		person.food_fulfilled = false
	storage.items[FOOD_ID] = 1
	storage.food_portions.clear()
	_expect(store.save_checkpoint(), "Save an isolated uncovered-person checkpoint containing one food item: " + store.last_error)
	var stock_on_load_bytes: PackedByteArray = FileAccess.get_file_as_bytes(SAVE_PATH)
	# A pending notification from the old world must not act on the restored one.
	storage.changed.emit()
	_expect(store.load_checkpoint(), "Load the uncovered-person checkpoint: " + store.last_error)
	for _frame: int in range(3):
		await get_tree().process_frame
	_expect(storage.get_food_supply_points() == 1 and CitizenNeedsManager.food_coverage_until.is_empty()
		and FileAccess.get_file_as_bytes(SAVE_PATH) == stock_on_load_bytes,
		"Load and its deferred notifications do not consume food or grant coverage without an elapsed minute.")
	storage.changed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(storage.get_food_supply_points() == 1 and CitizenNeedsManager.food_coverage_until.is_empty(),
		"A post-load tool/roster-only storage notification does not consume unchanged food stock.")
	_expect(TimeComponentManager.advance_minutes(1), "The loaded city advances one real game minute.")
	_expect(storage.get_food_supply_points() == 0 and CitizenNeedsManager.food_coverage_until.size() == 1,
		"After one elapsed minute a single actual ration is consumed and assigned once.")
	_expect(store.load_checkpoint(), "Restore the same stock-on-load checkpoint once more.")
	_expect(storage.try_add_worksite_output(FOOD_ID, 1), "A genuine new food delivery succeeds after load.")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(storage.get_food_supply_points() == 0 and CitizenNeedsManager.food_coverage_until.size() == 2,
		"A genuine post-load food delivery serves two uncovered people from the two actual points.")
	_finish()
