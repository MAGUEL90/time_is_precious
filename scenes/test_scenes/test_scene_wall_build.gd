extends Node

var failures: int = 0
var content: Node
var state: Node
var ui: CanvasLayer

func _ready() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _load_map() -> void:
	content = preload("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(content)
	content.get_node("YSortWorld/Player").debug_disable_player_needs = true
	state = content.get_node("RaidBootstrap").state
	ui = state.get_node("RaidUI")

func _run() -> void:
	TimeComponentManager.set_process(false)
	_load_map()
	await get_tree().process_frame
	var original_inventory: Dictionary = Inventory.items.duplicate(true)
	var original_clock: Array = [TimeComponentManager.current_day, TimeComponentManager.current_hour, TimeComponentManager.current_minute]
	_expect(state.wall_hp == 0 and state.wall_level == 0, "The main-map wall starts ruined and unbuilt.")
	_expect(not state.config.raids_enabled, "Build-first profile does not silently enable unapproved raid balance.")
	ui.open_details()
	await get_tree().process_frame
	_expect(ui.build_button.visible and not ui.build_button.disabled, "Build is accessible in the wall details.")
	_check_bounds()
	await _capture("wall-ruins.png")
	ui.build_button.pressed.emit()
	await get_tree().process_frame
	_expect(state.wall_hp == 50 and state.wall_level == 1, "UI Build completes level 1 at 50 HP.")
	_expect(ui.hp_bar.value == 50 and ui.hp_bar.max_value == 50, "HP bar shows the actual full wall durability.")
	_expect(not ui.build_button.visible or ui.build_button.disabled, "A built wall cannot be built repeatedly.")
	_expect(Inventory.items == original_inventory, "Instant free construction consumes no Inventory items.")
	_expect(original_clock == [TimeComponentManager.current_day, TimeComponentManager.current_hour, TimeComponentManager.current_minute], "Instant free construction consumes no game time.")
	await _capture("wall-level-one.png")
	var ledger: Node = state
	for index: int in range(3):
		ui.close_details()
		ui.open_details()
	_expect(not state.build_wall(), "Repeated requests do not rebuild or grant extra levels.")
	_expect(ui.details_panel.visible, "Details can reopen repeatedly.")
	var paused_before: bool = get_tree().paused
	get_tree().paused = true
	ui.close_details()
	_expect(get_tree().paused, "Closing wall details does not unpause another menu.")
	get_tree().paused = paused_before
	content.free()
	await get_tree().process_frame
	var home: Node = preload("res://scenes/player_home_interior/player_home_interior.tscn").instantiate()
	add_child(home)
	await get_tree().process_frame
	_expect(is_instance_valid(ledger) and ledger.wall_hp == 50 and ledger.wall_level == 1, "Wall state survives entering home.")
	home.free()
	await get_tree().process_frame
	_load_map()
	await get_tree().process_frame
	_expect(state == ledger and state.wall_hp == 50 and state.wall_level == 1, "Returning to the map retains the original wall ledger.")
	_expect(state.get_child_count() == 1, "Map reentry does not duplicate the wall HUD.")
	state._on_time_changed(TimeComponentManager.current_day + 100, 12, 0, "clear")
	_expect(state.phase == "safe" and state.wall_hp == 50, "Passing days cannot attack the build-only playtest.")
	_expect(ui.build_requested.get_connections().size() == 1, "Map reentry does not duplicate construction callbacks.")
	content.free()
	print("WallBuildTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _check_bounds() -> void:
	var viewport_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	_expect(viewport_rect.encloses(ui.details_panel.get_global_rect()), "Wall details fit the logical viewport.")

func _capture(file_name: String) -> void:
	var folder: String = OS.get_environment("TIP_RAID_CAPTURE_DIR")
	if folder.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join(file_name))
