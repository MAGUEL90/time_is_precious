extends Node

## Full content map at night. Only the initial starting pose is staged; all
## subsequent movement uses the same input actions as the player.
const CONTENT = preload("res://scenes/content_scene/content_scene.tscn")
const VISIBLE_BOUNDS = preload("res://scenes/workshop_plot/keeper/workshop_visual_bounds.gd")
var failures: int = 0
var city: Node
var runtime: Node
var player: Player
var saw_wood: bool = false
var saw_reed: bool = false

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _capture(stage: String) -> void:
	var directory: String = OS.get_environment("TIP_MVP_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	_check(image.save_png(directory.path_join("night-walk-" + stage + ".png")) == OK, "Capture night walk " + stage)

func _sample(stage: String) -> void:
	await get_tree().process_frame
	var site: Marker2D = runtime._highlighted_site
	var owner: String = str(site.name) if is_instance_valid(site) else "none"
	if owner == "WoodSite":
		saw_wood = true
	elif owner == "ReedSite":
		saw_reed = true
	if is_instance_valid(site):
		var prompt: InteractableLabelComponent = site.get_node("InteractPrompt")
		var icon: Sprite2D = site.get_node("ResourceIcon")
		var box: Rect2 = prompt.get_global_transform() * Rect2(Vector2.ZERO, prompt.size)
		var art: Rect2 = VISIBLE_BOUNDS.measure(icon)
		var player_art: Rect2 = VISIBLE_BOUNDS.measure(player.get_node("PlayerVisual"))
		_check(prompt.visible and is_equal_approx(box.get_center().x, art.get_center().x) and is_equal_approx(art.position.y - box.end.y, 2.0), stage + ": E remains above the selected resource")
		_check(not box.intersects(art), stage + ": E does not cover the resource")
		_check(not box.intersects(player_art), stage + ": E does not cover the moving player")
		for neighbor: Marker2D in runtime.get_node("WorksiteMarkers").get_children():
			if neighbor != site:
				var neighbor_art: Rect2 = VISIBLE_BOUNDS.measure(neighbor.get_node("ResourceIcon"))
				_check(not box.intersects(neighbor_art), stage + ": E does not cover " + str(neighbor.name) + " artwork")
		print("NightWalk ", JSON.stringify({"stage":stage,"owner":owner,"player":str(player.global_position),"box":str(box)}))
	await _capture(stage)

func _move(action: StringName, frames: int, prefix: String, interval: int) -> void:
	Input.action_press(action)
	for index: int in range(frames):
		await get_tree().physics_frame
		if (index + 1) % interval == 0:
			await _sample(prefix + "-" + str(index + 1))
	Input.action_release(action)
	await get_tree().process_frame

func _activate_focused_site(expected: String) -> void:
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	_check(runtime.inspector.visible and is_instance_valid(runtime._selected_site) and str(runtime._selected_site.name) == expected,
		"Normal E action opens the selected " + expected + " panel")
	runtime._close_inspector()
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame

func _run() -> void:
	TimeComponentManager.current_day = 3
	TimeComponentManager.current_hour = 22
	TimeComponentManager.current_minute = 1
	TimeComponentManager.is_paused = false
	TimeComponentManager.set_process(false)
	city = CONTENT.instantiate()
	add_child(city)
	runtime = city.get_node("YSortWorld/WorkerRuntime")
	player = city.get_node("YSortWorld/Player")
	var accepted_board: Node2D = city.get_node("YSortWorld/InitialWorksites/JobBoard")
	var accepted_art: Rect2 = VISIBLE_BOUNDS.measure(accepted_board.get_node("Sprite2D"))
	var accepted_box: Rect2 = accepted_board.get_node("InteractableLabelComponent").get_global_transform() * Rect2(Vector2.ZERO, Vector2(16, 16))
	_check(is_equal_approx(accepted_art.position.y - accepted_box.end.y, 2.0), "Reference Job Board gap stays two world pixels")
	get_window().size = Vector2i(1200, 675)
	player.get_node("Camera2D").make_current()
	await get_tree().physics_frame
	player._set_current_interactable(null)
	player.global_position = runtime.get_node("WorksiteMarkers/WoodSite").global_position + Vector2(-20, -6)
	for _frame: int in range(3):
		await get_tree().physics_frame
	await _sample("wood-start")
	await _activate_focused_site("WoodSite")
	await _move(&"move_down", 45, "down", 9)
	await _move(&"move_down", 25, "around-bottom", 25)
	await _move(&"move_right", 50, "around-right", 10)
	await _move(&"move_up", 22, "up-right", 11)
	await _activate_focused_site("ReedSite")
	var storage: Node2D = runtime.get_node("CityStorageArea")
	player._set_current_interactable(null)
	player.global_position = storage.get_node("Board").global_position + Vector2(-17, 13)
	for _frame: int in range(3):
		await get_tree().physics_frame
	player._refresh_current_interactable()
	_check(player.current_interactable == storage and storage.interactable_label_component.visible,
		"Front City Storage board owns E at night")
	var board_art: Rect2 = VISIBLE_BOUNDS.measure(storage.get_node("Board"))
	var board_box: Rect2 = storage.interactable_label_component.get_global_transform() * Rect2(Vector2.ZERO, storage.interactable_label_component.size)
	_check(is_equal_approx(board_box.get_center().x, board_art.get_center().x) and is_equal_approx(board_art.position.y - board_box.end.y, 2.0),
		"City Storage E is centered two pixels above its front board at night")
	await _capture("board-front")
	var storage_event := InputEventAction.new()
	storage_event.action = &"interact"
	storage_event.pressed = true
	player._unhandled_input(storage_event)
	_check(is_instance_valid(storage.menu) and storage.menu.visible,
		"City Storage board routes E through the native Player interaction handler")
	storage.close_menu()
	_check(saw_wood and saw_reed, "Normal night movement changes worksite focus from Wood to Reed")
	print("NightWorksiteWalkTest: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
