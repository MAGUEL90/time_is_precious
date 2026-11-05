extends "res://scenes/test_scenes/test_scene_citizen_house_navigation.gd"

## Exercise the new-game spawn, relocated food sources and home using real input.
func _run() -> void:
	_expect(not FileAccess.file_exists(CHECKPOINT_PATH), "Use a fresh isolated profile for the authored layout walk.")
	get_tree().current_scene = null
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = CHECKPOINT_PATH
	menu.session_started.connect(_on_session_started)
	get_tree().root.add_child(menu)
	menu._request_new_game()
	for frame: int in range(600):
		if launched:
			break
		await get_tree().process_frame
	_expect(launched and not continued, "The real menu starts a fresh game.")
	if not launched:
		_finish_layout()
		return
	content = get_tree().current_scene as Node2D
	player = content.get_node("YSortWorld/Player") as Player
	TimeComponentManager.set_process(false)
	for frame: int in range(8):
		await get_tree().physics_frame
	var wall: CanvasItem = content.get_node("YSortWorld/WallStone")
	_expect(not wall.visible, "The old wall artwork does not cover the authored layout.")
	var storage: Area2D = content.get_node("YSortWorld/WorkerRuntime/CityStorageArea")
	_expect(not storage.get_node("Sprite2D").visible and storage.get_node("Board").visible
		and storage.get_node("BuildingBody/CollisionShape2D").disabled,
		"The visible storage board replaces the old building without an invisible blocker.")
	var storage_access: CollisionShape2D = storage.get_node("CollisionShape2D")
	if not await _walk_to(storage_access.global_position, "City Storage board"):
		_finish_layout()
		return
	_expect(player.current_interactable == storage and storage.has_player_access(),
		"Normal walking reaches the storage board and selects its interaction.")
	await _press_interact()
	_expect(is_instance_valid(storage.menu), "The storage board opens its real menu.")
	storage.close_menu()
	for frame: int in range(4):
		await get_tree().physics_frame
	_expect(player.can_move, "Closing City Storage returns player control.")
	if failures > 0:
		_finish_layout()
		return
	var palm: Node2D = content.get_node("YSortWorld/DatePalmTree3")
	var pickup: PickUpItem = palm._pickups.get(0)
	_expect(is_instance_valid(pickup), "The relocated date palm still has a real pickup.")
	if not is_instance_valid(pickup):
		_finish_layout()
		return
	var before: int = int(Inventory.items.get("date_cluster", 0))
	if not await _walk_to(pickup.global_position + Vector2(0, -5), "relocated date palm"):
		_finish_layout()
		return
	_expect(player.current_interactable is PickUpItem and player.current_interactable.is_in_group("date_palm_pickups"),
		"Walking to the palm selects a date pickup through normal interaction.")
	await _press_interact()
	for frame: int in range(240):
		if player.can_move and int(Inventory.items.get("date_cluster", 0)) > before:
			break
		await get_tree().physics_frame
	_expect(int(Inventory.items.get("date_cluster", 0)) > before and player.can_move,
		"The relocated palm grants dates and returns control to the player.")
	if failures > 0:
		_finish_layout()
		return
	var door: Area2D = content.get_node("YSortWorld/HomeDoor")
	if not await _walk_to(door.global_position + Vector2(0, 30), "approach to the relocated home"):
		_finish_layout()
		return
	_release_input()
	Input.action_press("move_up")
	for frame: int in range(180):
		await get_tree().physics_frame
		if SceneTransition.is_transitioning or get_tree().current_scene != content:
			break
	_release_input()
	for frame: int in range(300):
		if get_tree().current_scene != content and not SceneTransition.is_transitioning:
			break
		await get_tree().process_frame
	_expect(get_tree().current_scene != content
		and get_tree().current_scene.scene_file_path == "res://scenes/player_home_interior/player_home_interior.tscn",
		"Walking through the relocated home door reaches the real interior.")
	_finish_layout()


func _finish_layout() -> void:
	_release_input()
	get_tree().paused = false
	print("AuthoredLayoutAccessTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures, "; walked=", walked)
	get_tree().quit(0 if failures == 0 else 1)
