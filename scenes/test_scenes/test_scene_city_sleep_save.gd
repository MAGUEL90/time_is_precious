extends "res://scenes/test_scenes/test_scene_city_save_economy.gd"

const SLEEP_SAVE_PATH: String = "user://city_sleep_save_test/checkpoint.json"
const SAVE_STATE: Script = preload("res://scenes/new_scenes/save_game/city_save_state.gd")
const SAVE_VALUES: Script = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const SAVE_WORKSITES: Script = preload("res://scenes/new_scenes/save_game/city_save_worksites.gd")
const LEGACY_RELIABILITY: Script = preload("res://scenes/test_scenes/legacy_reliability_fixture.gd")
const LEGACY_STOCKPILES: Script = preload("res://scenes/content_scene/worksites/legacy_stockpile_layout.gd")
var mode: String = "roundtrip"

func _run() -> void:
	if not _isolated_profile_is_safe():
		_expect(false, "Sleep fixture requires an isolated sibling citysave_suite_qa profile before any checkpoint operations.")
		get_tree().quit(1)
		return
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
	if mode not in ["roundtrip", "write", "read"]:
		_expect(false, "Choose a roundtrip, write, or read sleep fixture phase.")
		get_tree().quit(1)
		return
	if mode == "read":
		_expect(FileAccess.file_exists(SLEEP_SAVE_PATH), "A fresh-process sleep reader requires its isolated writer checkpoint.")
		if failures > 0:
			_finish_sleep_test()
			return
		var files_before_read: Dictionary = _sleep_checkpoint_files()
		await _load_home_checkpoint()
		await _verify_return_to_city()
		_expect(_sleep_checkpoint_files() == files_before_read,
			"Fresh-process sleep Continue and return to city preserve the exact checkpoint and recovery siblings.")
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
	var visuals: Node = runtime.get_node("WorkerVisuals")
	var deadline: int = _clock_minute() + 1800
	while (not runtime.hauling.routes.has(HAULER_ID) or runtime.hauling.routes[HAULER_ID].phase != "outbound") and _clock_minute() < deadline:
		# One game minute is one real second: drive the same frame-based walk
		# that marks physical arrival before advancing the work scheduler.
		for _frame: int in range(20):
			visuals._process(0.05)
		TimeComponentManager.advance_minutes(1)
	var laborer: WorkerData = WorkerDatabase.get_worker_data(LABORER_ID)
	_expect(laborer != null and not laborer.physical_approach.is_empty() and laborer.physical_approach.arrived,
		"The assigned Laborer physically reaches the Wood Site before producing.")
	_expect(runtime.hauling.routes.has(HAULER_ID) and runtime.hauling.routes[HAULER_ID].cargo.quantity == 3, "A real Hauler is carrying three wood logs before the home visit.")
	if runtime.hauling.routes.has(HAULER_ID):
		# Mirror the value-only adapter installed when a pre-v3 save's removed
		# WoodStorage route is restored. Old stockpile deliveries settle into a
		# retained world pile rather than a modern City Storage receipt.
		var legacy_route: Dictionary = runtime.hauling.routes[HAULER_ID]
		var legacy_target: Vector2 = runtime.to_global(LEGACY_STOCKPILES.STOCKPILES["WoodStorage"].position)
		legacy_route.legacy_final = true
		legacy_route.removing = true
		legacy_route.target = legacy_target
		legacy_route.destination_path = NodePath("WoodStorage")
		legacy_route.arrival = int(legacy_route.start) + runtime.hauling._travel_minutes(
			Vector2(legacy_route.origin).distance_to(legacy_target))
		legacy_route.destination = SAVE_WORKSITES.LegacyFinalDestination.new(runtime, legacy_target)
	city_storage.items["stone"] = 20
	city_storage.items["wood_log"] = 5
	var city_stock_before_wall: Dictionary = city_storage.items.duplicate(true)
	Inventory.add_bulk_item({"stone": 10, "wood_log": 5})
	var legacy_route_snapshot: Dictionary = store.snapshot._sites.capture(runtime)
	_expect(not legacy_route_snapshot.is_empty()
		and store.snapshot._sites.validate(legacy_route_snapshot, runtime,
			WorkerDatabase.workers_by_id, WorkerDatabase.dismissed_workers),
		"The simulated legacy final route validates with its removed WoodStorage ID and adapter target before handoff.")
	var wall_quote: Dictionary = state.get_work_quote()
	var wall_started: bool = state.request_wall_work(wall_quote)
	_expect(wall_started and state._work_paid_source == "inventory"
		and int(Inventory.items.get("stone", 0)) == 0 and int(Inventory.items.get("wood_log", 0)) == 0
		and city_storage.items == city_stock_before_wall,
		"Paid wall construction begins from Player Inventory while City Storage remains unchanged.")
	# The original cargo is a legacy trip, but all new Daily work uses the live
	# City's current direct-output destination after the test seeds that trip.
	runtime.daily.jobs[WOOD_SITE].drop = runtime._deliver_daily_output.bind(
		runtime.get_node("WorksiteMarkers/WoodSite"))
	var drop: PickUpItem = preload("res://scenes/pickup_item/pickup_item.tscn").instantiate()
	drop.item_id = "clay_lump"
	drop.quantity = 4
	drop.position = Vector2(-210, -260)
	content.get_node("YSortWorld").add_child(drop)
	# These six legacy views are intentionally disabled in the authored scene.
	# Seed their retained ledgers directly: one refills during sleep and five
	# retain distinct pending timers/slots. This is not an interactive harvest.
	for index: int in range(6):
		var palm: Node = content.get_node("YSortWorld/DatePalmTree" + ("" if index == 0 else str(index + 1)))
		_expect(not palm.world_view_enabled and palm._pickups.is_empty(),
			"Sleep fixture preserves the hidden legacy palm view: " + str(palm.name))
		palm.state._rng.seed = 2000 + index
		palm.state.collect(index % 3)
		palm.state.remaining_minutes = 10 if index == 0 else 1000 - index * 17
	var sources_before_sleep: Dictionary = store.snapshot._sources.capture()
	var original_runtime: Node = runtime
	# Plot changes above defer navigation rebuilding until the next frame.
	for frame: int in range(8):
		if not runtime.navigation_refresh_pending:
			break
		await get_tree().process_frame
	_expect(not runtime.navigation_refresh_pending, "Deferred plot navigation has settled before the home handoff.")
	var before_departure: Dictionary = store.snapshot._sites.capture(runtime)
	_expect(store.prepare_home_departure(content, store.snapshot.HOME_PATH), "The city can prepare a home handoff.")
	_expect(WorkerDatabase.payroll_changed.is_connected(Callable(visuals, "_on_worker_roster_changed")), "The parked visual owner keeps its worker roster connection.")
	store.cancel_home_departure()
	_expect(WorkerDatabase.payroll_changed.is_connected(Callable(visuals, "_on_worker_roster_changed")), "Cancelling the handoff keeps the worker roster connection.")
	_expect(runtime.get_parent() == content.get_node("YSortWorld") and _same_snapshot(before_departure, store.snapshot._sites.capture(runtime)), "A failed scene switch can roll back the handoff without altering any work state.")
	var home_door: Node = content.get_node("YSortWorld/HomeDoor")
	home_door._on_body_entered(player)
	if not await _wait_scene(store.snapshot.HOME_PATH):
		_finish_sleep_test()
		return
	_expect(store.parked_worksite == original_runtime and original_runtime.daily.jobs.has(WOOD_SITE), "Entering home preserves the live daily assignment and hauling scheduler.")
	_expect(CitizenManager.citizen_added.is_connected(Callable(visuals, "_on_resident_changed")) and CitizenManager.citizen_left.is_connected(Callable(visuals, "_on_resident_changed")), "The parked owner reconnects resident signals while away from the city.")
	_expect(original_runtime.hauling.routes[HAULER_ID].cargo.quantity == 3, "The home transition does not discard in-flight cargo.")
	_expect(not FileAccess.file_exists(SLEEP_SAVE_PATH), "Entering home alone does not create a sleep checkpoint.")
	var home: Node = get_tree().current_scene
	player = home.get_node("YSortWorld/Player")
	player.hunger = 0.2
	player.fatigue = 0.7
	player.last_sleep_day = -1
	var sleep_spot: SleepSpot = home.get_node("YSortWorld/SleepSpot")
	player.global_position = sleep_spot.global_position + Vector2(-22, 8)
	for frame: int in range(3):
		await get_tree().physics_frame
	var city_wood_before_sleep: int = int(city_storage.items.get("wood_log", 0))
	var site_wood_before_sleep: int = int(original_runtime.sites[WOOD_SITE].stock)
	var minute_before: int = _clock_minute()
	await sleep_spot.on_player_interact(player)
	_expect(_clock_minute() == minute_before + player.sleep_duration_minutes, "The actual bed advances the existing seven-hour sleep once.")
	_expect(store.status == "Saved" and FileAccess.file_exists(SLEEP_SAVE_PATH), "Successful sleep automatically writes the checkpoint: " + store.last_error)
	if store.status != "Saved":
		_finish_sleep_test()
		return
	_expect(state.wall_hp == 50 and state._work_kind.is_empty(), "Construction advances normally during sleep before saving.")
	_expect(_legacy_wood_pile_total() == 3 and not original_runtime.hauling.routes.has(HAULER_ID),
		"The migrated Hauler completes its one final delivery into the legacy ground pile while the city is offscreen.")
	var city_wood_gained_during_sleep: int = int(city_storage.items.get("wood_log", 0)) - city_wood_before_sleep
	var site_wood_gathered_during_sleep: int = site_wood_before_sleep - int(original_runtime.sites[WOOD_SITE].stock)
	_expect(city_wood_gained_during_sleep > 0 and city_wood_gained_during_sleep == site_wood_gathered_during_sleep,
		"New Daily output transfers from site stock to City Storage exactly once during sleep, apart from the legacy pile.")
	var saved_legacy_wood: int = 0
	for pile: Dictionary in store.snapshot.prepared.worksites.get("legacy_ground", []):
		if str(pile.item_id) == "wood_log":
			saved_legacy_wood += int(pile.quantity)
	_expect(saved_legacy_wood == 3,
		"The home checkpoint serializes the legacy delivery separately from new city-owned Daily output.")
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
	_expect(raw.player.last_sleep_day == TimeComponentManager.current_day and is_equal_approx(raw.player.fatigue, player.fatigue) and is_equal_approx(raw.player.hunger, player.hunger), "The checkpoint includes completed sleep recovery, Hunger and the daily sleep latch.")
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
	var v3_stockpiles: Dictionary = _move_legacy_wood_into_old_stockpile(v3_raw)
	var v3_palms: Dictionary = expected_sources.duplicate(true)
	for record: Dictionary in v3_palms.values():
		record.erase("config")
	v3_raw.erase("pickup_sources")
	v3_raw.date_palms = v3_palms
	v3.schema_version = 3
	_strip_post_v3_owner_fields(v3_raw)
	v3.state = LEGACY_RELIABILITY.encode_city(v3_codec, v3_raw, v3_stockpiles)
	_strip_post_v3_worker_fields(v3.state)
	var v3_file := FileAccess.open(SLEEP_SAVE_PATH, FileAccess.WRITE)
	v3_file.store_string(JSON.stringify(v3, "", true, true))
	v3_file.close()
	_expect(store.load_checkpoint(), "A v3 home checkpoint migrates through the normal handoff.")
	await _wait_scene(store.snapshot.HOME_PATH)
	var v3_deadline: int = Time.get_ticks_msec() + 5000
	while store._busy and Time.get_ticks_msec() < v3_deadline:
		await get_tree().process_frame
	_expect(store.status == "Loaded" and store.snapshot._sources.capture() == expected_sources
		and _worksite_legacy_ground_wood(store.snapshot.prepared.worksites) == 3 and _legacy_wood_pile_total() == 3,
		"v3 home migration preserves all palm state and recovers the retired WoodStorage stock as a pickup-able pile.")
	await _verify_return_to_city()
	# A v2 home file had no palms: exercise fallback through the real home loader.
	var codec = preload("res://scenes/new_scenes/save_game/city_save_values.gd").new()
	var legacy: Dictionary = parsed.duplicate(true)
	var legacy_raw: Dictionary = codec.decode(legacy.state)
	legacy_raw.erase("pickup_sources")
	var legacy_stockpiles: Dictionary = _move_legacy_wood_into_old_stockpile(legacy_raw)
	legacy.schema_version = 2
	_strip_post_v3_owner_fields(legacy_raw)
	legacy.state = LEGACY_RELIABILITY.encode_city(codec, legacy_raw, legacy_stockpiles)
	_strip_post_v3_worker_fields(legacy.state)
	var legacy_file := FileAccess.open(SLEEP_SAVE_PATH, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy, "", true, true))
	legacy_file.close()
	_expect(store.load_checkpoint(), "A legacy v2 home checkpoint loads through the normal handoff.")
	await _wait_scene(store.snapshot.HOME_PATH)
	var legacy_deadline: int = Time.get_ticks_msec() + 5000
	while store._busy and Time.get_ticks_msec() < legacy_deadline:
		await get_tree().process_frame
	_expect(store.status == "Loaded" and not store._busy
		and _worksite_legacy_ground_wood(store.snapshot.prepared.worksites) == 3 and _legacy_wood_pile_total() == 3,
		"Legacy home migration restores the retired WoodStorage logs as a pickup-able pile without replaying sleep.")
	for palm: Dictionary in store.snapshot._sources.capture().values():
		_expect(palm.available == [true, true, true] and palm.remaining_minutes == 0, "Legacy home load initializes full trees with no inferred history.")
	await _verify_return_to_city()
	var migrated_wood: PickUpItem = _find_legacy_wood_pile()
	Inventory.items.clear()
	if is_instance_valid(migrated_wood):
		migrated_wood.on_player_interact(player)
	_expect(is_instance_valid(migrated_wood) and migrated_wood.is_collecting
		and int(Inventory.items.get("wood_log", 0)) == 3,
		"The three wood logs recovered by legacy migration can be picked up into Player Inventory.")
	if is_instance_valid(migrated_wood):
		migrated_wood.on_player_interact(player)
	_expect(int(Inventory.items.get("wood_log", 0)) == 3,
		"A legacy wood pickup cannot be claimed twice during its collection animation.")
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
	var expected_raw: Dictionary = SAVE_VALUES.new().decode(expected.state)
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
	var expected_city_wood: int = int(expected_raw.city_storage.items.get("wood_log", 0))
	var expected_legacy_wood: int = 0
	for pile: Dictionary in expected_raw.worksites.get("legacy_ground", []):
		if str(pile.item_id) == "wood_log":
			expected_legacy_wood += int(pile.quantity)
	_expect(state.wall_hp == 50 and int(city_storage.items.get("wood_log", 0)) == expected_city_wood
		and expected_legacy_wood == 3 and _legacy_wood_pile_total() == 3,
		"A home checkpoint retains the completed wall, direct city output and legacy ground delivery.")
	var actual: Dictionary = JSON.parse_string(JSON.stringify(store.snapshot.capture(get_tree().current_scene), "", true, true))
	_expect(_same_snapshot(expected, actual), "Every owner and the exact home position match the disk checkpoint, including in a fresh process.")

