extends "res://scenes/test_scenes/test_scene_city_save_economy.gd"

## Isolated regression. Snapshot probes are in memory; this test writes no saves.
const TEST_PICKUP: PackedScene = preload("res://scenes/pickup_item/pickup_item.tscn")
const TEST_VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const MAX_INVENTORY_COUNT: int = 9223372036854775807
const PILE_POSITION := Vector2(-13, 27)

class RejectingPickup extends "res://scenes/content_scene/worksites/legacy_stockpile_pickup.gd":
	var attempts: int = 0

	func _transfer_to_inventory(_taken: int) -> bool:
		attempts += 1
		return false

var observed_pile: PickUpItem
var expected_inventory: int = 0
var expected_ground: int = 0
var observation_count: int = 0
var observing: bool = false
var collected_count: int = 0
var observe_handoff: bool = false


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
	store = WorkStateRuntime.get_node("CitySave")
	# This harness never calls the disk save API. Keep a separate path even if
	# a future test adds one, and run under an isolated Godot user-data directory.
	store.disk.path = "user://legacy_stockpile_pickup_test/checkpoint.json"
	Inventory.items.clear()
	Inventory.max_load = 100.0
	for child: Node in runtime.get_node("GroundOutput").get_children():
		child.free()

	var initial_snapshot: Dictionary = store.snapshot.capture(content)
	_expect(not initial_snapshot.is_empty(), "The real content scene can be captured before pickup tests: " + store.snapshot.error)
	if initial_snapshot.is_empty():
		await _finish_pickup_test()
		return

	var created: bool = runtime._drop_legacy_stockpile_output(96, PILE_POSITION, "clay_lump")
	_expect(created, "A legacy pile is created in the actual content worksite.")
	if not created:
		await _finish_pickup_test()
		return
	var pile: PickUpItem = runtime.get_node("GroundOutput").get_child(-1) as PickUpItem
	pile.collected.connect(_on_pile_collected)
	_expect(pile.quantity == 96 and pile.position == PILE_POSITION
		and bool(pile.get_meta("legacy_stockpile", false)) and str(pile.get_meta("daily_site", "")) == "",
		"The pile retains its type, position and all 96 clay units without a daily-site tag.")
	_expect(runtime._daily_output_count(&"ClaySiteA") == 0, "A legacy pile is not counted as Hauler output.")

	# Clay weighs 2.0, so an empty 100-unit bag holds exactly 50 of the 96.
	_observe_next_transfer(pile, 50, 46, true)
	pile.on_player_interact(player)
	_end_observation()
	_expect(observation_count == 1, "Partial collection emits one inventory change.")
	_expect(int(Inventory.items.get("clay_lump", 0)) == 50 and pile.quantity == 46,
		"An empty bag takes 50 clay and keeps 46 at the same pile.")
	_expect(pile.position == PILE_POSITION and not pile.is_collecting and collected_count == 0,
		"Partial collection leaves the original pickup in place and does not emit collected.")

	# A second interaction at full capacity must not change either owner.
	var before_full: Dictionary = Inventory.items.duplicate(true)
	pile.on_player_interact(player)
	_expect(Inventory.items == before_full and pile.quantity == 46 and collected_count == 0,
		"A full bag and repeated interaction leave inventory and ground unchanged.")
	pile.is_player_in_interaction_range = true
	pile._refresh_interaction_feedback()
	_expect(pile.interactable_label_component.label.has_theme_color_override("font_color"),
		"A full bag uses the existing unavailable interaction feedback.")
	await get_tree().create_timer(0.3).timeout
	_expect(pile.position.is_equal_approx(PILE_POSITION), "Failed-pickup feedback returns the pile to its original position.")

	# Twenty logs weigh 60, leaving room for 20 more clay.
	Inventory.items.clear()
	Inventory.items["wood_log"] = 20
	pile.is_player_in_interaction_range = true
	pile._refresh_interaction_feedback()
	_expect(pile.interactable_label_component.label.text == "E"
		and not pile.interactable_label_component.label.has_theme_color_override("font_color"),
		"A partly full bag shows the existing interact prompt when one item fits.")
	_observe_next_transfer(pile, 20, 26)
	pile.on_player_interact(player)
	_end_observation()
	_expect(observation_count == 1 and int(Inventory.items.get("wood_log", 0)) == 20
		and int(Inventory.items.get("clay_lump", 0)) == 20 and pile.quantity == 26,
		"A partially full bag takes only 20 clay, leaving 26 in the same world pile.")
	_expect(pile.position.is_equal_approx(PILE_POSITION), "Partial collection preserves the world position.")

	# Emptying the bag allows the remaining pile to complete, exactly once.
	Inventory.items.clear()
	_observe_next_transfer(pile, 26, 0)
	pile.on_player_interact(player)
	_end_observation()
	_expect(observation_count == 1 and int(Inventory.items.get("clay_lump", 0)) == 26
		and pile.is_collecting and collected_count == 1,
		"The last 26 units enter the empty bag and emit collected once.")
	pile.on_player_interact(player)
	_expect(int(Inventory.items.get("clay_lump", 0)) == 26 and collected_count == 1,
		"An exhausted pickup cannot be collected again during its animation.")
	await get_tree().create_timer(0.6).timeout
	_expect(not is_instance_valid(pile), "The exhausted pickup frees itself after standard feedback.")

	_test_rejected_transfers()
	_test_inventory_overflow()
	_test_legacy_handoff_cache()
	await _finish_pickup_test()


