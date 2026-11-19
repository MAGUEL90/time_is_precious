extends "res://scenes/test_scenes/mvp_first_playthrough.gd"

## Two-process end-to-end check of the five migrated stockpiles. Uses the
## synthetic v12 checkpoint, actual Start Menu, movement, focus and E input.
## During the water pickup only, the bag limit is reduced in this test to
## exercise a partial pickup and full-bag retry; it is restored before Save.
const FLOW_DIR: String = "user://legacy_walk_pickups_test"
const FLOW_SAVE: String = FLOW_DIR + "/checkpoint.json"
const FLOW_EVIDENCE: String = FLOW_DIR + "/evidence.json"
const STOCKED_SOURCE: String = "res://scenes/test_scenes/fixtures/legacy_stockpile_v12/stocked.json.gz"
const STOCKED_SHA256: String = "61493082ed3e6af4f9c3a01185ed8681bccfbcb0ea199ff77dcc3b3346460ce2"
const ITEM_ORDER: Array[String] = ["clay_lump", "wood_log", "reed_bundle", "straw_bundle", "water_jar"]
const LEGACY_COUNTS: Dictionary = {"clay_lump": 4, "wood_log": 5, "reed_bundle": 6, "straw_bundle": 7, "water_jar": 8}
const ORIGINAL_GROUND: Dictionary = {"clay_lump": 6, "wood_log": 10, "reed_bundle": 6, "straw_bundle": 7, "water_jar": 8}

var store: Node
var city_tools: Node
var loaded_from_menu: bool = false
var initial_city: Dictionary = {}
var initial_totals: Dictionary = {}

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--legacy-walk-phase="):
			phase = argument.trim_prefix("--legacy-walk-phase=")
	_expect(phase in ["write", "read"], "Choose --legacy-walk-phase=write or read.")
	if OS.get_name() == "Linux":
		var data_root: String = OS.get_environment("XDG_DATA_HOME")
		var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
		_expect(not data_root.is_empty() and data_root.is_absolute_path()
			and user_root.begins_with(data_root.simplify_path().trim_suffix("/") + "/"), "Use an isolated absolute XDG_DATA_HOME.")
	if stopped:
		return
	var source: PackedByteArray = FileAccess.get_file_as_bytes(STOCKED_SOURCE).decompress_dynamic(1000000, FileAccess.COMPRESSION_GZIP)
	_expect(not source.is_empty() and _sha256(source) == STOCKED_SHA256, "The synthetic stocked checkpoint has the expected v12 hash.")
	if stopped:
		return
	if phase == "write":
		for suffix: String in ["", ".bak", ".tmp", ".pending"]:
			_expect(not FileAccess.file_exists(FLOW_SAVE + suffix), "Refuse to overwrite an existing isolated checkpoint.")
		if stopped:
			return
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FLOW_DIR))
		var file := FileAccess.open(FLOW_SAVE, FileAccess.WRITE)
		_expect(file != null, "The isolated synthetic checkpoint can be created.")
		if stopped:
			return
		file.store_buffer(source)
		file.close()
	else:
		_expect(FileAccess.file_exists(FLOW_SAVE) and FileAccess.file_exists(FLOW_EVIDENCE), "The read phase needs the preceding written checkpoint and evidence.")
	if stopped:
		return
	var before_continue: PackedByteArray = FileAccess.get_file_as_bytes(FLOW_SAVE)
	get_tree().current_scene = null
	get_tree().paused = false
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = FLOW_SAVE
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
	_expect(launched and loaded_from_menu, "The real Start Menu Continue loads the selected checkpoint.")
	if stopped:
		return
	bind_map()
	store = WorkStateRuntime.get_node("CitySave")
	city_tools = WorkStateRuntime.get_node("CityToolStorage")
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	_expect(FileAccess.get_file_as_bytes(FLOW_SAVE) == before_continue, "Continue leaves the checkpoint bytes unchanged.")
	_expect(_sha256(FileAccess.get_file_as_bytes(STOCKED_SOURCE).decompress_dynamic(1000000, FileAccess.COMPRESSION_GZIP)) == STOCKED_SHA256, "The source fixture remains unchanged.")
	_expect(content.name == "ContentScene" and runtime != null and runtime.has_node("CityStorageArea/DeliveryPoint"), "The actual city, worksites and City Storage are active.")
	if stopped:
		return
	if phase == "write":
		await _walk_and_collect(source)
	else:
		_verify_continue(source)
	if stopped:
		return
	print("LegacyWalkPickupsTest ", phase, ": PASS")
	get_tree().quit(0)

