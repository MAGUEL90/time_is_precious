extends Node

var failures: int = 0
var content: Node
var state: Node
var ui: CanvasLayer
var player: Player
var wall_spot: Node2D
var wall_map: TileMapLayer

func _ready() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _load_map() -> void:
	content = preload("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(content)
	player = content.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = true
	wall_spot = content.get_node("YSortWorld/WallManagementSpot")
	wall_map = content.get_node("YSortWorld/WallStone")
	state = content.get_node("RaidBootstrap").state
	ui = state.get_node("RaidUI")

func _move_to_wall_spot() -> void:
	player.global_position = wall_spot.global_position + Vector2(0, 15)
	await _settle_physics()
	player._refresh_current_interactable()
	await get_tree().process_frame

func _get_greeting_balloon() -> BaseGameDialogueBalloon:
	return wall_spot.get("greeting_balloon") as BaseGameDialogueBalloon

func _open_wall_greeting() -> BaseGameDialogueBalloon:
	await _move_to_wall_spot()
	var interact_event := InputEventAction.new()
	interact_event.action = &"interact"
	interact_event.pressed = true
	player._unhandled_input(interact_event)
	var deadline: int = Time.get_ticks_msec() + 5000
	while not bool(wall_spot.call("_has_live_greeting_balloon")) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var balloon: BaseGameDialogueBalloon = _get_greeting_balloon()
	while is_instance_valid(balloon) and not is_instance_valid(balloon.dialogue_line) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(is_instance_valid(balloon) and is_instance_valid(balloon.dialogue_line), "E opens the native wall caretaker dialogue.")
	if not is_instance_valid(balloon) or not is_instance_valid(balloon.dialogue_line):
		return null
	if balloon.dialogue_label.is_typing:
		balloon.dialogue_label.skip_typing()
	while is_instance_valid(balloon) and not balloon.is_waiting_for_input and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(not get_tree().paused and not TimeComponentManager.is_paused and not player.can_move,
		"Wall dialogue holds Player movement without pausing the world clock.")
	return balloon

func _show_wall_responses(balloon: BaseGameDialogueBalloon) -> void:
	if not is_instance_valid(balloon):
		return
	if balloon.dialogue_label.is_typing:
		balloon.dialogue_label.skip_typing()
	balloon.show_responses()
	await get_tree().process_frame

func _visible_wall_responses(balloon: BaseGameDialogueBalloon) -> Array[String]:
	var texts: Array[String] = []
	if not is_instance_valid(balloon) or not balloon.responses_menu.visible:
		return texts
	for item: Control in balloon.responses_menu.get_menu_items():
		var response: DialogueResponse = item.get_meta("response") as DialogueResponse
		if is_instance_valid(response):
			texts.append(response.text.strip_edges())
	return texts

func _choose_wall_response(balloon: BaseGameDialogueBalloon, response_text: String) -> void:
	if not is_instance_valid(balloon):
		_expect(false, "A live wall greeting exists before response selection.")
		return
	if not balloon.responses_menu.visible:
		balloon.show_responses()
	var response_button: Control
	for item: Control in balloon.responses_menu.get_menu_items():
		var response: DialogueResponse = item.get_meta("response") as DialogueResponse
		if is_instance_valid(response) and response.text.strip_edges() == response_text:
			response_button = item
	_expect(is_instance_valid(response_button), "Wall greeting exposes the %s response." % response_text)
	if not is_instance_valid(response_button):
		return
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	response_button.gui_input.emit(click)

func _wait_for_wall_greeting_end() -> void:
	var deadline: int = Time.get_ticks_msec() + 5000
	while (bool(wall_spot.call("_has_live_greeting_balloon")) or not player.can_move or TimeComponentManager.is_paused) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(not bool(wall_spot.call("_has_live_greeting_balloon")), "Wall dialogue ends or cancels cleanly.")
	_expect(player.can_move and not get_tree().paused and not TimeComponentManager.is_paused,
		"Ending wall dialogue releases its Player movement lock without pausing time.")

func _settle_physics() -> void:
	for frame: int in range(5):
		await get_tree().physics_frame

func _wall_atlas_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for cell: Vector2i in wall_map.get_used_cells():
		snapshot[cell] = wall_map.get_cell_atlas_coords(cell)
	return snapshot

func _expect_wall_visual(source_id: int, atlas_snapshot: Dictionary, message: String) -> void:
	var current_cells: Array[Vector2i] = wall_map.get_used_cells()
	_expect(current_cells.size() == atlas_snapshot.size(), "%s (same tile count)" % message)
	for cell: Vector2i in atlas_snapshot:
		_expect(current_cells.has(cell), "%s (cell %s remains)" % [message, cell])
		_expect(wall_map.get_cell_source_id(cell) == source_id, "%s (cell %s source)" % [message, cell])
		_expect(wall_map.get_cell_atlas_coords(cell) == atlas_snapshot[cell], "%s (cell %s atlas)" % [message, cell])

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	_load_map()
	await _settle_physics()
	var original_inventory: Dictionary = Inventory.items.duplicate(true)
	var original_clock: Array = [TimeComponentManager.current_day, TimeComponentManager.current_hour, TimeComponentManager.current_minute]
	var wall_atlas: Dictionary = _wall_atlas_snapshot()
	_expect(state.wall_hp == 0 and state.wall_level == 0, "The main-map wall starts ruined and unbuilt.")
	_expect(not state.config.raids_enabled, "Build-first profile does not silently enable unapproved raid balance.")
	_expect(wall_spot.is_in_group("wall_management_spots"), "The wall spot participates in Player's nearest-interaction routing.")
	_expect(wall_map.get_used_cells().size() > 0, "The wall tilemap exposes its existing cells for visual-state checks.")

	# The status/details panel is informational. Even a forced button signal cannot build here.
	ui.open_details()
	await get_tree().process_frame
	_expect(ui.details_panel.visible, "Wall details can be opened from the read-only status UI.")
	_expect(not ui.build_button.visible, "Read-only wall details do not expose Build.")
	ui.build_button.pressed.emit()
	await get_tree().process_frame
	_expect(state.wall_hp == 0 and state.wall_level == 0, "A forced Build signal from read-only Details cannot construct the wall.")
	_check_bounds()
	var paused_before: bool = get_tree().paused
	get_tree().paused = true
	ui.close_details()
	_expect(get_tree().paused, "Closing read-only Details does not unpause another menu.")
	get_tree().paused = paused_before

	# The real Player interaction opens the caretaker dialogue; declining has no effects.
	await _move_to_wall_spot()
	_expect(player.current_interactable == wall_spot and player.can_interact, "The nearest wall spot becomes Player's selected interaction in range.")
	var greeting: BaseGameDialogueBalloon = await _open_wall_greeting()
	_expect(greeting.dialogue_line.text.to_lower().contains("tembok"), "The caretaker shows the introductory wall dialogue before responses.")
	await _show_wall_responses(greeting)
	var response_texts: Array[String] = _visible_wall_responses(greeting)
	_expect(response_texts.size() == 2 and response_texts.has("Perbaiki tembok (gratis)") and response_texts.has("Nanti saja"),
		"A ruined wall offers free construction or declining.")
	_choose_wall_response(greeting, "Nanti saja")
	await _wait_for_wall_greeting_end()
	_expect(state.wall_hp == 0 and state.wall_level == 0, "Declining the caretaker dialogue leaves the ruined wall unchanged.")
	_expect(Inventory.items == original_inventory and original_clock == [TimeComponentManager.current_day, TimeComponentManager.current_hour, TimeComponentManager.current_minute],
		"Declining does not change inventory or game time.")
	_expect(ui.build_requested.get_connections().size() == 1, "Wall construction has exactly one UI request connection.")
	await _capture("wall-ruins.png")

	# A response selected after leaving the spot is rejected before physics reports body exit.
	greeting = await _open_wall_greeting()
	await _show_wall_responses(greeting)
	response_texts = _visible_wall_responses(greeting)
	_expect(response_texts.has("Perbaiki tembok (gratis)"), "The caretaker offers work while the wall is ruined and Player is nearby.")
	player.global_position = wall_spot.global_position + Vector2(100, 0)
	_choose_wall_response(greeting, "Perbaiki tembok (gratis)")
	await _settle_physics()
	player._refresh_current_interactable()
	await _wait_for_wall_greeting_end()
	_expect(state.wall_hp == 0 and state.wall_level == 0, "Leaving range while choosing work cannot build from a stale dialogue response.")
	_expect(Inventory.items == original_inventory, "Out-of-range dialogue cancellation does not affect Inventory.")

	# Returning to range allows the actual dialogue response to build the wall.
	greeting = await _open_wall_greeting()
	await _show_wall_responses(greeting)
	response_texts = _visible_wall_responses(greeting)
	_expect(player.current_interactable == wall_spot and response_texts.has("Perbaiki tembok (gratis)"), "Returning to range restores the caretaker work response.")
	_choose_wall_response(greeting, "Perbaiki tembok (gratis)")
	await _wait_for_wall_greeting_end()
	_expect(state.wall_hp == 50 and state.wall_level == 1, "The real dialogue response builds level 1 at 50 HP.")
	_expect(ui.hp_bar.value == 50 and ui.hp_bar.max_value == 50, "HP bar shows the actual full wall durability.")
	_expect(not ui.build_button.visible and not ui.repair_button.visible, "Read-only details expose no build or repair action after construction.")
	_expect_wall_visual(1, wall_atlas, "Building changes every existing wall cell to the intact tile source while preserving coordinates")
	_expect(Inventory.items == original_inventory, "Instant free construction consumes no Inventory items.")
	_expect(original_clock == [TimeComponentManager.current_day, TimeComponentManager.current_hour, TimeComponentManager.current_minute], "Instant free construction consumes no game time.")
	await _capture("wall-level-one.png")
	ui.open_details()
	await get_tree().process_frame
	ui.build_button.pressed.emit()
	ui.repair_button.pressed.emit()
	await get_tree().process_frame
	_expect(not ui.build_button.visible and not ui.repair_button.visible and state.wall_hp == 50,
		"Opening read-only Details and forcing both action signals cannot build or repair.")
	ui.close_details()
	var ledger: Node = state
	for index: int in range(3):
		greeting = await _open_wall_greeting()
		await _show_wall_responses(greeting)
		response_texts = _visible_wall_responses(greeting)
		_expect(response_texts.size() == 1 and response_texts[0] == "Nanti saja", "A full wall does not offer unnecessary free repairs.")
		_choose_wall_response(greeting, "Nanti saja")
		await _wait_for_wall_greeting_end()
	_expect(not state.build_wall(), "Repeated requests do not rebuild or grant extra levels.")
	_expect(state.wall_hp == 50 and state.wall_level == 1, "Repeated caretaker visits preserve level 1 and full HP.")
	_expect(ui.build_requested.get_connections().size() == 1, "Repeated caretaker visits retain the legacy construction connection exactly once.")
	greeting = await _open_wall_greeting()
	var exit_balloon: BaseGameDialogueBalloon = greeting
	content.free()
	await get_tree().process_frame
	_expect(not is_instance_valid(exit_balloon), "Freeing the map cancels its active caretaker dialogue balloon.")
	_expect(not ui.details_panel.visible, "Leaving the map does not open or retain a wall action panel.")
	var home: Node = preload("res://scenes/player_home_interior/player_home_interior.tscn").instantiate()
	add_child(home)
	await get_tree().process_frame
	_expect(is_instance_valid(ledger) and ledger.wall_hp == 50 and ledger.wall_level == 1, "Wall state survives entering home.")
	home.free()
	await get_tree().process_frame
	_load_map()
	await _settle_physics()
	_expect(state == ledger and state.wall_hp == 50 and state.wall_level == 1, "Returning to the map retains the original wall ledger.")
	_expect(not ui.details_panel.visible and player.can_move, "Map reentry has no stale caretaker action or movement lock.")
	_expect(not bool(wall_spot.call("_has_live_greeting_balloon")), "Map reentry does not retain the old caretaker dialogue.")
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
