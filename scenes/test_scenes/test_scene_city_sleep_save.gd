extends "res://scenes/test_scenes/test_scene_city_save_economy.gd"

const SLEEP_SAVE_PATH: String = "user://city_sleep_save_test/checkpoint.json"
const SAVE_STATE: Script = preload("res://scenes/new_scenes/save_game/city_save_state.gd")
const SAVE_VALUES: Script = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
var mode: String = "roundtrip"

func _run() -> void:
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	_reset_singletons_before_load()
	await _load_root_city()
	store.disk.path = SLEEP_SAVE_PATH
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--sleep-save-phase="):
			mode = argument.trim_prefix("--sleep-save-phase=")
	if mode == "read":
		await _load_home_checkpoint()
		await _verify_return_to_city()
		_finish_sleep_test()
		return
	_clean_files()
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	_prepare_city_state()
	if not _hire_and_assign_team():
		_finish_sleep_test()
		return
	_settle_needs()
	var deadline: int = _clock_minute() + 1800
	while (not runtime.hauling.routes.has(HAULER_ID) or runtime.hauling.routes[HAULER_ID].phase != "outbound") and _clock_minute() < deadline:
		TimeComponentManager.advance_minutes(1)
	_expect(runtime.hauling.routes.has(HAULER_ID) and runtime.hauling.routes[HAULER_ID].cargo.quantity == 3, "A real Hauler is carrying three wood logs before the home visit.")
	city_storage.items["stone"] = 20
	city_storage.items["wood_log"] = 5
	_expect(state.request_wall_work(state.get_work_quote()), "Paid wall construction begins before sleep.")
	var drop: PickUpItem = preload("res://scenes/pickup_item/pickup_item.tscn").instantiate()
	drop.item_id = "clay_lump"
	drop.quantity = 4
	drop.position = Vector2(-210, -260)
	content.get_node("YSortWorld").add_child(drop)
	# One tree refills during sleep; five retain distinct pending timers/slots.
	for index: int in range(6):
		var palm: Node = content.get_node("YSortWorld/DatePalmTree" + ("" if index == 0 else str(index + 1)))
		palm.state._rng.seed = 2000 + index
		palm.state.collect(index % 3)
		palm.state.remaining_minutes = 10 if index == 0 else 1000 - index * 17
	var sources_before_sleep: Dictionary = store.snapshot._sources.capture()
	var original_runtime: Node = runtime
	var before_departure: Dictionary = store.snapshot._sites.capture(runtime)
	_expect(store.prepare_home_departure(content, store.snapshot.HOME_PATH), "The city can prepare a home handoff.")
	store.cancel_home_departure()
	_expect(runtime.get_parent() == content.get_node("YSortWorld") and _same_snapshot(before_departure, store.snapshot._sites.capture(runtime)), "A failed scene switch can roll back the handoff without altering any work state.")
	var home_door: Node = content.get_node("YSortWorld/HomeDoor")
	home_door._on_body_entered(player)
	if not await _wait_scene(store.snapshot.HOME_PATH):
		_finish_sleep_test()
		return
	_expect(store.parked_worksite == original_runtime and original_runtime.daily.jobs.has(WOOD_SITE), "Entering home preserves the live daily assignment and hauling scheduler.")
	_expect(original_runtime.hauling.routes[HAULER_ID].cargo.quantity == 3, "The home transition does not discard in-flight cargo.")
	_expect(not FileAccess.file_exists(SLEEP_SAVE_PATH), "Entering home alone does not create a sleep checkpoint.")
	var home: Node = get_tree().current_scene
	player = home.get_node("YSortWorld/Player")
	player.hunger = 0.2
	player.focus = 0.8
	player.fatigue = 0.7
	player.last_sleep_day = -1
	var sleep_spot: SleepSpot = home.get_node("YSortWorld/SleepSpot")
	player.global_position = sleep_spot.global_position + Vector2(-22, 8)
	for frame: int in range(3):
		await get_tree().physics_frame
	var minute_before: int = _clock_minute()
	await sleep_spot.on_player_interact(player)
	_expect(_clock_minute() == minute_before + player.sleep_duration_minutes, "The actual bed advances the existing seven-hour sleep once.")
	_expect(store.status == "Saved" and FileAccess.file_exists(SLEEP_SAVE_PATH), "Successful sleep automatically writes the checkpoint: " + store.last_error)
	if store.status != "Saved":
		_finish_sleep_test()
		return
	_expect(state.wall_hp == 50 and state._work_kind.is_empty(), "Construction advances normally during sleep before saving.")
	_expect(city_storage.items.get("wood_log", 0) == 3 and original_runtime.hauling.routes[HAULER_ID].cargo.quantity == 0, "The Hauler completes delivery while the city is offscreen.")
	_expect(original_runtime._daily_output_count(WOOD_SITE) > 0, "Assigned workers continue producing during the real sleep time skip.")
	var saved: String = FileAccess.get_file_as_string(SLEEP_SAVE_PATH)
	var parsed: Dictionary = JSON.parse_string(saved)
	_expect(parsed.schema_version == SAVE_STATE.VERSION and parsed.location == "home", "Sleep checkpoints record the current schema and home location explicitly.")
	var raw: Dictionary = store.snapshot.prepared
	var current_sources: Dictionary = raw.pickup_sources
	for id: String in sources_before_sleep:
		var old: Dictionary = sources_before_sleep[id]
		var current: Dictionary = current_sources[id]
		var remaining: int = old.remaining_minutes
		var expected_available: Array = old.available
		if old.config.refill_enabled:
			remaining = maxi(0, old.remaining_minutes - player.sleep_duration_minutes)
			if remaining == 0:
				expected_available = []
				expected_available.resize(old.config.capacity)
				expected_available.fill(true)
		_expect(current.remaining_minutes == remaining, "Sleep saves the exact elapsed refill minutes: " + id)
		_expect(current.available == expected_available, "Sleep refills only sources whose authored timer expires: " + id)
		_expect(current.rng == old.rng, "Sleep/refill does not consume new pickup-source RNG draws: " + id)
		_expect(current.config == old.config, "Sleep preserves each pickup source's authored configuration: " + id)
	_expect(raw.player.last_sleep_day == TimeComponentManager.current_day and is_equal_approx(raw.player.focus, player.focus), "The checkpoint includes completed sleep recovery and the daily sleep latch.")
	_expect(sleep_spot._save_feedback.visible and sleep_spot._save_feedback.text == "Game saved", "Successful sleep gives visible save feedback in the existing pixel font.")
	await capture_defense("sleep-save-home.png")
	await sleep_spot.on_player_interact(player)
	_expect(FileAccess.get_file_as_string(SLEEP_SAVE_PATH) == saved and _clock_minute() == minute_before + player.sleep_duration_minutes, "A refused second sleep neither rewrites the file nor advances time.")
	if mode == "write":
		_finish_sleep_test()
		return
	await _verify_return_to_city()
	Inventory.items.clear()
	state.wall_hp = 1
	await _load_home_checkpoint()
	var restored: Dictionary = JSON.parse_string(JSON.stringify(store.snapshot.capture(get_tree().current_scene), "", true, true))
	_expect(_same_snapshot(restored, parsed), "Loading returns every saved owner, stock, job, clock and home position without repeating sleep.")
	await _verify_return_to_city()
	# Version 3 home checkpoints retain the exact palm state through migration.
	var v3_codec = preload("res://scenes/new_scenes/save_game/city_save_values.gd").new()
	var v3: Dictionary = parsed.duplicate(true)
	var v3_raw: Dictionary = v3_codec.decode(v3.state)
	var expected_sources: Dictionary = v3_raw.pickup_sources.duplicate(true)
	var v3_palms: Dictionary = expected_sources.duplicate(true)
	for record: Dictionary in v3_palms.values():
		record.erase("config")
	v3_raw.erase("pickup_sources")
	v3_raw.date_palms = v3_palms
	v3.schema_version = 3
	_strip_post_v3_owner_fields(v3_raw)
	v3.state = v3_codec.encode(v3_raw)
	_strip_post_v3_worker_fields(v3.state)
	var v3_file := FileAccess.open(SLEEP_SAVE_PATH, FileAccess.WRITE)
	v3_file.store_string(JSON.stringify(v3, "", true, true))
	v3_file.close()
	_expect(store.load_checkpoint(), "A v3 home checkpoint migrates through the normal handoff.")
	await _wait_scene(store.snapshot.HOME_PATH)
	var v3_deadline: int = Time.get_ticks_msec() + 5000
	while store._busy and Time.get_ticks_msec() < v3_deadline:
		await get_tree().process_frame
	_expect(store.status == "Loaded" and store.snapshot._sources.capture() == expected_sources, "v3 home migration preserves all palm slots, timers and RNG.")
	await _verify_return_to_city()
	# A v2 home file had no palms: exercise fallback through the real home loader.
	var codec = preload("res://scenes/new_scenes/save_game/city_save_values.gd").new()
	var legacy: Dictionary = parsed.duplicate(true)
	var legacy_raw: Dictionary = codec.decode(legacy.state)
	legacy_raw.erase("pickup_sources")
	legacy.schema_version = 2
	_strip_post_v3_owner_fields(legacy_raw)
	legacy.state = codec.encode(legacy_raw)
	_strip_post_v3_worker_fields(legacy.state)
	var legacy_file := FileAccess.open(SLEEP_SAVE_PATH, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy, "", true, true))
	legacy_file.close()
	_expect(store.load_checkpoint(), "A legacy v2 home checkpoint loads through the normal handoff.")
	await _wait_scene(store.snapshot.HOME_PATH)
	var legacy_deadline: int = Time.get_ticks_msec() + 5000
	while store._busy and Time.get_ticks_msec() < legacy_deadline:
		await get_tree().process_frame
	_expect(store.status == "Loaded" and not store._busy, "Legacy home load completes without replaying sleep.")
	for palm: Dictionary in store.snapshot._sources.capture().values():
		_expect(palm.available == [true, true, true] and palm.remaining_minutes == 0, "Legacy home load initializes full trees with no inferred history.")
	await _verify_return_to_city()
	# A blocked sleep-save must not destroy an existing corrupt checkpoint.
	var file := FileAccess.open(SLEEP_SAVE_PATH, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	_expect(not store.save_checkpoint() and FileAccess.get_file_as_string(SLEEP_SAVE_PATH) == "{broken", "Autosave shares the existing corrupt-file preservation boundary.")
	_finish_sleep_test()

func _strip_post_v3_worker_fields(value: Variant) -> void:
	if value is Dictionary:
		if value.get("$type") == "object" and value.get("class") == "WorkerData":
			for field: String in SAVE_VALUES.PAYROLL_FIELDS + SAVE_VALUES.CONTRACT_FIELDS + ["physical_approach"]:
				value.fields.erase(field)
		for child: Variant in value.values():
			_strip_post_v3_worker_fields(child)
	elif value is Array:
		for child: Variant in value:
			_strip_post_v3_worker_fields(child)

func _load_root_city() -> void:
	content = CONTENT_SCENE.instantiate()
	get_tree().root.add_child(content)
	get_tree().current_scene = content
	for frame: int in range(3):
		await get_tree().process_frame
	_bind_city_references()

func _bind_city_references() -> void:
	content = get_tree().current_scene
	player = content.get_node("YSortWorld/Player")
	state = WorkStateRuntime.get_node("CityRaid")
	ui = state.get_node("RaidUI")
	storage = state.storage
	city_storage = storage
	store = WorkStateRuntime.get_node("CitySave")
	runtime = content.get_node("YSortWorld/WorkerRuntime")
	wood_storage = runtime.get_node("CityStorageArea/DeliveryPoint")

func _load_home_checkpoint() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SLEEP_SAVE_PATH))
	_expect(store.load_checkpoint(), "Load accepts the sleep checkpoint: " + store.last_error)
	_expect(not TimeComponentManager.is_processing() and not state.is_processing(), "A home Load freezes clock and raid processing before its deferred fade.")
	if not await _wait_scene(store.snapshot.HOME_PATH):
		return
	var deadline: int = Time.get_ticks_msec() + 5000
	while store._busy and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(store.status == "Loaded" and not store._busy, "The saved home opens and the load transition completes.")
	var home_player: Player = get_tree().current_scene.get_node("YSortWorld/Player")
	_expect(home_player.can_move and not home_player.is_sleeping and not home_player.can_sleep(), "Load returns an awake player and cannot repeat the saved day's sleep.")
	_expect(state.wall_hp == 50 and city_storage.items.get("wood_log", 0) == 3, "A home checkpoint retains the completed wall and delivered cargo.")
	var actual: Dictionary = JSON.parse_string(JSON.stringify(store.snapshot.capture(get_tree().current_scene), "", true, true))
	_expect(_same_snapshot(expected, actual), "Every owner and the exact home position match the disk checkpoint, including in a fresh process.")

