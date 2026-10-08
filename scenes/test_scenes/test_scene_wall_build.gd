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

func _move_away_from_wall_spot() -> void:
	player.global_position = wall_spot.global_position + Vector2(100, 0)
	await _settle_physics()
	player._refresh_current_interactable()
	await get_tree().process_frame

func _interact_with_wall_spot() -> void:
	var interact_event := InputEventAction.new()
	interact_event.action = &"interact"
	interact_event.pressed = true
	player._unhandled_input(interact_event)
	await get_tree().process_frame

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
	var paused_before: bool = get_tree().paused
	get_tree().paused = true
	ui.close_details()
	_expect(get_tree().paused, "Closing read-only Details does not unpause another menu.")
	get_tree().paused = paused_before

	# Moving into range selects the spot; the real Player interact action opens management.
	await _move_to_wall_spot()
	_expect(player.current_interactable == wall_spot and player.can_interact, "The nearest wall spot becomes Player's selected interaction in range.")
	await _interact_with_wall_spot()
	_expect(ui.details_panel.visible and ui.build_button.visible and not ui.build_button.disabled, "E opens wall management and exposes the free initial build.")
	_expect(player.can_move, "Opening wall management does not lock player movement.")
	_expect(ui.build_requested.get_connections().size() == 1, "Wall construction has exactly one UI request connection.")
	_check_bounds()
	await _capture("wall-ruins.png")

	# Moving out of range closes management and guards against a stale button click.
	player.global_position = wall_spot.global_position + Vector2(100, 0)
	ui.build_button.pressed.emit()
	await get_tree().process_frame
	_expect(state.wall_hp == 0 and state.wall_level == 0, "A Build click immediately after leaving geometry is rejected before physics exit.")
	await _settle_physics()
	player._refresh_current_interactable()
	await get_tree().process_frame
	_expect(player.can_move, "Player can walk away while wall management is open.")
	_expect(not ui.details_panel.visible, "Leaving the wall spot closes management.")
	ui.build_button.pressed.emit()
	await get_tree().process_frame
	_expect(state.wall_hp == 0 and state.wall_level == 0, "A stale out-of-range Build signal cannot construct the wall.")
	_expect(ui.build_requested.get_connections().size() == 1, "Leaving range does not duplicate or remove the build request connection.")

	await _move_to_wall_spot()
	_expect(player.current_interactable == wall_spot, "Returning to range selects the wall spot again.")
	await _interact_with_wall_spot()
	_expect(ui.details_panel.visible and ui.build_button.visible, "E reopens management after re-entering range.")
	ui.build_button.pressed.emit()
	await get_tree().process_frame
	_expect(state.wall_hp == 50 and state.wall_level == 1, "UI Build completes level 1 at 50 HP.")
	_expect(ui.hp_bar.value == 50 and ui.hp_bar.max_value == 50, "HP bar shows the actual full wall durability.")
	_expect(not ui.build_button.visible or ui.build_button.disabled, "A built wall cannot be built repeatedly.")
	_expect_wall_visual(1, wall_atlas, "Building changes every existing wall cell to the intact tile source while preserving coordinates")
	_expect(Inventory.items == original_inventory, "Instant free construction consumes no Inventory items.")
	_expect(original_clock == [TimeComponentManager.current_day, TimeComponentManager.current_hour, TimeComponentManager.current_minute], "Instant free construction consumes no game time.")
	await _capture("wall-level-one.png")
	var ledger: Node = state
	for index: int in range(3):
		await _move_away_from_wall_spot()
		await _move_to_wall_spot()
		await _interact_with_wall_spot()
		_expect(ui.details_panel.visible, "Wall management can reopen repeatedly after re-entering range.")
		ui.build_button.pressed.emit()
		await get_tree().process_frame
	_expect(not state.build_wall(), "Repeated requests do not rebuild or grant extra levels.")
	_expect(state.wall_hp == 50 and state.wall_level == 1, "Repeated management visits preserve level 1 and full HP.")
	_expect(ui.build_requested.get_connections().size() == 1, "Repeated management visits keep one construction callback.")
	_expect(ui.details_panel.visible, "The final management visit remains open for the map-exit check.")
	content.free()
	await _settle_physics()
	_expect(not ui.details_panel.visible, "Leaving the map frees the wall spot and closes management.")
	var home: Node = preload("res://scenes/player_home_interior/player_home_interior.tscn").instantiate()
	add_child(home)
	await get_tree().process_frame
	_expect(is_instance_valid(ledger) and ledger.wall_hp == 50 and ledger.wall_level == 1, "Wall state survives entering home.")
	home.free()
	await get_tree().process_frame
	_load_map()
	await _settle_physics()
	_expect(state == ledger and state.wall_hp == 50 and state.wall_level == 1, "Returning to the map retains the original wall ledger.")
	_expect(not ui.details_panel.visible, "Map reentry does not reopen stale wall management.")
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
