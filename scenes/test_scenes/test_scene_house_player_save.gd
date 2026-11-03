extends "res://scenes/test_scenes/test_scene_house_save_migration.gd"

## Isolated disk checkpoint for manual house work. The gameplay UI tests own
## input, session duration, collapse and animation; this checks save ownership.
func _run() -> void:
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	_reset_singletons_before_load()
	await _load_root_city()
	_prepare_city_state()
	if not _hire_and_assign_team():
		_finish_player_save_test()
		return
	_settle_needs()
	house_state = content.get_node("YSortWorld/CitizenHousePlot").construction
	Inventory.max_load = 1000.0
	Inventory.add_item("wood_log", 11)
	Inventory.add_item("clay_lump", 13)
	Inventory.add_item("reed_bundle", 9)
	player.debug_disable_player_needs = false
	player.debug_disable_fatigue = false
	player.fatigue = 0.10
	player.hunger = 0.10
	WorkerDatabase.get_worker_data(PRODUCTION_ID).profession_xp = 17
	_select_house_path(test_root.path_join("player_house.json"))
	var baseline: Dictionary = store.snapshot.capture(content)
	_expect(store.snapshot.VERSION == 14 and store.snapshot.prepare(baseline, content),
		"The current world validates before the player begins work.")
	var values = MIGRATION_VALUES.new()
	var legacy: Dictionary = baseline.duplicate(true)
	legacy.schema_version = 11
	legacy.state = MIGRATION_FIXTURE.encode_v11(values, values.decode(baseline.state))
	_expect(store.snapshot.prepare(legacy, content) and _same_snapshot(baseline, store.snapshot.capture(content)),
		"A v11 control still prepares without mutating the live world.")
	_expect(store.save_checkpoint(), "An initial checkpoint saves before player work: " + store.last_error)
	var initial_bytes: PackedByteArray = FileAccess.get_file_as_bytes(store.disk.path)
	if not _test_player_cleaning(initial_bytes):
		_finish_player_save_test()
		return
	if not _test_player_building():
		_finish_player_save_test()
		return
	_test_worker_replacement()
	_finish_player_save_test()


func _test_player_cleaning(initial_bytes: PackedByteArray) -> bool:
	var original_items: Dictionary = Inventory.items.duplicate(true)
	var before_fatigue: float = player.fatigue
	var before_hunger: float = player.hunger
	var result: Dictionary = house_state.start_clearing([] as Array[String], true)
	_expect(bool(result.get("success", false)) and house_state.is_player_work_active(),
		"Player cleaning starts through the house state.")
	if not bool(result.get("success", false)):
		return false
	_expect(not store.save_checkpoint() and FileAccess.get_file_as_bytes(store.disk.path) == initial_bytes,
		"Saving is refused during player cleaning without touching the prior checkpoint.")
	_expect(TimeComponentManager.advance_minutes(7), "Seven actual manual-cleaning minutes advance.")
	_expect(is_equal_approx(player.fatigue, before_fatigue + 7.0 * player.fatigue_increase_per_min)
		and is_equal_approx(player.hunger, before_hunger + 7.0 * player.hunger_increase_per_min),
		"The real clock applies Energy and Belly changes once during player cleaning.")
	house_state.interrupt_player_work()
	_expect(not house_state.is_player_work_active() and house_state.phase == "uncleared"
		and house_state.clearing_remaining == house_state.CLEARING_MINUTES - 7
		and _same_snapshot(Inventory.items, original_items),
		"Interrupted cleaning retains its exact remainder without consuming materials.")
	if house_state.phase != "uncleared":
		return false
	var paused_fatigue: float = player.fatigue
	var paused_hunger: float = player.hunger
	_expect(store.save_checkpoint(), "Interrupted cleaning saves: " + store.last_error)
	var clean_files: Dictionary = _house_files(store.disk.path)
	for attempt: int in range(2):
		_expect(store.load_checkpoint(), "Interrupted cleaning Continues: " + store.last_error)
		_expect(not house_state.is_player_work_active() and house_state.clearing_remaining == house_state.CLEARING_MINUTES - 7
			and is_equal_approx(player.fatigue, paused_fatigue) and is_equal_approx(player.hunger, paused_hunger)
			and _same_snapshot(Inventory.items, original_items) and _house_files(store.disk.path) == clean_files,
			"Repeated Continue keeps cleaning, needs, materials and checkpoint files unchanged.")
	# A worker can take over the player's interrupted clearing, and the player
	# can take over again if that worker resigns. Reload the earlier save after
	# the probe so the paid worker remains available for the later build test.
	result = house_state.start_clearing([PRODUCTION_ID] as Array[String], false)
	_expect(bool(result.get("success", false)) and _arrive_at_house("clearing"),
		"A paid worker takes over the player's partially cleared site.")
	if not bool(result.get("success", false)):
		return false
	_expect(TimeComponentManager.advance_minutes(5) and house_state._remaining_work_units() == house_state.CLEARING_MINUTES - 12,
		"The worker continues from the player's exact remaining clearing work.")
	var worker: WorkerData = WorkerDatabase.get_worker_data(PRODUCTION_ID)
	worker.get_linked_citizen().satisfaction = 0.0
	WorkerDatabase.resign_idle_workers_at_zero()
	_expect(house_state.phase == "clearing" and house_state.worker_ids.is_empty()
		and house_state._remaining_work_units() == house_state.CLEARING_MINUTES - 12,
		"Worker resignation preserves partially cleared progress for another participant.")
	result = house_state.resume_player_work()
	_expect(bool(result.get("success", false)) and TimeComponentManager.advance_minutes(3),
		"The player can take over clearing after a worker resigns.")
	house_state.interrupt_player_work()
	_expect(house_state.phase == "uncleared" and house_state.clearing_remaining == house_state.CLEARING_MINUTES - 15
		and _same_snapshot(Inventory.items, original_items), "Player interruption preserves the shared clearing progress.")
	_expect(store.load_checkpoint() and _house_files(store.disk.path) == clean_files,
		"Reloading the earlier save restores its worker and exact checkpoint bytes.")
	result = house_state.start_clearing([] as Array[String], true)
	_expect(bool(result.get("success", false)), "Player resumes interrupted cleaning without a new material charge.")
	if not bool(result.get("success", false)):
		return false
	_expect(TimeComponentManager.advance_minutes(house_state.clearing_remaining), "The remaining manual cleaning time advances.")
	_expect(house_state.phase == "empty" and not house_state.is_player_work_active()
		and _same_snapshot(Inventory.items, original_items), "Cleaning finishes without charging materials.")
	return house_state.phase == "empty"


