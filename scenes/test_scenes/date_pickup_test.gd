extends Node

var failures: int = 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var map = load("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(map)
	await get_tree().process_frame
	var player: Player = map.get_node("YSortWorld/Player")
	player.set_physics_process(false)
	Inventory.items.clear()
	var dates: Array = []
	for node_name in ["DatesPickup", "DatesPickup2", "DatesPickup3"]:
		var pickup = map.get_node("YSortWorld/" + node_name)
		dates.append(pickup)
		check(pickup is PickUpItem, "Must reuse PickUpItem")
		check(pickup.icon.texture.resource_path == "res://assets/objects/dates_pickup.png", "World texture override")
		check(pickup.item_id == "date_cluster", "Date item binding")
	check(ItemDatabase.get_item_data("date_cluster").icon.resource_path == "res://assets/items/date_cluster.png", "Inventory icon unchanged")
	Inventory.max_load = 0.0
	dates[0].on_player_interact(player)
	check(not dates[0].is_collecting and Inventory.items.is_empty(), "Full inventory retains pickup")
	Inventory.max_load = 100.0
	player._on_interactable_activated(dates[0])
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	player._unhandled_input(event)
	dates[0].on_player_interact(player)
	check(Inventory.items.get("date_cluster", 0) == 1, "Repeated interaction cannot duplicate")
	dates[1].on_player_interact(player)
	dates[2].on_player_interact(player)
	check(Inventory.items.get("date_cluster", 0) == 3, "Three pickups enter inventory")
	await get_tree().create_timer(0.6).timeout
	check(not is_instance_valid(dates[0]), "Collected pickup removed")
	var legacy = load("res://scenes/pickup_item/pickup_item.tscn").instantiate()
	legacy.item_id = "orchard_apple"
	add_child(legacy)
	check(legacy.icon.texture == ItemDatabase.get_item_data("orchard_apple").icon, "Legacy icon fallback")
	var ui = map.get_node("InventoryUI")
	player.hunger = 0.5
	player.fatigue = 0.5
	ui.player_ref = player
	await ui._execute_use_item("date_cluster", 1)
	check(is_equal_approx(player.hunger, 0.46), "Existing date hunger effect")
	check(Inventory.items.get("date_cluster", 0) == 2, "Eating consumes date")
	print("DatePickupTest: ", "PASS" if failures == 0 else "FAIL")
	await get_tree().create_timer(2.0).timeout
	legacy.queue_free()
	map.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if failures == 0 else 1)
