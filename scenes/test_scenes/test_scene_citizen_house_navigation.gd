extends Node

## New Game and Player movement are real; the built phase is fixture-set only
## to isolate the resulting collider. No player position is assigned by the test.
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const CHECKPOINT_PATH: String = "user://house_navigation_fixture/checkpoint.json"
const GRID: float = 8.0
const ACTIONS: Array[String] = ["move_left", "move_right", "move_up", "move_down"]

var failures: int = 0
var launched: bool = false
var continued: bool = false
var content: Node2D
var player: Player
var house: Node2D
var house_collision: CollisionShape2D
var player_collision: CollisionShape2D
var walked: float = 0.0
var capture_dir: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	capture_dir = OS.get_environment("TIP_PLOT_CAPTURE_DIR")
	_expect(not FileAccess.file_exists(CHECKPOINT_PATH), "Use a fresh isolated XDG directory for New Game.")
	if failures > 0:
		_finish()
		return
	var authored: Node2D = CONTENT.instantiate()
	var authored_world: Node2D = authored.get_node("YSortWorld") as Node2D
	var authored_player: Node2D = authored.get_node("YSortWorld/Player") as Node2D
	var expected_spawn: Vector2 = authored.transform * (authored_world.transform * authored_player.position)
	authored.free()
	get_tree().current_scene = null
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = CHECKPOINT_PATH
	menu.session_started.connect(_on_session_started)
	get_tree().root.add_child(menu)
	menu._request_new_game()
	for _frame: int in range(600):
		if launched:
			break
		await get_tree().process_frame
	_expect(launched and not continued, "The real start menu opens a fresh New Game.")
	if not launched or continued:
		_finish()
		return
	content = get_tree().current_scene as Node2D
	player = content.get_node_or_null("YSortWorld/Player") as Player
	house = content.get_node_or_null("YSortWorld/CitizenHousePlot") as Node2D
	_expect(player != null and house != null, "The actual New Game map has its player and citizen house plot.")
	if player == null or house == null:
		_finish()
		return
	house_collision = house.get_node_or_null("HouseBody/CollisionShape2D") as CollisionShape2D
	player_collision = player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	_expect(house_collision != null and player_collision != null, "The actual player and finished-house collision shapes exist.")
	if house_collision == null or player_collision == null:
		_finish()
		return
	TimeComponentManager.set_process(false)
	_expect(player.global_position.distance_to(expected_spawn) < 0.1
		and player.can_move and not player.debug_disable_player_needs and not player.debug_disable_fatigue,
		"The player remains at the authored New Game spawn with normal movement and needs.")
	_expect(house.construction.phase == "uncleared" and house_collision.disabled,
		"The rubble begins uncleared with its finished-house body disabled.")
	if failures > 0:
		_finish()
		return

	var access: Node2D = house.get_node("InteractableComponent") as Node2D
	var interaction_point: Vector2 = access.global_position + Vector2(0, 4)
	var walked_before: float = walked
	if not await _walk_to(interaction_point, "New Game spawn to house rubble"):
		_finish()
		return
	for _frame: int in range(4):
		await get_tree().physics_frame
	_expect(walked - walked_before > 20.0 and player.current_interactable == house and house.has_player_access(),
		"Real movement reaches the house interaction area from the authored spawn.")
	if player.current_interactable != house or not house.has_player_access():
		_finish()
		return
	await _capture("house-walked-to-rubble")
	await _press_interact()
	var plot_menu: WorkshopPlotUI = house.get("menu") as WorkshopPlotUI
	_expect(plot_menu != null and get_tree().paused, "Pressing E at the reached rubble opens the house menu directly.")
	if plot_menu == null:
		_finish()
		return
	var title: Label = plot_menu.get_node("Root/Center/Window/Margin/MainVBox/TitleHeader/TitleLabel") as Label
	_expect(title.text == "CLEAR HOUSE SITE" and plot_menu.player_button.visible,
		"The reached house menu offers player cleaning.")
	await _capture("house-walked-menu")
	plot_menu.close_menu()
	for _frame: int in range(3):
		await get_tree().physics_frame
	_expect(player.can_move and house.has_player_access(),
		"Closing the menu leaves the player at the actual clearing interaction point.")
	if not player.can_move or not house.has_player_access():
		_finish()
		return

	# This deliberately activates the real built collider around the player at
	# the last valid interaction position; the production lifecycle is covered by
	# the separate house integration fixture.
	var before_build_position: Vector2 = player.global_position
	house.construction.phase = "built"
	house.construction.changed.emit()
	await get_tree().process_frame
	await get_tree().physics_frame
	_expect(not house_collision.disabled and house.get_node("FinishedHouse").visible,
		"The built phase activates the actual finished-house collider and artwork.")
	if house_collision.disabled:
		_finish()
		return
	if not await _walk_out_of_new_collider(before_build_position):
		_finish()
		return
	var south: Vector2 = house.global_position + Vector2(0, 38)
	if not await _walk_to(south, "open space south of the built house"):
		_finish()
		return
	if not await _verify_house_blocks_entry():
		_finish()
		return
	await _capture("house-collision-block")
	# The authored workshop's east wall occupies x=-39..-32 here. These
	# aligned waypoints instead use the open passage just outside the house.
	var left: Vector2 = house.global_position + Vector2(-24, 26)
	var right: Vector2 = house.global_position + Vector2(24, 26)
	if not await _walk_to(left, "southwest side of built house"):
		_finish()
		return
	if not await _walk_to(right, "southeast side of built house"):
		_finish()
		return
	_expect(not _house_overlaps_player() and player.can_move,
		"Real movement passes both sides of the built house without entering its footprint.")
	await _capture("house-surrounding-route")
	_finish()