func _test_player_building() -> bool:
	var before_items: Dictionary = Inventory.items.duplicate(true)
	var before_shelter: int = CityStockManager.shelter_capacity
	var result: Dictionary = house_state.start_build([] as Array[String], true)
	_expect(bool(result.get("success", false)) and house_state.phase == "building"
		and house_state.is_player_work_active() and house_state.worker_ids.is_empty(),
		"The player starts the paid-material house build without a worker reservation.")
	if not bool(result.get("success", false)):
		return false
	var paid_items: Dictionary = Inventory.items.duplicate(true)
	for id: String in house_state.get_requirements():
		_expect(int(before_items.get(id, 0)) - int(paid_items.get(id, 0)) == int(house_state.get_requirements()[id]),
			"Player construction consumes %s exactly once." % id)
	var files_before: Dictionary = _house_files(store.disk.path)
	_expect(not store.save_checkpoint() and not store.load_checkpoint() and _house_files(store.disk.path) == files_before,
		"Save and Continue both refuse an active player build without touching the files.")
	var before_work: int = house_state._remaining_work_units()
	var fatigue_before: float = player.fatigue
	var hunger_before: float = player.hunger
	_expect(TimeComponentManager.advance_minutes(13), "Thirteen player-building minutes advance.")
	_expect(house_state._remaining_work_units() == before_work - 13
		and is_equal_approx(player.fatigue, fatigue_before + 13.0 * player.fatigue_increase_per_min)
		and is_equal_approx(player.hunger, hunger_before + 13.0 * player.hunger_increase_per_min),
		"The house records elapsed manual work and charges normal clock needs once.")
	house_state.interrupt_player_work()
	var remaining: int = house_state._remaining_work_units()
	var fatigue: float = player.fatigue
	var hunger: float = player.hunger
	_expect(not house_state.is_player_work_active() and house_state.phase == "building"
		and house_state.worker_ids.is_empty() and remaining == before_work - 13
		and house_state.get_replacement_slots() >= 1 and _same_snapshot(Inventory.items, paid_items),
		"An interrupted build remains paid, workerless and available for replacement.")
	_expect(store.save_checkpoint(), "The interrupted build saves: " + store.last_error)
	var paused_files: Dictionary = _house_files(store.disk.path)
	for attempt: int in range(2):
		_expect(store.load_checkpoint(), "The paused player build Continues: " + store.last_error)
		var saved_worker: WorkerData = WorkerDatabase.get_worker_data(PRODUCTION_ID)
		_expect(not house_state.is_player_work_active() and house_state.phase == "building"
			and house_state._remaining_work_units() == remaining and _same_snapshot(Inventory.items, paid_items)
			and is_equal_approx(player.fatigue, fatigue) and is_equal_approx(player.hunger, hunger)
			and saved_worker != null and saved_worker.profession_xp == 17
			and CityStockManager.shelter_capacity == before_shelter and _house_files(store.disk.path) == paused_files,
			"Repeated Continue preserves progress, needs, material, worker and shelter without file changes.")
	_expect(TimeComponentManager.advance_minutes(8), "Time passes while the player build is paused.")
	_expect(house_state._remaining_work_units() == remaining and CityStockManager.shelter_capacity == before_shelter,
		"A paused player build never advances simply because time passes.")
	result = house_state.resume_player_work()
	_expect(bool(result.get("success", false)) and house_state.is_player_work_active(),
		"The player can resume the existing paid build.")
	if not bool(result.get("success", false)):
		return false
	_expect(TimeComponentManager.advance_minutes(31), "A second player session advances 31 minutes.")
	house_state.interrupt_player_work()
	_expect(not house_state.is_player_work_active() and house_state._remaining_work_units() == remaining - 31
		and _same_snapshot(Inventory.items, paid_items) and CityStockManager.shelter_capacity == before_shelter,
		"Player resumption preserves prior progress and never charges the materials twice.")
	return house_state.phase == "building" and not house_state.is_player_work_active()


