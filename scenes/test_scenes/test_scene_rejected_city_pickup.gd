extends "res://scenes/test_scenes/test_scene_legacy_walk_pickups.gd"

## Separately exercise the original City Storage delivery that is rejected:
## its final cargo must be physically reachable as a pickup at that endpoint.
const CITY_DIR: String = "user://rejected_city_pickup_test"
const CITY_SAVE: String = CITY_DIR + "/checkpoint.json"
const CITY_SOURCE: String = "res://scenes/test_scenes/fixtures/legacy_stockpile_v12/city_outbound.json.gz"
const CITY_SHA256: String = "b3eafccbbcd2e212bde5d415c3b00c442e8852347fcc713cb009fa25c283dd2b"
const HAULER_ID: String = "initial_worksite_hauler"

func _run() -> void:
	if OS.get_name() == "Linux":
		var data_root: String = OS.get_environment("XDG_DATA_HOME")
		var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
		_expect(not data_root.is_empty() and data_root.is_absolute_path()
			and user_root.begins_with(data_root.simplify_path().trim_suffix("/") + "/"), "Use an isolated absolute XDG_DATA_HOME.")
	var source: PackedByteArray = FileAccess.get_file_as_bytes(CITY_SOURCE).decompress_dynamic(1000000, FileAccess.COMPRESSION_GZIP)
	_expect(not source.is_empty() and _sha256(source) == CITY_SHA256, "The synthetic city-outbound checkpoint has the expected v12 hash.")
	for suffix: String in ["", ".bak", ".tmp", ".pending"]:
		_expect(not FileAccess.file_exists(CITY_SAVE + suffix), "Refuse to overwrite an existing isolated checkpoint.")
	if stopped:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CITY_DIR))
	var file := FileAccess.open(CITY_SAVE, FileAccess.WRITE)
	_expect(file != null, "The isolated city-outbound checkpoint can be created.")
	if stopped:
		return
	file.store_buffer(source)
	file.close()
	get_tree().current_scene = null
	get_tree().paused = false
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = CITY_SAVE
	menu.session_started.connect(func(from_save: bool):
		loaded_from_menu = from_save
		launched = true)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _frames()
	await press(menu.continue_button)
	for _frame: int in range(1200):
		if launched or stopped:
			break
		await get_tree().process_frame
	_expect(launched and loaded_from_menu, "The real Start Menu loads the legacy City Storage delivery.")
	if stopped:
		return
	bind_map()
	store = WorkStateRuntime.get_node("CitySave")
	city_tools = WorkStateRuntime.get_node("CityToolStorage")
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	_expect(FileAccess.get_file_as_bytes(CITY_SAVE) == source, "Continue leaves the old checkpoint unchanged.")
	var destination: StorageDestination = runtime.get_node("CityStorageArea/DeliveryPoint")
	var route: Dictionary = runtime.hauling.routes.get(HAULER_ID, {})
	_expect(not route.is_empty() and route.phase == "outbound" and bool(route.get("legacy_final", false))
		and int(route.cargo.quantity) == 3, "The legacy outbound route owns exactly three logs.")
	if stopped:
		return
	var target: Vector2 = route.target
	var city_before: Dictionary = _city_state()
	var ground_before: int = _ground_count("wood_log")
	var inventory_before: int = int(Inventory.items.get("wood_log", 0))
	var xp_before: int = WorkerDatabase.get_worker_data(HAULER_ID).profession_xp
	destination.accepting_deliveries = false
	_expect(TimeComponentManager.advance_minutes(maxi(1, int(route.arrival) - now())), "The last shipment reaches the deliberately rejecting City Storage.")
	destination.accepting_deliveries = true
	_expect(_ground_count("wood_log") == ground_before + 3, "The rejected cargo appears once on the ground.")
	_assert_city_unchanged(city_before, "after rejected delivery")
	_expect(WorkerDatabase.get_worker_data(HAULER_ID).profession_xp == xp_before, "A rejected delivery grants no receipt XP.")
	var pile: PickUpItem
	for child: Node in runtime.get_node("GroundOutput").get_children():
		if child is PickUpItem and not child.is_queued_for_deletion() and not child.is_collecting \
			and child.item_id == "wood_log" and bool(child.get_meta("legacy_stockpile", false)) \
			and child.global_position.is_equal_approx(target):
			pile = child as PickUpItem
			break
	_expect(is_instance_valid(pile) and pile.quantity == 3, "The three-log fallback is located at the original DeliveryPoint.")
	if stopped:
		return
	print("RejectedCityPickup world=", pile.global_position, " player=", player.global_position,
		" clear=", runtime.worksite_navigation.is_clear(pile.global_position),
		" closest=", runtime.worksite_navigation.reachable_point(player.global_position + Vector2(0, -4), pile.global_position))
	await _walk_to_pickup(pile, "rejected City Storage cargo")
	if stopped:
		return
	await _take_full_pile(pile, "wood_log")
	_expect(int(Inventory.items.get("wood_log", 0)) == inventory_before + 3 and _ground_count("wood_log") == ground_before,
		"The player picks up the rejected cargo exactly once via E.")
	_assert_city_unchanged(city_before, "after player pickup")
	if stopped:
		return
	_expect(store.save_checkpoint(), "Save after the rejected cargo pickup: " + store.last_error)
	_expect(FileAccess.get_file_as_bytes(CITY_SAVE + ".bak") == source, "The original v12 checkpoint remains in the normal backup.")
	if stopped:
		return
	print("RejectedCityPickupTest: PASS")
	get_tree().quit(0)
