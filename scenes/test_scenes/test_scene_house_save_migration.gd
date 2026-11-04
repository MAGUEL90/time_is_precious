extends "res://scenes/test_scenes/test_scene_city_sleep_save.gd"

## Run with an isolated XDG_DATA_HOME. All checkpoint paths below are test-only.
const HOUSE_ID: String = "citizen_house_1"
const HOUSE_ORDER: String = "construction:citizen_house_1"
var house_state: Node
var house_key: String = "WorkshopConstruction_" + HOUSE_ID.sha256_text()
var test_root: String = "user://house_save_migration_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]

func _run() -> void:
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	_reset_singletons_before_load()
	await _load_root_city()
	_prepare_city_state()
	if not _hire_and_assign_team():
		_finish_house_test()
		return
	_settle_needs()
	Inventory.max_load = 1000.0
	Inventory.add_item("wood_log", 11)
	Inventory.add_item("clay_lump", 13)
	Inventory.add_item("reed_bundle", 9)
	house_state = content.get_node("YSortWorld/CitizenHousePlot").construction
	_expect(store.snapshot.VERSION == 15 and house_state.order_id == HOUSE_ORDER
		and store.snapshot.plots(content).get(house_key) == house_state,
		"The authored house retains its plot identity in the current checkpoint schema.")
	_test_v11_continue()
	_test_invalid_layouts()
	if not _test_clearing_and_building():
		_finish_house_test()
		return
	await _test_home_completion()
	_finish_house_test()

func _test_v11_continue() -> void:
	for capacity: int in [0, 9]:
		CityStockManager.shelter_capacity = capacity
		var current: Dictionary = store.snapshot.capture(content)
		var values = MIGRATION_VALUES.new()
		var raw: Dictionary = values.decode(current.state)
		var saved_inventory: Dictionary = raw.inventory.items.duplicate(true)
		var saved_storage: Dictionary = raw.city_storage.items.duplicate(true)
		var saved_worker: WorkerData = raw.workers.workers_by_id[PRODUCTION_ID]
		var saved_job: Dictionary = raw.worksites.jobs[str(WOOD_SITE)].duplicate(true)
		var expected_xp: int = saved_worker.profession_xp
		var legacy: Dictionary = current.duplicate(true)
		legacy.schema_version = 11
		legacy.state = MIGRATION_FIXTURE.encode_v11(values, raw)
		var legacy_raw: Dictionary = values.decode(legacy.state)
		_expect(legacy_raw.plots.size() == 2 and not legacy_raw.plots.has(house_key), "The v11 source contains only the two historical plots.")
		var bytes: PackedByteArray = (JSON.stringify(legacy, "\t", true, true) + "\n").to_utf8_buffer()
		var path: String = test_root.path_join("legacy_%d.json" % capacity)
		_write_house_bytes(path, bytes)
		_select_house_path(path)
		# A previous session can have a built house; migration must use old data,
		# rather than the current plot or current capacity as its starting point.
		house_state.phase = "built"
		CityStockManager.shelter_capacity = capacity + 5
		Inventory.items.clear()
		WorkerDatabase.get_worker_data(PRODUCTION_ID).profession_xp = expected_xp + 10
		var files_before: Dictionary = _house_files(path)
		for attempt: int in range(2):
			var loaded: bool = store.load_checkpoint()
			_expect(loaded, "A v11 checkpoint loads at capacity %d (attempt %d): " % [capacity, attempt] + store.last_error)
			if not loaded:
				break
			var restored: WorkerData = WorkerDatabase.get_worker_data(PRODUCTION_ID)
			var restored_job: Dictionary = store.snapshot._sites.capture(runtime).jobs[str(WOOD_SITE)]
			_expect(CityStockManager.shelter_capacity == capacity and house_state.phase == "uncleared"
				and house_state.clearing_remaining == house_state.CLEARING_MINUTES
				and house_state.worker_ids.is_empty() and house_state._latest_time == _clock_minute(),
				"Continue preserves old shelter capacity and initializes one fresh house (attempt %d)." % attempt)
			_expect(_same_snapshot(Inventory.items, saved_inventory) and _same_snapshot(city_storage.items, saved_storage)
				and restored.profession_xp == expected_xp and _same_snapshot(restored_job, saved_job),
				"Continue preserves inventory, city materials, worker XP and existing assignments (attempt %d)." % attempt)
			_expect(_house_files(path) == files_before and FileAccess.get_file_as_bytes(path) == bytes,
				"Continue leaves every v11 source/recovery file unchanged (attempt %d)." % attempt)
		_expect(store.save_checkpoint(), "An explicit save upgrades the v11 checkpoint: " + store.last_error)
		var upgraded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var upgraded_raw: Dictionary = values.decode(upgraded.state)
		_expect(upgraded.schema_version == store.snapshot.VERSION and upgraded_raw.plots.has(house_key)
			and FileAccess.get_file_as_bytes(path + ".bak") == bytes,
			"The current save contains the house and retains exact v11 bytes in the backup.")