func _walk_and_collect(source: PackedByteArray) -> void:
	initial_city = _city_state()
	_expect(Inventory.max_load == 100.0, "The fixture starts with the normal 100-unit bag.")
	for id: String in ITEM_ORDER:
		_expect(_ground_count(id) == int(ORIGINAL_GROUND[id]) and _legacy_count(id) == int(LEGACY_COUNTS[id]), "The migrated and pre-existing ground quantities are exact: " + id)
		initial_totals[id] = int(Inventory.items.get(id, 0)) + _ground_count(id)
	if stopped:
		return
	for id: String in ITEM_ORDER:
		var pile: PickUpItem = _legacy_pile(id)
		_expect(is_instance_valid(pile) and pile.quantity == int(LEGACY_COUNTS[id]), "The individual migrated pile exists: " + id)
		if stopped:
			return
		print("LegacyWalk ", id, " pickup_world=", pile.global_position, " from=", player.global_position)
		await _walk_to_pickup(pile, id)
		if stopped:
			return
		if id == "water_jar":
			await _exercise_partial_water(pile)
		else:
			await _take_full_pile(pile, id)
		if stopped:
			return
		_assert_conservation("after " + id)
		_assert_city_unchanged(initial_city, "after " + id)
		if stopped:
			return
	_expect(_legacy_count("clay_lump") == 0 and _legacy_count("wood_log") == 0 and _legacy_count("reed_bundle") == 0
		and _legacy_count("straw_bundle") == 0 and _legacy_count("water_jar") == 0, "All five migrated piles were collected exactly once.")
	_expect(_ground_count("clay_lump") == 2 and _ground_count("wood_log") == 5, "Pre-existing ordinary clay and wood ground piles remain untouched.")
	_expect(Inventory.max_load == 100.0, "The temporary bag capacity is restored before Save.")
	if stopped:
		return
	var evidence: Dictionary = {"inventory": Inventory.items.duplicate(true), "ground": _all_ground(),
		"city": initial_city, "totals": initial_totals, "clock": now(), "max_load": Inventory.max_load}
	_expect(store.save_checkpoint(), "Save after collecting all migrated piles: " + store.last_error)
	_expect(FileAccess.get_file_as_bytes(FLOW_SAVE + ".bak") == source, "The normal backup retains the original v12 checkpoint bytes.")
	if stopped:
		return
	var file := FileAccess.open(FLOW_EVIDENCE, FileAccess.WRITE)
	_expect(file != null, "The isolated evidence file can be written.")
	if file != null:
		file.store_string(JSON.stringify(evidence, "\t", true, true))
		file.close()

func _take_full_pile(pile: PickUpItem, id: String) -> void:
	var amount: int = pile.quantity
	var before_inventory: int = int(Inventory.items.get(id, 0))
	var before_ground: int = _ground_count(id)
	_expect(Inventory.has_capacity_for(id, amount), "The normal bag can hold this complete pile: " + id)
	await interact(pile)
	_expect(int(Inventory.items.get(id, 0)) == before_inventory + amount and _ground_count(id) == before_ground - amount,
		"E transfers exactly the selected pile from ground to player: " + id)
	await _wait_for_pickup(pile, true)

func _exercise_partial_water(pile: PickUpItem) -> void:
	var original_limit: float = Inventory.max_load
	var item: ItemData = ItemDatabase.get_item_data("water_jar")
	_expect(item != null and item.weight > 0.0 and pile.quantity > 2, "Water fixture supports a partial-capacity interaction.")
	if stopped:
		return
	Inventory.max_load = Inventory.get_total_inventory_weight() + item.weight * 2.0
	var inventory_before: int = int(Inventory.items.get("water_jar", 0))
	var ground_before: int = _ground_count("water_jar")
	await interact(pile)
	_expect(int(Inventory.items.get("water_jar", 0)) == inventory_before + 2 and _ground_count("water_jar") == ground_before - 2
		and is_instance_valid(pile) and pile.quantity == ground_before - 2, "E takes exactly the two water jars that fit and leaves the remainder on the ground.")
	await _wait_for_pickup(pile, false)
	_expect(player.current_interactable == pile, "The partially collected water pile remains the focused interactable.")
	await interact(pile)
	_expect(int(Inventory.items.get("water_jar", 0)) == inventory_before + 2 and _ground_count("water_jar") == ground_before - 2,
		"Pressing E again with a full bag changes neither inventory nor ground.")
	await _wait_for_pickup(pile, false)
	Inventory.max_load = original_limit
	_expect(player.current_interactable == pile and Inventory.has_capacity_for("water_jar", pile.quantity), "The normal bag can collect the same remaining water pile.")
	await _take_full_pile(pile, "water_jar")