func _test_worker_replacement() -> void:
	var before_items: Dictionary = Inventory.items.duplicate(true)
	var before_shelter: int = CityStockManager.shelter_capacity
	var remaining: int = house_state._remaining_work_units()
	var ids: Array[String] = [PRODUCTION_ID]
	var result: Dictionary = house_state.add_replacement_workers(ids)
	_expect(bool(result.get("success", false)) and house_state._remaining_work_units() == remaining
		and _same_snapshot(Inventory.items, before_items),
		"A hired replacement takes over the player's paid work without another charge.")
	if not bool(result.get("success", false)) or not _arrive_at_house("building"):
		return
	_expect(TimeComponentManager.advance_minutes(1) and house_state._remaining_work_units() == remaining - 1,
		"The arrived replacement adds exactly one shift minute to the shared progress.")
	remaining = house_state._remaining_work_units()
	_expect(store.save_checkpoint(), "The replacement-worker state saves: " + store.last_error)
	var worker_files: Dictionary = _house_files(store.disk.path)
	for attempt: int in range(2):
		_expect(store.load_checkpoint(), "The worker replacement Continues: " + store.last_error)
		var worker: WorkerData = WorkerDatabase.get_worker_data(PRODUCTION_ID)
		_expect(house_state._remaining_work_units() == remaining and house_state.worker_ids == ids
			and worker != null and worker.current_order_id == HOUSE_ORDER
			and _same_snapshot(Inventory.items, before_items) and CityStockManager.shelter_capacity == before_shelter
			and _house_files(store.disk.path) == worker_files,
			"Worker Continue preserves reservation, progress and material without duplicate shelter.")
	# After validating the real partial state, stage the last minute to check the
	# production completion boundary without running the remaining 2,800+ minutes.
	house_state.completes_at = house_state._latest_time + 1
	house_state.payroll_work_remainder = 0
	_expect(TimeComponentManager.advance_minutes(1), "The staged final worker minute advances.")
	_expect(house_state.phase == "built" and CityStockManager.shelter_capacity == before_shelter + 3
		and _same_snapshot(Inventory.items, before_items), "The house grants three shelter places once.")
	for repeat: int in range(3):
		house_state.changed.emit()
	TimeComponentManager.emit_time_signal()
	_expect(CityStockManager.shelter_capacity == before_shelter + 3, "Repeated callbacks do not duplicate shelter.")
	_expect(store.save_checkpoint(), "The completed house saves: " + store.last_error)
	var built_files: Dictionary = _house_files(store.disk.path)
	for attempt: int in range(2):
		_expect(store.load_checkpoint(), "The completed house Continues: " + store.last_error)
		_expect(house_state.phase == "built" and CityStockManager.shelter_capacity == before_shelter + 3
			and _same_snapshot(Inventory.items, before_items) and _house_files(store.disk.path) == built_files,
			"Repeated built-house Continue does not regrant shelter or alter files.")


func _finish_player_save_test() -> void:
	print("HousePlayerSaveTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