func _test_invalid_layouts() -> void:
	var current: Dictionary = store.snapshot.capture(content)
	var values = MIGRATION_VALUES.new()
	var raw: Dictionary = values.decode(current.state)
	for invalid_case: String in ["v12_missing", "v12_extra", "v12_forged_order", "v12_forged_phase", "v11_extra_house"]:
		var bad_raw: Dictionary = raw.duplicate(true)
		var bad: Dictionary = current.duplicate(true)
		match invalid_case:
			"v12_missing": bad_raw.plots.erase(house_key)
			"v12_extra": bad_raw.plots["unregistered_plot"] = bad_raw.plots[house_key].duplicate(true)
			"v12_forged_order": bad_raw.plots[house_key].order_id = "construction:forged_house"
			"v12_forged_phase": bad_raw.plots[house_key].phase = "forged"
			"v11_extra_house": bad.schema_version = 11
		bad.state = values.encode(bad_raw)
		var bytes: PackedByteArray = (JSON.stringify(bad, "\t", true, true) + "\n").to_utf8_buffer()
		var path: String = test_root.path_join(invalid_case + ".json")
		_write_house_bytes(path, bytes)
		_select_house_path(path)
		var files_before: Dictionary = _house_files(path)
		var sentinel: Dictionary = store.snapshot.capture(content)
		_expect(not store.load_checkpoint() and not store.save_checkpoint(), "A malformed house layout blocks Continue and Save: " + invalid_case)
		_expect(_house_files(path) == files_before and FileAccess.get_file_as_bytes(path) == bytes
			and _same_snapshot(sentinel, store.snapshot.capture(content)),
			"The rejected layout preserves all files and live owners: " + invalid_case)

func _test_clearing_and_building() -> bool:
	_select_house_path(test_root.path_join("clearing.json"))
	var ids: Array[String] = [PRODUCTION_ID]
	var started: Dictionary = house_state.start_clearing(ids, false)
	_expect(bool(started.get("success", false)), "A hired worker starts clearing the house plot.")
	if not bool(started.get("success", false)) or not _arrive_at_house("clearing"):
		return false
	TimeComponentManager.advance_minutes(5)
	var clearing_remaining: int = house_state.completes_at - house_state._latest_time
	var clearing_inventory: Dictionary = Inventory.items.duplicate(true)
	var base_capacity: int = CityStockManager.shelter_capacity
	_expect(_save_and_reload_house("clearing", clearing_remaining, base_capacity, clearing_inventory), "Clearing survives repeated disk saves and loads.")
	TimeComponentManager.advance_minutes(clearing_remaining)
	_expect(house_state.phase == "empty" and CityStockManager.shelter_capacity == base_capacity, "Clearing completes without granting shelter.")
	var requirements: Dictionary = house_state.get_requirements()
	var before_build: Dictionary = Inventory.items.duplicate(true)
	started = house_state.start_build(ids)
	_expect(bool(started.get("success", false)), "The same worker starts house construction with the real materials.")
	if not bool(started.get("success", false)) or not _arrive_at_house("building"):
		return false
	var consumed_once: bool = true
	for id: String in requirements:
		consumed_once = consumed_once and int(Inventory.items.get(id, 0)) == int(before_build.get(id, 0)) - int(requirements[id])
	_expect(consumed_once, "Starting construction consumes the actual material requirements once.")
	TimeComponentManager.advance_minutes(5)
	var building_remaining: int = house_state.completes_at - house_state._latest_time
	var building_inventory: Dictionary = Inventory.items.duplicate(true)
	_select_house_path(test_root.path_join("building.json"))
	_expect(_save_and_reload_house("building", building_remaining, base_capacity, building_inventory), "Building survives repeated disk saves and loads.")
	# Establish a consistent nearly-finished job to exercise the completion
	# boundary in a single work shift and through the real home handoff.
	house_state.completes_at = house_state._latest_time + 3
	return true

func _arrive_at_house(phase_name: String) -> bool:
	var worker: WorkerData = WorkerDatabase.get_worker_data(PRODUCTION_ID)
	if worker == null or worker.physical_approach.is_empty():
		_expect(false, "The house worker has an authored physical approach: " + phase_name)
		return false
	worker.physical_approach.position = worker.physical_approach.target
	var arrived: bool = worker.mark_physical_arrival(HOUSE_ORDER + ":" + phase_name)
	_expect(arrived, "The house worker reaches the authored entry: " + phase_name)
	return arrived

