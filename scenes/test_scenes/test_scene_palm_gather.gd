extends "res://scenes/test_scenes/test_scene_city_save.gd"

## Actual E input against an authored palm, with capacity, re-entry and save
## probes. Time is frozen; this is a source invariant test, not a playthrough.
var callback_count: int = 0
var blocked_saves: int = 0
var reentry_target: PickUpItem


func _run() -> void:
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	await load_content()
	store = WorkStateRuntime.get_node("CitySave")
	store.disk.path = "user://palm_gather/checkpoint.json"
	for suffix: String in ["", ".bak", ".tmp", ".pending"]:
		DirAccess.remove_absolute(store.disk.path + suffix)
	Inventory.items.clear()
	var first: Node = content.get_node("YSortWorld/DatePalmTree")
	var palms: Array = _authored_palm_trees()
	var other: Node = palms[1] if palms[0] == first else palms[0]
	var chosen: PickUpItem = first._pickups[1]
	Inventory.max_load = 0.0
	await _press_pickup(chosen)
	_expect(Inventory.items.is_empty() and first.state.available.count(true) == 3,
		"A full bag retains every fruit on the palm.")
	await _wait_for_pickup()

	Inventory.max_load = 0.21
	reentry_target = chosen
	Inventory.items_changed.connect(_on_inventory_during_gather)
	await _press_pickup(chosen)
	Inventory.items_changed.disconnect(_on_inventory_during_gather)
	_expect(callback_count == 2 and blocked_saves == 2,
		"Both synchronous inventory callbacks are inside the pickup movement lock.")
	_expect(int(Inventory.items.get("date_cluster", 0)) == 2 and first.state.available.count(true) == 1,
		"Partial capacity collects exactly two existing slots despite re-entry attempts.")
	_expect(other.state.available.count(true) == 3,
		"Gathering a palm never consumes another palm's slots.")
	_expect(first.state.remaining_minutes >= 60 and first.state.remaining_minutes <= 1080,
		"The existing palm timer starts normally.")
	var popups: Array = _visible_popups()
	_expect(popups.size() == 1 and popups[0].get_node("Row/AmountLabel").text == "+2",
		"The player sees one accurate combined pickup count.")
	await _wait_for_pickup()
	await get_tree().process_frame
	var saved_slots: Array = first.state.available.duplicate()
	var saved_timer: int = first.state.remaining_minutes
	var saved_rng: int = first.state._rng.state
	_expect(store.save_checkpoint(), "A partly harvested palm and inventory can save: " + store.last_error)
	Inventory.max_load = 100.0
	var remaining: PickUpItem = first._pickups.values()[0]
	await _press_pickup(remaining)
	_expect(int(Inventory.items.get("date_cluster", 0)) == 3 and first.state.available.count(true) == 0,
		"The remaining fruit can be collected after capacity becomes available.")
	await _wait_for_pickup()
	_expect(store.load_checkpoint(), "The partial palm checkpoint loads: " + store.last_error)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(int(Inventory.items.get("date_cluster", 0)) == 2 and first.state.available == saved_slots
		and first.state.remaining_minutes == saved_timer and first.state._rng.state == saved_rng,
		"Loading restores the exact inventory, missing slots, timer and RNG.")
	_expect(store.load_checkpoint(), "Repeated load does not duplicate fruit.")
	await get_tree().process_frame
	_expect(int(Inventory.items.get("date_cluster", 0)) == 2 and first.state.available == saved_slots,
		"Repeated load retains the same items and slots.")
	Inventory.max_load = 100.0
	_expect(TimeComponentManager.advance_minutes(saved_timer), "Natural clock advances to the existing refill deadline.")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(first.state.available.count(true) == 3 and first._pickups.size() == 3,
		"The normal timer refills the same three slots, without bonus stock.")
	var inventory_before: int = int(Inventory.items.get("date_cluster", 0))
	await _press_pickup(first._pickups.values()[0])
	_expect(int(Inventory.items.get("date_cluster", 0)) == inventory_before + 3 and first.state.available.count(true) == 0,
		"After refill one E gathers the three physical fruit once.")
	popups = _visible_popups()
	_expect(popups.size() == 1 and popups[0].get_node("Row/AmountLabel").text == "+3",
		"Full gathering shows one +3 popup.")
	await _wait_for_pickup()
	# A load or other synchronous owner can update the ledger before deferred
	# view refresh. A stale view must never mint a previously removed fruit.
	var stale: PickUpItem = other._pickups[0]
	other.state.collect(0)
	inventory_before = int(Inventory.items.get("date_cluster", 0))
	stale.on_player_gather(player)
	_expect(int(Inventory.items.get("date_cluster", 0)) == inventory_before and other.state.available.count(true) == 2,
		"Selecting a stale unavailable view cannot gather any fruit.")
	other._pickups[1].on_player_gather(player)
	_expect(int(Inventory.items.get("date_cluster", 0)) == inventory_before + 2 and not stale.is_collecting
		and other.state.available.count(true) == 0,
		"A valid selection ignores the stale unavailable sibling and gathers only two slots.")
	await _wait_for_pickup()
	await _non_palm_input()
	await _food_balance()
	print("PalmGatherTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)


func _press_pickup(pickup: PickUpItem) -> void:
	player.global_position = pickup.global_position + Vector2(0, -6)
	await _settle_physics()
	_expect(player.current_interactable == pickup, "Physical proximity selects the requested fruit.")
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	player._unhandled_input(event)


func _wait_for_pickup() -> void:
	var deadline: int = Time.get_ticks_msec() + 4000
	while not player.can_move and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	await get_tree().create_timer(0.65).timeout
	_expect(player.can_move, "The pickup animation releases the movement lock.")


func _on_inventory_during_gather() -> void:
	callback_count += 1
	if not store.save_checkpoint() and store.last_error.contains("Finish the current interaction"):
		blocked_saves += 1
	# Both the user-facing group action and the low-level item action resist re-entry.
	reentry_target.on_player_gather(player)
	reentry_target.on_player_interact(player)


func _visible_popups() -> Array:
	var result: Array = []
	for child: Node in get_tree().current_scene.get_children():
		if child.get_script() != null and child.get_script().resource_path == "res://item_change_popup.gd":
			result.append(child)
	return result


func _non_palm_input() -> void:
	var world: Node2D = content.get_node("YSortWorld")
	var drop: PickUpItem = load("res://scenes/pickup_item/pickup_item.tscn").instantiate()
	drop.item_id = "orchard_apple"
	world.add_child(drop)
	drop.global_position = player.global_position + Vector2(0, -35)
	var dates_before: int = int(Inventory.items.get("date_cluster", 0))
	await _press_pickup(drop)
	_expect(int(Inventory.items.get("orchard_apple", 0)) == 1
		and int(Inventory.items.get("date_cluster", 0)) == dates_before,
		"Actual E input on an ordinary drop still takes that item only.")
	await _wait_for_pickup()
	var runtime: Node = world.get_node("WorkerRuntime")
	_expect(runtime._drop_legacy_stockpile_output(3, Vector2.ZERO, "clay_lump"),
		"The legacy partial-pile fixture is created through the worksite runtime.")
	var pile: PickUpItem = runtime.get_node("GroundOutput").get_child(-1)
	pile.global_position = player.global_position + Vector2(0, -35)
	Inventory.max_load = Inventory.get_total_inventory_weight() + 2.1
	await _press_pickup(pile)
	_expect(int(Inventory.items.get("clay_lump", 0)) == 1 and pile.quantity == 2 and not pile.is_collecting,
		"Actual E input preserves legacy partial-pile behavior and its remainder.")
	await _wait_for_pickup()
	Inventory.max_load = 100.0


func _food_balance() -> void:
	var dates: ItemData = ItemDatabase.get_item_data("date_cluster")
	var loaf: ItemData = ItemDatabase.get_item_data("fresh_loaf")
	_expect(is_equal_approx(dates.hunger_reduction, 0.04) and is_equal_approx(dates.fatigue_reduction, 0.01)
		and is_equal_approx(dates.weight, 0.1) and dates.food_supply_value == 1,
		"Date Cluster keeps its original nutrition, weight and city supply.")
	_expect(is_equal_approx(loaf.hunger_reduction, 0.10) and is_equal_approx(loaf.fatigue_reduction, 0.01)
		and is_equal_approx(loaf.weight, 0.3) and loaf.food_supply_value == 1,
		"Fresh Loaf keeps more Belly per item, equal Energy, and greater weight.")
	Inventory.items.clear()
	Inventory.add_item("date_cluster", 1)
	Inventory.add_item("fresh_loaf", 1)
	player.hunger = 0.7
	player.fatigue = 0.7
	var inventory_ui: Node = content.get_node("InventoryUI")
	inventory_ui.player_ref = player
	await inventory_ui._execute_use_item("date_cluster", 1)
	_expect(is_equal_approx(player.hunger, 0.66) and is_equal_approx(player.fatigue, 0.69),
		"The real use-item path applies the date's 4 Belly and 1 Energy.")
	await inventory_ui._execute_use_item("fresh_loaf", 1)
	_expect(is_equal_approx(player.hunger, 0.56) and is_equal_approx(player.fatigue, 0.68),
		"The real use-item path applies the loaf's 10 Belly and 1 Energy.")