func _on_session_started(is_continue: bool) -> void:
	continued = is_continue
	launched = true


func _walk_to(target: Vector2, label: String) -> bool:
	var grid := AStarGrid2D.new()
	var start_cell := Vector2i((player.global_position / GRID).round())
	var end_cell := Vector2i((target / GRID).round())
	var left: int = mini(start_cell.x, end_cell.x) - 15
	var top: int = mini(start_cell.y, end_cell.y) - 15
	var right: int = maxi(start_cell.x, end_cell.x) + 15
	var bottom: int = maxi(start_cell.y, end_cell.y) + 15
	grid.region = Rect2i(left, top, right - left + 1, bottom - top + 1)
	grid.cell_size = Vector2(GRID, GRID)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	var door: Node2D = content.get_node_or_null("YSortWorld/HomeDoor") as Node2D
	for x: int in range(left, right + 1):
		for y: int in range(top, bottom + 1):
			var position: Vector2 = Vector2(x * GRID, y * GRID)
			var solid: bool = player.test_move(Transform2D(0.0, position), Vector2(0.01, 0))
			if door != null and position.distance_to(door.global_position) < 20.0:
				solid = true # Avoid triggering the real home transition en route.
			grid.set_point_solid(Vector2i(x, y), solid)
	grid.set_point_solid(start_cell, false)
	if grid.is_point_solid(end_cell) or player.test_move(Transform2D(0.0, target), Vector2(0.01, 0)):
		_expect(false, "%s destination is blocked at %s." % [label, target])
		return false
	var points: PackedVector2Array = grid.get_point_path(start_cell, end_cell)
	_expect(not points.is_empty(), "A collision-aware route exists for " + label + ".")
	if points.is_empty():
		return false
	points.append(target)
	for point: Vector2 in points:
		var frames: int = 0
		var stationary: int = 0
		while player.global_position.distance_to(point) > 1.1:
			_release_input()
			var delta: Vector2 = point - player.global_position
			if absf(delta.x) > 0.7:
				Input.action_press("move_right" if delta.x > 0 else "move_left")
			elif absf(delta.y) > 0.7:
				Input.action_press("move_down" if delta.y > 0 else "move_up")
			var before: Vector2 = player.global_position
			await get_tree().physics_frame
			var moved: float = before.distance_to(player.global_position)
			walked += moved
			stationary = stationary + 1 if moved < 0.01 else 0
			frames += 1
			if stationary > 45 or frames > 180 or not player.can_move or SceneTransition.is_transitioning:
				_release_input()
				_expect(false, "%s walking stalled at %s toward %s." % [label, player.global_position, point])
				return false
		_release_input()
	for _frame: int in range(3):
		await get_tree().physics_frame
	return true


func _walk_out_of_new_collider(before_build_position: Vector2) -> bool:
	var input_distance: float = 0.0
	for action: String in ["move_down", "move_left", "move_right", "move_up"]:
		_release_input()
		Input.action_press(action)
		for _frame: int in range(90):
			var before: Vector2 = player.global_position
			await get_tree().physics_frame
			var moved: float = before.distance_to(player.global_position)
			walked += moved
			input_distance += moved
			if not _house_overlaps_player() and input_distance >= 2.0 and player.global_position.distance_to(before_build_position) >= 8.0:
				_release_input()
				_expect(player.can_move, "The player can walk out after the house collider activates at the interaction point.")
				return player.can_move
	_release_input()
	_expect(false, "The player could not walk out of the newly activated house collider from the interaction point.")
	return false


func _verify_house_blocks_entry() -> bool:
	var body: StaticBody2D = house.get_node("HouseBody") as StaticBody2D
	var started: Vector2 = player.global_position
	var hit_house: bool = false
	_release_input()
	Input.action_press("move_up")
	for _frame: int in range(120):
		var before: Vector2 = player.global_position
		await get_tree().physics_frame
		walked += before.distance_to(player.global_position)
		for index: int in range(player.get_slide_collision_count()):
			if player.get_slide_collision(index).get_collider() == body:
				hit_house = true
		if hit_house:
			break
	_release_input()
	_expect(hit_house and player.global_position.y < started.y and not _house_overlaps_player(),
		"Walking toward the house from outside is blocked by its own finished collider.")
	return hit_house and not _house_overlaps_player()


func _house_overlaps_player() -> bool:
	return house_collision.shape.collide(house_collision.global_transform, player_collision.shape, player_collision.global_transform)


func _press_interact() -> void:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame
	event = InputEventAction.new()
	event.action = "interact"
	event.pressed = false
	get_viewport().push_input(event)
	await get_tree().process_frame


func _release_input() -> void:
	for action: String in ACTIONS:
		Input.action_release(action)


func _capture(name: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(capture_dir.path_join(name + ".png"))


func _finish() -> void:
	_release_input()
	get_tree().paused = false
	print("CitizenHouseNavigationTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures, "; walked=", walked)
	get_tree().quit(0 if failures == 0 else 1)