func _verify_return_to_city() -> void:
	var home: Node = get_tree().current_scene
	if not store.snapshot.is_home(home):
		_expect(false, "The return trip begins in the saved home.")
		return
	var before: Dictionary = store.snapshot._sites.capture(store.parked_worksite)
	var palms_before: Dictionary = store.snapshot._sources.capture()
	var person: Player = home.get_node("YSortWorld/Player")
	home.get_node("YSortWorld/ExitDoor")._on_body_entered(person)
	if not await _wait_scene("res://scenes/content_scene/content_scene.tscn"):
		return
	_bind_city_references()
	_expect(not is_instance_valid(store.parked_worksite), "Returning to city releases the hidden projection after adoption.")
	_expect(_same_snapshot(store.snapshot._sites.capture(runtime), before), "Return to city preserves the offscreen jobs, cargo, resource stock and ground yield.")
	_expect(_wood_total() == 72, "All wood remains conserved across sleep and both scene transitions.")
	_expect(store.snapshot._sources.capture() == palms_before, "Home/city transition preserves every palm slot, timer and RNG.")
	var view_count: int = 0
	for index: int in range(6):
		var palm: Node = content.get_node("YSortWorld/DatePalmTree" + ("" if index == 0 else str(index + 1)))
		var slots: Array = palms_before[str(palm.state.name)].available
		view_count += slots.count(true)
		for slot: int in range(slots.size()):
			_expect(palm._pickups.has(slot) == slots[slot], "City return recreates only the saved available slot for " + str(palm.name))
	_expect(get_tree().get_nodes_in_group("date_palm_pickups").size() == view_count, "Home/city return creates no extra palm views or personal drops.")
	var drops: Array = store.snapshot._capture_city_drops(content)
	_expect(drops.size() == 1 and drops[0].item_id == "clay_lump" and drops[0].quantity == 4, "Dropped player items survive the trip home exactly once.")
	ui.open_details()
	ui._select_hub_tab(true)
	await capture_defense("city-shelter-supply.png")
	ui.close_details()

func _wait_scene(path: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == path and not SceneTransition.is_transitioning:
			for frame: int in range(2):
				await get_tree().process_frame
			return true
		await get_tree().process_frame
	_expect(false, "The scene transition completes: " + path)
	return false

func _clean_files() -> void:
	for suffix: String in ["", ".bak", ".tmp", ".pending"]:
		if FileAccess.file_exists(SLEEP_SAVE_PATH + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SLEEP_SAVE_PATH + suffix))

func _finish_sleep_test() -> void:
	if mode != "write":
		_clean_files()
	print("CitySleepSaveTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _strip_post_v3_owner_fields(raw: Dictionary) -> void:
	# Pseudo-legacy documents omit owner fields absent in those schemas.
	raw.raid.erase("notification_seen_keys")
	for plot: Dictionary in raw.plots.values():
		plot.erase("payroll_work_remainder")
