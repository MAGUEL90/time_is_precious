extends Node
var failures: int = 0

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	TimeComponentManager.set_process(false)
	var map = load("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(map)
	for frame in range(6):
		await get_tree().physics_frame
	var player: Player = map.get_node("YSortWorld/Player")
	# This fixture tests interaction and refill, not starvation during clock jumps.
	player.debug_disable_player_needs = true
	var tree = map.get_node("YSortWorld/DatePalmTree")
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	var palms: Array[Node] = []
	for child: Node in map.get_node("YSortWorld").get_children():
		if child.get_script() == preload("res://scenes/pickup_item/date_palm_spawner.gd"):
			palms.append(child)
	expect(palms.size() == 6, "Integrated city retains six independent date palms")
	for palm: Node in palms:
		for slot in range(3):
			var pickup = palm._pickups[slot]
			var ground: TileMapLayer = map.get_node("Ground/base2")
			expect(ground.get_cell_source_id(ground.local_to_map(ground.to_local(pickup.global_position))) >= 0, "Date pickup is on authored land: " + str(palm.name))
			player.global_position = pickup.global_position + Vector2(0, -6)
			expect(not player.test_move(player.global_transform, Vector2(0, 1)), "Pickup approach is outside solid geometry")
			for frame in range(6):
				await get_tree().physics_frame
			expect(player.current_interactable == pickup, "Physical approach selects %s slot %d" % [palm.name, slot])
			var before: int = Inventory.items.get("date_cluster", 0)
			player._unhandled_input(event)
			expect(Inventory.items.get("date_cluster", 0) == before + 1, "E collects approached date")
			await get_tree().create_timer(1.0).timeout
			print("DATE_ACCESS ", slot, " can_move=", player.can_move)
			expect(player.can_move, "Movement restored after pickup animation")
	var remaining: int = tree.state.remaining_minutes
	TimeComponentManager.advance_minutes(remaining - 1)
	TimeComponentManager.current_weather = "storm"
	TimeComponentManager.advance_minutes(1)
	await get_tree().process_frame
	expect(tree.state.available.count(true) == 3, "Current policy refills in storm")
	print("DatePickupAccessTest: ", "PASS" if failures == 0 else "FAIL")
	map.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().call_deferred("quit", 0 if failures == 0 else 1)
