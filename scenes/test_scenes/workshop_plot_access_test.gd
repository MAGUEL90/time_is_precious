extends Node

var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	get_viewport().push_input(event)
	await get_tree().process_frame

func _run() -> void:
	TimeComponentManager.is_paused = true
	var content = load("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(content)
	var player: Player = content.get_node("YSortWorld/Player")
	var plot = content.get_node("YSortWorld/WorkshopPlot")
	for path in ["Ground/water", "Ground/base", "Ground/base2", "YSortWorld/object"]:
		var layer: TileMapLayer = content.get_node(path)
		_expect(layer.tile_set.get_source_count() == 1, "Only the replacement atlas belongs in the authoring map.")
		var atlas: TileSetAtlasSource = layer.tile_set.get_source(0)
		_expect(atlas.texture.resource_path == "res://assets/tile_set/tile_set_base_new_28_09_2026.png", "Every layer must use the supplied tileset.")
		for index in range(atlas.get_tiles_count()):
			var coords: Vector2i = atlas.get_tile_id(index)
			_expect(coords.x < 18 and coords.y < 16, "Atlas tiles must stay inside the supplied 288x256 texture.")
	_expect(content.get_node("YSortWorld/WorkerRuntime").sites.size() == 5, "Main map contains five resource sites.")
	_expect(content.get_node("YSortWorld/WorkerRuntime").storage_destinations.size() == 5, "Each site has a matching stockpile.")
	_expect(content.get_node("YSortWorld/WorkshopPlot/Label").text.is_empty(), "Uncleared plot has no debug title.")
	_expect(not player.debug_disable_player_needs and not player.debug_disable_fatigue, "Normal map startup enables player needs.")
	# This separate construction access fixture intentionally accelerates multiple days.
	content.get_node("TimeDebugOverlay").set_player_guard(true)
	var stock_before: Dictionary = WorkShopStorage.items.duplicate(true)
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	plot.on_player_interact(player)
	_expect(not is_instance_valid(plot.menu), "Out-of-range access must be rejected.")
	player.global_position = plot.get_node("InteractableComponent").global_position + Vector2(0, 4)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	_expect(player.current_interactable == plot, "Approaching the authored plot must select its E interaction.")
	_expect(plot.get_node("Board").self_modulate.r > 1.0, "Selected plot artwork must be highlighted.")
	_expect(plot.interactable_label_component.visible, "Approaching plot must reveal the hand prompt.")
	_expect(plot.interactable_label_component.size == Vector2(16, 16), "Hammer backdrop must remain native 16x16.")
	_expect(plot.get_node("InteractableLabelComponent/HammerIcon").texture.resource_path == "res://assets/ui/ui_icon/hand_job_icon.png", "Hand must be drawn over the prompt panel.")
	get_tree().paused = true
	plot.on_player_interact(player)
	_expect(not is_instance_valid(plot.menu), "Plot must not open over another paused modal.")
	get_tree().paused = false
	await _capture("plot")
	await _press("interact")
	_expect(is_instance_valid(plot.menu), "E must open plot menu through Player input.")
	if not is_instance_valid(plot.menu):
		_finish(content)
		return
	_expect(get_tree().paused and not player.can_move, "Plot menu must pause the game and lock movement.")
	var first_menu = plot.menu
	await _press("open_inventory")
	await _press("open_work_progress")
	await _press("interact")
	_expect(plot.menu == first_menu, "Shortcuts must not create duplicate plot menus.")
	_expect(not content.get_node("InventoryUI").visible, "Inventory must not open over plot menu.")
	_expect(not content.get_node("WorkProgressUI/Root").visible, "Progress must not open over plot menu.")
	_expect(plot.menu.find_child("HammerButton", true, false) == null, "No intermediate hammer panel should remain.")
	await _capture("requirements")
	var build: Button = plot.menu.find_child("BuildButton", true, false)
	_expect(build != null and build.disabled, "Construction must remain unavailable without approved requirements.")
	_expect(build != null and build.is_visible_in_tree(), "E must open clearing assignment directly.")
	_expect(plot.menu.find_child("DebugSupplyButton", true, false) == null, "No debug supply control remains in gameplay UI.")
	await _press("ui_cancel")
	_expect(not is_instance_valid(plot.menu) and not get_tree().paused and player.can_move, "Closing must restore movement and pause state.")
	await _press("interact")
	_expect(is_instance_valid(plot.menu), "Plot menu must reopen.")
	player.global_position = plot.global_position + Vector2(100, 100)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not is_instance_valid(plot.menu) and not get_tree().paused, "Leaving range even while paused must close the menu.")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(plot.get_node("Board").self_modulate == Color.WHITE, "Leaving the plot restores its authored color.")
	player.global_position = plot.get_node("InteractableComponent").global_position + Vector2(0, 4)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	await _press("interact")
	_expect(is_instance_valid(plot.menu), "Plot must remain usable after leaving and returning.")
	plot.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not get_tree().paused and player.can_move, "Removing an open plot must restore controls.")
	_expect(WorkShopStorage.items == stock_before and Inventory.items == inventory_before, "Plot preview must never change inventory or workshop stock.")
	var board = content.get_node("YSortWorld/InitialWorksites/JobBoard")
	player.global_position = board.global_position + Vector2(0, 4)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
	_expect(player.current_interactable == board, "Job Board must retain its interaction after map cleanup.")
	_expect(board.interactable_label_component.size == Vector2(16, 16), "E panel matches the 16x16 clean/build panel.")
	_expect(board.get_node("Sprite2D").self_modulate.r > 1.0, "Job Board receives the shared interaction highlight.")
	await _capture("board-highlight")
	await _press("interact")
	_expect(is_instance_valid(board.job_board_ui), "E must still open Job Board.")
	if is_instance_valid(board.job_board_ui):
		board.job_board_ui.close()
	await get_tree().process_frame
	_finish(content)

func _capture(suffix: String) -> void:
	var folder := OS.get_environment("TIP_PLOT_CAPTURE_DIR")
	if folder.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join("workshop-" + suffix + ".png"))

func _finish(content: Node) -> void:
	get_tree().paused = false
	content.free()
	print("WorkshopPlotAccessTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