func _walk_to_pickup(pile: PickUpItem, label: String) -> void:
	# If another interactable is nearer on one side, try other physical approach
	# positions. The actual movement and interaction focus still decide success.
	for offset: Vector2 in [Vector2(0, -5), Vector2(-4, -5), Vector2(4, -5), Vector2(0, 0), Vector2(-5, 0), Vector2(5, 0), Vector2(0, 3)]:
		if not is_instance_valid(pile) or stopped:
			return
		var candidate: Vector2 = pile.global_position + offset
		if player.test_move(Transform2D(0.0, candidate), Vector2(0.01, 0)):
			continue
		await walk(candidate)
		if stopped:
			return
		if player.current_interactable == pile:
			return
	_expect(false, "No attempted physical position focused the intended pickup %s; player=%s, current=%s" % [label, player.global_position, str(player.current_interactable)])

func _wait_for_pickup(pile: PickUpItem, must_disappear: bool) -> void:
	for _frame: int in range(240):
		if player.can_move and (not must_disappear or not is_instance_valid(pile)):
			break
		await get_tree().physics_frame
	_expect(player.can_move and (not must_disappear or not is_instance_valid(pile)), "Pickup completes before further input or Save; locks=%s" % str(player._movement_locks))

func _verify_continue(source: PackedByteArray) -> void:
	var evidence: Variant = JSON.parse_string(FileAccess.get_file_as_string(FLOW_EVIDENCE))
	_expect(evidence is Dictionary, "The written inventory and ground evidence is readable.")
	if stopped:
		return
	initial_totals = evidence.totals
	_assert_saved_state(evidence, "first Continue")
	_expect(FileAccess.get_file_as_bytes(FLOW_SAVE + ".bak") == source, "Continue retains the untouched original v12 backup.")
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(FLOW_SAVE)
	_expect(store.load_checkpoint() and FileAccess.get_file_as_bytes(FLOW_SAVE) == bytes, "Repeated Load leaves the upgraded checkpoint unchanged.")
	_assert_saved_state(evidence, "repeated Continue")

func _assert_saved_state(evidence: Dictionary, label: String) -> void:
	_expect(_same_counts(Inventory.items, evidence.inventory) and _same_counts(_all_ground(), evidence.ground), label + ": inventory and ground counts match the saved state exactly.")
	_expect(is_equal_approx(Inventory.max_load, float(evidence.max_load)) and now() == int(evidence.clock), label + ": normal capacity and clock survive.")
	for id: String in ITEM_ORDER:
		_expect(_legacy_count(id) == 0, label + ": the collected legacy pile does not reappear: " + id)
	_assert_conservation(label)
	_assert_city_unchanged(evidence.city, label)

func _legacy_pile(id: String) -> PickUpItem:
	for child: Node in runtime.get_node("GroundOutput").get_children():
		if child is PickUpItem and not child.is_queued_for_deletion() and not child.is_collecting and child.item_id == id and bool(child.get_meta("legacy_stockpile", false)):
			return child as PickUpItem
	return null

func _legacy_count(id: String) -> int:
	var total: int = 0
	for child: Node in runtime.get_node("GroundOutput").get_children():
		if child is PickUpItem and not child.is_queued_for_deletion() and not child.is_collecting and child.item_id == id and bool(child.get_meta("legacy_stockpile", false)):
			total += child.quantity
	return total

func _ground_count(id: String) -> int:
	var total: int = 0
	for child: Node in runtime.get_node("GroundOutput").get_children():
		if child is PickUpItem and not child.is_queued_for_deletion() and not child.is_collecting and child.item_id == id:
			total += child.quantity
	return total

func _all_ground() -> Dictionary:
	var result: Dictionary = {}
	for id: String in ITEM_ORDER:
		result[id] = _ground_count(id)
	return result

func _assert_conservation(label: String) -> void:
	for id: String in ITEM_ORDER:
		_expect(int(Inventory.items.get(id, 0)) + _ground_count(id) == int(initial_totals[id]), label + ": inventory plus ground conserves " + id)

func _city_state() -> Dictionary:
	return {"items": city_tools.items.duplicate(true), "units": city_tools.units.duplicate(true),
		"food_portions": city_tools.food_portions.duplicate(true), "unit_sequence": city_tools._unit_sequence,
		"treasury": CityStockManager.treasury_shekel}

func _assert_city_unchanged(expected: Dictionary, label: String) -> void:
	_expect(_same_counts(city_tools.items, expected.items) and _same_counts(city_tools.food_portions, expected.food_portions)
		and city_tools.units == expected.units and int(city_tools._unit_sequence) == int(expected.unit_sequence)
		and int(CityStockManager.treasury_shekel) == int(expected.treasury), label + ": City Storage and treasury are unchanged.")

func _same_counts(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size():
		return false
	for key: Variant in expected:
		if not actual.has(key) or int(actual[key]) != int(expected[key]):
			return false
	return true

func _sha256(bytes: PackedByteArray) -> String:
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(bytes)
	return hasher.finish().hex_encode()