func _verify_return_to_city() -> void:
	var home: Node = get_tree().current_scene
	if not store.snapshot.is_home(home):
		_expect(false, "The return trip begins in the saved home.")
		return
	var before: Dictionary = store.snapshot._sites.capture(store.parked_worksite)
	var palms_before: Dictionary = store.snapshot._sources.capture()
	var inventory_before_return: Dictionary = Inventory.items.duplicate(true)
	var person: Player = home.get_node("YSortWorld/Player")
	home.get_node("YSortWorld/ExitDoor")._on_body_entered(person)
	if not await _wait_scene("res://scenes/content_scene/content_scene.tscn"):
		return
	_bind_city_references()
	_expect(not is_instance_valid(store.parked_worksite), "Returning to city releases the hidden projection after adoption.")
	var city_visuals: Node = runtime.get_node("WorkerVisuals")
	for resident: CitizenData in CitizenManager.get_all_residents():
		_expect(city_visuals.actors.has(resident.citizen_id), "Returning home to the city restores the resident visual for " + resident.citizen_id)
	_expect(_same_snapshot(store.snapshot._sites.capture(runtime), before), "Return to city preserves the offscreen jobs, cargo, resource stock and ground yield.")
	var city_wood: int = int(city_storage.items.get("wood_log", 0))
	var daily_ground_wood: int = runtime._daily_output_count(WOOD_SITE)
	var legacy_ground_wood: int = _legacy_wood_pile_total()
	var site_wood: int = int(runtime.sites[WOOD_SITE].stock)
	var cargo_wood: int = int(runtime.daily.hauling.routes.get(HAULER_ID, {}).get("cargo", {}).get("quantity", 0))
	var conserved_wood: int = city_wood + daily_ground_wood + legacy_ground_wood + site_wood + cargo_wood
	# The fixture adds five logs to storage after gathering begins. Site capacity
	# is a temporary balance parameter, so conserve its configured initial stock.
	var expected_wood: int = int(runtime.sites[WOOD_SITE].deposit_capacity) + 5
	_expect(conserved_wood == expected_wood,
		"Wood balances to %d across City Storage %d, Daily ground %d, legacy ground %d, site %d, and cargo %d."
		% [expected_wood, city_wood, daily_ground_wood, legacy_ground_wood, site_wood, cargo_wood])
	_expect(store.snapshot._sources.capture() == palms_before, "Home/city transition preserves every palm slot, timer and RNG.")
	for index: int in range(6):
		var palm: Node = content.get_node("YSortWorld/DatePalmTree" + ("" if index == 0 else str(index + 1)))
		var slots: Array = palms_before[str(palm.state.name)].available
		_expect(palm.state.available == slots,
			"City return retains the exact hidden palm slot ledger: " + str(palm.name))
		_expect(not palm.world_view_enabled and palm._pickups.is_empty(),
			"City return does not project pickup views for a disabled legacy palm: " + str(palm.name))
	_expect(get_tree().get_nodes_in_group("date_palm_pickups").is_empty()
		and Inventory.items == inventory_before_return,
		"Home/city return creates no legacy palm views and grants no inventory items.")
	var drops: Array = store.snapshot._capture_city_drops(content)
	_expect(drops.size() == 1 and drops[0].item_id == "clay_lump" and drops[0].quantity == 4, "Dropped player items survive the trip home exactly once.")
	ui.open_details()
	ui._select_hub_tab(true)
	await capture_defense("city-shelter-supply.png")
	ui.close_details()