func _observe_next_transfer(pile: PickUpItem, inventory_count: int, ground_count: int, handoff: bool = false) -> void:
	observed_pile = pile
	expected_inventory = inventory_count
	expected_ground = ground_count
	observation_count = 0
	observe_handoff = handoff
	Inventory.items_changed.connect(_on_items_changed_during_pickup)


func _end_observation() -> void:
	if Inventory.items_changed.is_connected(_on_items_changed_during_pickup):
		Inventory.items_changed.disconnect(_on_items_changed_during_pickup)
	observed_pile = null


func _on_items_changed_during_pickup() -> void:
	if observing:
		return
	observing = true
	observation_count += 1
	var before_nested: Dictionary = Inventory.items.duplicate(true)
	if is_instance_valid(observed_pile):
		observed_pile.on_player_interact(player)
	_expect(Inventory.items == before_nested, "Reentrant interaction during items_changed does not collect twice.")
	if observe_handoff:
		var handoff_ok: bool = store.prepare_home_departure(content, store.snapshot.HOME_PATH)
		_expect(handoff_ok and store.parked_worksite == runtime,
			"The real home handoff can park the worksite during the inventory signal.")
	var captured: Dictionary = store.snapshot.capture(content)
	_expect(not captured.is_empty(), "An in-signal snapshot can capture the real content scene: " + store.snapshot.error)
	if not captured.is_empty():
		var decoded: Variant = TEST_VALUES.new().decode(captured.state)
		_expect(decoded is Dictionary, "The in-signal snapshot decodes.")
		if decoded is Dictionary:
			var piles: Array = []
			for entry: Dictionary in decoded.worksites.legacy_ground:
				piles.append(entry)
			_expect(int(decoded.inventory.items.get("clay_lump", 0)) == expected_inventory,
				"The in-signal snapshot includes the credited inventory amount.")
			if expected_ground == 0:
				_expect(piles.is_empty(), "An exhausted pile is already absent from the in-signal snapshot.")
			else:
				_expect(piles.size() == 1, "The in-signal snapshot includes exactly one legacy remainder.")
				if piles.size() == 1:
					_expect(int(piles[0].quantity) == expected_ground and piles[0].item_id == "clay_lump"
						and piles[0].position == PILE_POSITION and piles[0].site_id == "",
						"The in-signal snapshot preserves the exact remainder and position without a Hauler tag.")
	if observe_handoff and store.parked_worksite == runtime:
		store.cancel_home_departure()
		_expect(runtime.get_parent() == content.get_node("YSortWorld"), "The parked worksite returns after the handoff probe.")
	observing = false


func _on_pile_collected() -> void:
	collected_count += 1