func _save_and_reload_house(phase_name: String, remaining: int, capacity: int, materials: Dictionary) -> bool:
	var path: String = store.disk.path
	for attempt: int in range(2):
		if not store.save_checkpoint():
			_expect(false, "The %s checkpoint saves: " % phase_name + store.last_error)
			return false
		var files_before: Dictionary = _house_files(path)
		if not store.load_checkpoint():
			_expect(false, "The %s checkpoint loads: " % phase_name + store.last_error)
			return false
		var worker: WorkerData = WorkerDatabase.get_worker_data(PRODUCTION_ID)
		_expect(house_state.phase == phase_name and house_state.completes_at - house_state._latest_time == remaining
			and CityStockManager.shelter_capacity == capacity and _same_snapshot(Inventory.items, materials)
			and worker != null and worker.current_order_id == HOUSE_ORDER,
			"%s save/load preserves work, shelter, materials and reservation (attempt %d)." % [phase_name, attempt])
		_expect(_house_files(path) == files_before, "%s Continue leaves all files unchanged (attempt %d)." % [phase_name, attempt])
	return true

func _test_home_completion() -> void:
	var base_capacity: int = CityStockManager.shelter_capacity
	var materials: Dictionary = Inventory.items.duplicate(true)
	var home_path: String = test_root.path_join("home.json")
	_select_house_path(home_path)
	content.get_node("YSortWorld/HomeDoor")._on_body_entered(player)
	if not await _wait_scene(store.snapshot.HOME_PATH):
		return
	_expect(is_instance_valid(store.parked_worksite) and house_state.phase == "building", "A building house remains active while the city worksite is parked at home.")
	_expect(store.save_checkpoint(), "The nearly completed house saves from home: " + store.last_error)
	var pending_bytes: PackedByteArray = FileAccess.get_file_as_bytes(home_path)
	TimeComponentManager.advance_minutes(3)
	_expect(house_state.phase == "built" and CityStockManager.shelter_capacity == base_capacity + 3, "House completion while home grants exactly three shelter places.")
	if not await _return_house_to_city():
		return
	_expect(store.load_checkpoint(), "Continue opens the saved home construction checkpoint: " + store.last_error)
	if not await _wait_house_load():
		return
	_expect(house_state.phase == "building" and house_state.completes_at - house_state._latest_time == 3
		and CityStockManager.shelter_capacity == base_capacity and FileAccess.get_file_as_bytes(home_path) == pending_bytes,
		"Home Continue restores the unfinished job and old capacity without rewriting the file.")
	TimeComponentManager.advance_minutes(3)
	_expect(house_state.phase == "built" and CityStockManager.shelter_capacity == base_capacity + 3
		and _same_snapshot(Inventory.items, materials), "The resumed completion grants shelter once without consuming materials again.")
	_expect(store.save_checkpoint(), "The completed house saves at home: " + store.last_error)
	var built_files: Dictionary = _house_files(home_path)
	for attempt: int in range(2):
		if not await _return_house_to_city():
			return
		_expect(store.load_checkpoint(), "A completed home checkpoint loads (attempt %d): " % attempt + store.last_error)
		if not await _wait_house_load():
			return
		_expect(house_state.phase == "built" and CityStockManager.shelter_capacity == base_capacity + 3
			and _same_snapshot(Inventory.items, materials) and _house_files(home_path) == built_files,
			"Repeated built-house Continue preserves shelter and materials without duplicate grants (attempt %d)." % attempt)

func _return_house_to_city() -> bool:
	var home: Node = get_tree().current_scene
	if not store.snapshot.is_home(home):
		_expect(false, "The house test is in the home before returning to the city.")
		return false
	var home_player: Player = home.get_node("YSortWorld/Player")
	home.get_node("YSortWorld/ExitDoor")._on_body_entered(home_player)
	if not await _wait_scene("res://scenes/content_scene/content_scene.tscn"):
		return false
	_bind_city_references()
	return true

func _wait_house_load() -> bool:
	if not await _wait_scene(store.snapshot.HOME_PATH):
		return false
	var deadline: int = Time.get_ticks_msec() + 5000
	while store._busy and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(store.status == "Loaded" and not store._busy, "The home checkpoint handoff completes.")
	return store.status == "Loaded" and not store._busy

func _select_house_path(path: String) -> void:
	store.disk.path = path
	store.refresh_checkpoint_slot()

func _write_house_bytes(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

func _house_files(path: String) -> Dictionary:
	var files: Dictionary = {}
	for suffix: String in ["", ".bak", ".tmp", ".pending"]:
		files[suffix] = FileAccess.get_file_as_bytes(path + suffix) if FileAccess.file_exists(path + suffix) else null
	return files

func _finish_house_test() -> void:
	print("HouseSaveMigrationTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