func _legacy_wood_pile_total() -> int:
	var total: int = 0
	var ground: Node = runtime.get_node("GroundOutput")
	for pile: Node in ground.get_children():
		if pile.is_queued_for_deletion() or not bool(pile.get_meta("legacy_stockpile", false)):
			continue
		if str(pile.get("item_id")) == "wood_log":
			total += int(pile.get("quantity"))
	return total


func _find_legacy_wood_pile() -> PickUpItem:
	var ground: Node = runtime.get_node("GroundOutput")
	for pile: Node in ground.get_children():
		if pile is PickUpItem and not pile.is_queued_for_deletion() \
			and bool(pile.get_meta("legacy_stockpile", false)) and str(pile.get("item_id")) == "wood_log":
			return pile as PickUpItem
	return null


func _worksite_legacy_ground_wood(worksites: Dictionary) -> int:
	var total: int = 0
	for pile: Dictionary in worksites.get("legacy_ground", []):
		if str(pile.get("item_id", "")) == "wood_log":
			total += int(pile.get("quantity", 0))
	return total


func _move_legacy_wood_into_old_stockpile(raw: Dictionary) -> Dictionary:
	var worksite: Dictionary = raw.get("worksites", {})
	var retained_ground: Array = []
	var wood_quantity: int = 0
	for pile: Dictionary in worksite.get("legacy_ground", []):
		if str(pile.get("item_id", "")) == "wood_log":
			wood_quantity += int(pile.get("quantity", 0))
		else:
			retained_ground.append(pile.duplicate(true))
	worksite["legacy_ground"] = retained_ground
	if wood_quantity <= 0:
		return {}
	return {"WoodStorage": {"shared": false, "quantity": wood_quantity, "capacity": 96, "accepting": true}}

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

func _sleep_checkpoint_files() -> Dictionary:
	var result: Dictionary = {}
	for suffix: String in ["", ".bak", ".tmp", ".pending"]:
		var path: String = SLEEP_SAVE_PATH + suffix
		result[suffix] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	return result

func _finish_sleep_test() -> void:
	# Fresh-process readers keep the writer's synthetic files for byte checks
	# and a second independent reader. Roundtrip owns its disposable cleanup.
	if mode == "roundtrip":
		_clean_files()
	print("CitySleepSaveTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _strip_post_v3_owner_fields(raw: Dictionary) -> void:
	# Pseudo-legacy documents omit owner fields absent in those schemas.
	raw.player["focus"] = 0.75
	raw.raid.erase("notification_seen_keys")
	for plot: Dictionary in raw.plots.values():
		plot.erase("payroll_work_remainder")
