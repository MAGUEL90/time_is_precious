extends Node

var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("PASS: ", message)

func _settle() -> void:
	for frame in range(5):
		await get_tree().physics_frame
		await get_tree().process_frame

func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var folder: String = OS.get_environment("WAREHOUSE_CAPTURE_DIR")
	if not folder.is_empty():
		_expect(get_viewport().get_texture().get_image().save_png(folder.path_join(filename)) == OK, "Save rendered evidence")

func _run() -> void:
	TimeComponentManager.set_process(false)
	var content = load("res://scenes/content_scene/content_scene.tscn").instantiate()
	get_tree().root.add_child(content)
	get_tree().current_scene = content
	await _settle()
	var player: Player = content.get_node("YSortWorld/Player")
	var area = content.get_node("YSortWorld/WorkerRuntime/CityStorageArea")
	player.debug_disable_player_needs = true
	_expect(get_tree().get_nodes_in_group("city_storage_areas").size() == 1, "One physical City Storage in ContentScene")
	_expect(area.get_node("Sprite2D").texture.resource_path == "res://assets/ui/building/warehouse_leveL_1.png", "Warehouse asset bound")
	_expect(area.storage == WorkStateRuntime.get_node("CityToolStorage"), "Existing shared provider retained")
	player.global_position = area.delivery_point.global_position
	await _settle()
	_expect(area.has_player_access() and player.current_interactable == area, "Entrance and delivery point are accessible")
	_expect(not player.test_move(player.global_transform, Vector2(0, 1)), "Entrance is not inside building collision")
	_expect(player.test_move(player.global_transform, Vector2(0, -24)), "Walking north is blocked by building footprint")
	var before: Dictionary = area.storage.items.duplicate(true)
	await _capture("warehouse-world.png")
	for attempt in range(2):
		var event := InputEventAction.new()
		event.action = &"interact"
		event.pressed = true
		player._unhandled_input(event)
		await _settle()
		_expect(is_instance_valid(area.menu), "E opens existing storage menu")
		if is_instance_valid(area.menu):
			await _capture("warehouse-storage.png")
			area.close_menu()
		await _settle()
		_expect(player.can_move and not is_instance_valid(area.menu), "Closing restores movement")
	_expect(area.storage.items == before, "Browsing never changes stock")
	player.global_position = area.global_position + Vector2(0, -54)
	await _settle()
	_expect(not area.has_player_access(), "Rear of warehouse cannot open storage")
	await _capture("warehouse-behind.png")
	content.queue_free()
	await _settle()
	print("WarehouseTest ", "PASSED" if failures == 0 else "FAILED")
	get_tree().quit(0 if failures == 0 else 1)