func _test_rejected_transfers() -> void:
	Inventory.items.clear()
	var rejected: PickUpItem = TEST_PICKUP.instantiate()
	rejected.set_script(RejectingPickup)
	rejected.item_id = "clay_lump"
	rejected.quantity = 96
	rejected.position = PILE_POSITION
	rejected.set_meta("legacy_stockpile", true)
	runtime.get_node("GroundOutput").add_child(rejected)
	var label := Label.new()
	label.name = "QuantityLabel"
	rejected.add_child(label)
	rejected.on_player_interact(player)
	_expect(Inventory.items.is_empty() and rejected.quantity == 96 and not rejected.is_collecting
		and not bool(rejected.get("_taking")) and rejected.position == PILE_POSITION,
		"A rejected partial transfer rolls back the complete pile and transaction flag.")
	rejected.quantity = 2
	rejected.on_player_interact(player)
	_expect(Inventory.items.is_empty() and rejected.quantity == 2 and not rejected.is_collecting
		and not bool(rejected.get("_taking")) and int(rejected.get("attempts")) == 2,
		"A rejected full transfer also restores the pickup and can be retried.")
	rejected.free()


func _test_inventory_overflow() -> void:
	Inventory.items.clear()
	Inventory.items["shekel"] = MAX_INVENTORY_COUNT - 1
	var created: bool = runtime._drop_legacy_stockpile_output(2, PILE_POSITION, "shekel")
	_expect(created, "The int64 boundary fixture creates a legacy pickup.")
	if not created:
		return
	var pile: PickUpItem = runtime.get_node("GroundOutput").get_child(-1) as PickUpItem
	pile.on_player_interact(player)
	_expect(int(Inventory.items["shekel"]) == MAX_INVENTORY_COUNT and pile.quantity == 1 and not pile.is_collecting,
		"A weightless inventory stack stops at the integer maximum and preserves the remainder.")
	pile.on_player_interact(player)
	_expect(int(Inventory.items["shekel"]) == MAX_INVENTORY_COUNT and pile.quantity == 1,
		"A retry at the integer maximum neither wraps nor loses the remainder.")
	pile.free()


func _test_legacy_handoff_cache() -> void:
	Inventory.items.clear()
	var key: StringName = runtime.RESOURCE_STOCK_META
	var had_previous: bool = WorkStateRuntime.has_meta(key)
	var previous: Variant = WorkStateRuntime.get_meta(key) if had_previous else null
	var cache: Dictionary = {"day": TimeComponentManager.current_day, "sites": {},
		"storages": {&"ClaySiteA": 4, &"WoodSite": 5, &"ReedSite": 6, &"StrawSite": 7, &"WaterSite": 8},
		"ground": [], "pending_output": {}, "pending_progress": {}}
	WorkStateRuntime.set_meta(key, cache)
	runtime._restore_resource_stock()
	var totals: Dictionary = {}
	for pile: PickUpItem in runtime.get_node("GroundOutput").get_children():
		if bool(pile.get_meta("legacy_stockpile", false)):
			totals[pile.item_id] = int(totals.get(pile.item_id, 0)) + pile.quantity
	_expect(totals == {"clay_lump": 4, "wood_log": 5, "reed_bundle": 6, "straw_bundle": 7, "water_jar": 8}
		and cache.storages.is_empty(), "A prior scene handoff converts each cached stockpile exactly once.")
	var count: int = runtime.get_node("GroundOutput").get_child_count()
	runtime._restore_resource_stock()
	_expect(runtime.get_node("GroundOutput").get_child_count() == count, "Repeating a consumed legacy cache does not create another pile.")
	for pile: Node in runtime.get_node("GroundOutput").get_children():
		pile.free()
	if had_previous:
		WorkStateRuntime.set_meta(key, previous)
	else:
		WorkStateRuntime.remove_meta(key)


func _finish_pickup_test() -> void:
	_end_observation()
	if is_instance_valid(content):
		content.queue_free()
		await get_tree().process_frame
	_restore_clock()
	print("LegacyStockpilePickupTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
