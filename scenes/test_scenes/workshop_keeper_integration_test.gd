extends "res://scenes/test_scenes/test_scene_workshop_arrival_schema8.gd"

## Isolated fixture: adds keeper UI/geometry checks to the native schema8 lifecycle.
const KEEPER_BOUNDS = preload("res://scenes/workshop_plot/keeper/workshop_visual_bounds.gd")
var _keeper_checked := false
var _built_checked := false

func load_content() -> void:
	await super.load_content()
	if _keeper_checked:
		return
	_keeper_checked = true
	if DisplayServer.get_name() != "headless":
		get_window().title = "Time is Precious - Isolated Keeper Integration QA"
	var plot: Node2D = content.get_node("YSortWorld/WorkshopPlot")
	var other: Node2D = content.get_node("YSortWorld/WorkshopPlot2")
	_expect(plot.position == Vector2(-312, -482) and other.position == Vector2(-199, -482), "Both native authored plot locations remain unchanged.")
	_expect(plot.has_node("Craftsman") and not other.has_node("Craftsman") and other.get_node("Board").visible, "Only the main workshop replaces its board with the keeper.")
	_expect(plot.get_worker_entry_position() == plot.global_position + Vector2(0, 24) and plot.construction.worker_entry_position == plot.get_worker_entry_position(), "Native authored schema8 feet target remains unchanged.")
	var keeper: Node2D = plot.get_node("Craftsman")
	var original_phase: String = plot.construction.phase
	var original_inventory: Dictionary = Inventory.items.duplicate(true)
	# Presentation-only stage probes do not start work or invoke payment actions.
	for phase: String in ["uncleared", "clearing", "empty", "building"]:
		plot.construction.phase = phase
		plot._sync_construction()
		_expect(not plot.get_node("InteractableLabelComponent/HammerIcon").visible
			and plot.get_node("InteractableLabelComponent/InteractionKey").visible
			and plot.get_node("InteractableLabelComponent/InteractionKey").text == "E",
			"Keeper uses E without hand/hammer in phase " + phase)
	plot.construction.phase = original_phase
	plot._sync_construction()
	_expect(Inventory.items == original_inventory, "Prompt stage refresh never charges inventory or starts work.")
	var saved_player_position: Vector2 = player.global_position
	for offset: Vector2 in [Vector2(-20, 9), Vector2(-0.5, 20), Vector2(20, 9), Vector2(0.5, 20)]:
		player.global_position = keeper.global_position + offset
		await _keeper_frames(3)
		var expected: String = "left" if offset.x < 0 else "right"
		_expect(keeper.facing == expected, "Keeper follows native horizontal facing and retains its one-pixel deadzone.")
		for layer: AnimatedSprite2D in keeper.get_children():
			_expect(layer.animation == keeper.body.animation and layer.frame == keeper.body.frame and not layer.flip_h, "Bald head, brown beard and sash share authored direction and frame.")
		plot._update_keeper_hint()
		var keeper_bounds: Rect2 = KEEPER_BOUNDS.measure(keeper)
		var hint: Control = plot.interactable_label_component
		var hint_rect: Rect2 = hint.get_global_transform() * Rect2(Vector2.ZERO, hint.size)
		_expect(is_equal_approx(keeper_bounds.position.y - hint_rect.end.y, 4.0)
			and is_equal_approx(keeper_bounds.get_center().x, hint_rect.get_center().x), "Keeper E remains centered four pixels above visible directional art.")
	for adjacent: Vector2 in [Vector2(-16, 0), Vector2(16, 0), Vector2(0, 16)]:
		player.global_position = keeper.global_position + adjacent
		await _settle_physics()
		_expect(player.current_interactable == plot and plot.has_player_access(), "Native E offers the keeper from adjacent reachable sides at sixteen logical pixels.")
	player.global_position = keeper.global_position + Vector2(0, 9)
	await _settle_physics()
	_expect(player.current_interactable == plot and plot.has_player_access(), "Physical NPC range selects the main plot's native E owner.")
	var stock: Dictionary = Inventory.items.duplicate(true)
	var interact_event := InputEventAction.new()
	interact_event.action = &"interact"
	interact_event.pressed = true
	player._unhandled_input(interact_event)
	await _keeper_frames(8)
	_expect(is_instance_valid(plot.keeper_dialogue) and not player.can_move and not get_tree().paused, "Keeper dialogue locks movement while native time and world remain unpaused.")
	if is_instance_valid(plot.keeper_dialogue):
		var balloon: BaseGameDialogueBalloon = plot.keeper_dialogue.balloon
		await _show_responses(balloon)
		await _keeper_frames(3)
		_expect(balloon.scene_file_path == "res://dialogue/game_dialogue_balloon/game_dialogue_balloon.tscn" and balloon.chat_box_root.size == Vector2(176, 78), "Keeper uses the existing wall caretaker balloon and dimensions.")
		_check_keeper_layout(balloon, true)
		await _capture_keeper("uncleared-dialogue")
		var camera: Camera2D = player.get_node("Camera2D")
		var previous_offset: Vector2 = camera.offset
		camera.offset = previous_offset + Vector2(0, -100)
		camera.force_update_scroll()
		await _keeper_frames(3)
		_check_keeper_layout(balloon, false)
		camera.offset = previous_offset
		camera.force_update_scroll()
		_choose_response(balloon, "Not now")
		await _keeper_frames(12)
	_expect(not is_instance_valid(plot.keeper_dialogue) and player.can_move and Inventory.items == stock and plot.construction.phase == "uncleared", "Not now restores controls without costs or construction.")
	plot.on_player_interact(player)
	await _keeper_frames(8)
	if is_instance_valid(plot.keeper_dialogue):
		await _show_responses(plot.keeper_dialogue.balloon)
		_choose_response(plot.keeper_dialogue.balloon, "Continue")
		await _keeper_frames(12)
	_expect(is_instance_valid(plot.menu) and get_tree().paused and not player.can_move, "Continue opens the unchanged native construction menu.")
	plot.close_menu()
	await _keeper_frames(3)
	_expect(player.can_move and not get_tree().paused, "Closing the native menu restores pause and movement.")
	plot.on_player_interact(player)
	await _keeper_frames(5)
	player.global_position = keeper.global_position + Vector2(80, 80)
	await _keeper_frames(4)
	_expect(not is_instance_valid(plot.keeper_dialogue) and player.can_move, "Leaving dialogue range closes the balloon and clears only its movement lock.")
	player.global_position = saved_player_position
	await _settle_physics()

func _check_keeper_layout(balloon: BaseGameDialogueBalloon, normal: bool) -> void:
	var transform: Transform2D = balloon.chat_box_root.get_global_transform_with_canvas()
	var group: Rect2 = transform * Rect2(Vector2.ZERO, balloon.chat_box_root.size)
	var panel: Control = balloon.chat_box_root.get_node("TemplateDialogue")
	var panel_rect: Rect2 = panel.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, panel.size)
	var responses: Control = balloon.responses_menu
	var response_rect: Rect2 = responses.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, responses.size)
	var player_rect: Rect2 = get_viewport().get_canvas_transform() * KEEPER_BOUNDS.measure(player.get_node("PlayerVisual"))
	_expect(response_rect.end.y <= panel_rect.position.y and responses.visible, "Continue and Not now appear above the native text panel.")
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_expect(group.position.x >= 3.9 and group.position.y >= 3.9 and group.end.x <= viewport_size.x - 3.9 and group.end.y <= viewport_size.y - 3.9, "Entire keeper balloon stays inside its viewport (balloon %s, viewport %s)." % [group, viewport_size])
	_expect(balloon.dialogue_label.get_content_height() <= balloon.dialogue_label.size.y + 1, "Full English greeting fits the native text area.")
	if normal:
		_expect(group.position.y - player_rect.end.y >= 5 and group.position.y - player_rect.end.y <= 10, "Balloon appears eight pixels below visible player art.")
	else:
		_expect(not group.intersects(player_rect), "Viewport-edge fallback avoids overlapping the player.")

func _keeper_frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame

func _drive_arrival(worker_id: String = ARRIVAL_WORKER) -> void:
	print("Keeper arrival checkpoint: ", arrival_plot.construction.phase if is_instance_valid(arrival_plot) else "home", " worker=", worker_id)
	_check_approach_checkpoint("Pending")
	super._drive_arrival(worker_id)
	_check_approach_checkpoint("Arrived")
	if is_instance_valid(arrival_plot) and arrival_plot.construction.phase == "built" and not _built_checked:
		_built_checked = true
		var building: Node2D = arrival_plot.get_node("FinishedBuilding")
		_expect(building.visible and not building.y_sort_enabled and building.position == Vector2(11, 24) and building.get_child_count() == 3 and not arrival_plot.has_node("FinishedBuilding/OutputIcon"), "Complete art and roof ornaments sort together, with no output overlay.")
		var base: Sprite2D = building.get_node("Base")
		var vase: Sprite2D = building.get_node("Vase")
		var barrel: Sprite2D = building.get_node("Barrel")
		_assert_art(base, "res://assets/objects/workshop_1.png", Vector2i(48, 64), "be1a9b13091da67b75db80ec951004279930708b0957b50d238fe91a50c2772c")
		_assert_art(vase, "res://assets/objects/vase_type_1.png", Vector2i(16, 16), "e815ef10ae5f197d24d5ccbe64f49a11425404c580065f272cc193c987116a63")
		_assert_art(barrel, "res://assets/objects/barrel.png", Vector2i(16, 16), "58cd76e7d54d573787df34962d27a691fd66e787cd79dd5eacc2bbf6e926b36e")
		_expect(arrival_plot.construction.worker_entry_position == arrival_plot.global_position + Vector2(0, 24), "Built production preserves the exact schema8 feet target.")
		_expect(arrival_plot.get_node("BuiltWorkshop/InteractableLabelComponent/NinePatchRect/Label").text == "E",
			"Completed workshop preserves its native E prompt.")

func _finish_arrival() -> void:
	_finish_keeper.call_deferred()

func _finish_keeper() -> void:
	await _settle_physics()
	if is_instance_valid(arrival_plot) and arrival_plot.construction.phase == "built":
		var navigation: RefCounted = arrival_visuals.get_parent().worksite_navigation
		if navigation != null:
			_expect(navigation.segment_clear(arrival_plot.global_position + Vector2(0, 36), arrival_plot.global_position + Vector2(0, 15)), "Native route clearance fits the twelve-pixel door.")
		var original: Vector2 = player.global_position
		player.global_position = arrival_plot.global_position + Vector2(0, 36)
		_expect(player.move_and_collide(Vector2(0, -14)) == null, "Actual player body enters the aligned door opening.")
		_expect(player.move_and_collide(Vector2(0, -15)) != null, "Actual player stops at the rear workshop footprint.")
		player.global_position = original
		player.global_position = arrival_plot.get_node("Craftsman").global_position + Vector2(0, 9)
		await _settle_physics()
		var backend: WorkShop = arrival_plot.get_node("BuiltWorkshop")
		_expect(player.current_interactable == backend and not arrival_plot.interaction_area.monitoring, "Built keeper range has exactly one native WorkShop E owner.")
		var interact := InputEventAction.new()
		interact.action = &"interact"
		interact.pressed = true
		player._unhandled_input(interact)
		await _keeper_frames(3)
		_expect(player.claim_menu_is_open and get_tree().paused and not is_instance_valid(arrival_plot.keeper_dialogue), "Physical built E opens the native workshop menu without a blank greeting.")
		var native_menu: WorkshopMenuUI
		for child: Node in get_tree().current_scene.get_children():
			if child is WorkshopMenuUI:
				native_menu = child
		_expect(is_instance_valid(native_menu), "The built interaction creates the real WorkshopMenuUI.")
		if is_instance_valid(native_menu):
			native_menu.close_button.pressed.emit()
		await _keeper_frames(3)
		_expect(not player.claim_menu_is_open and not get_tree().paused and player.can_move, "Closing built menu restores native controls.")
		player.global_position = arrival_plot.global_position + Vector2(0, 46)
		await _settle_physics()
		await _capture_keeper("built-workshop")
		player.global_position = original
	print("WorkshopKeeperIntegrationTest: ", "PASS" if failures == 0 else "FAIL")
	super._finish_arrival()

func _capture_keeper(label: String) -> void:
	var directory: String = OS.get_environment("TIP_MVP_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _keeper_frames(3)
	await RenderingServer.frame_post_draw
	var picture: Image = get_viewport().get_texture().get_image()
	if picture.get_size() == Vector2i(400, 225):
		picture.resize(1200, 675, Image.INTERPOLATE_NEAREST)
	_expect(picture.save_png(directory.path_join("keeper-" + label + ".png")) == OK, "Keeper render evidence saves successfully.")

func _check_approach_checkpoint(label: String) -> void:
	# The inherited home parking probe deliberately detaches the plot while still
	# passing the old city map. Its actual home write/read modes use capture(home).
	if not is_instance_valid(arrival_plot) or not arrival_plot.is_inside_tree():
		return
	var document: Dictionary = arrival_snapshot.capture(content)
	_expect(not document.is_empty(), label + " keeper approach captures through the native save writer: " + arrival_snapshot.error)
	if not document.is_empty():
		_expect(arrival_snapshot.prepare(JSON.parse_string(JSON.stringify(document, "", true, true)), content), label + " keeper approach validates without schema or target changes: " + arrival_snapshot.error)

func _assert_art(sprite: Sprite2D, path: String, dimensions: Vector2i, source_sha256: String) -> void:
	_expect(sprite.texture != null and sprite.texture.get_size() == Vector2(dimensions), "Actual owner texture loads at its original dimensions: " + path)
	_expect(FileAccess.get_sha256(path) == source_sha256, "Owner PNG bytes remain identical: " + path)
	if sprite.texture == null:
		return
	var imported: Image = sprite.texture.get_image()
	var source := Image.new()
	source.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	_expect(imported != null and source != null, "Imported and source pixels are inspectable: " + path)
	if imported == null or source == null:
		return
	if imported.is_compressed():
		imported.decompress()
	imported.convert(Image.FORMAT_RGBA8)
	source.convert(Image.FORMAT_RGBA8)
	var visible_mismatches: int = 0
	var transparent_rgb_changes: int = 0
	if imported.get_size() == dimensions:
		for y: int in range(dimensions.y):
			for x: int in range(dimensions.x):
				var original: Color = source.get_pixel(x, y)
				var actual: Color = imported.get_pixel(x, y)
				if actual.a != original.a or (original.a > 0.0 and actual != original):
					visible_mismatches += 1
				elif original.a == 0.0 and actual != original:
					transparent_rgb_changes += 1
	# Existing Godot fix_alpha_border fills invisible RGB to prevent edge halos.
	# Alpha and every visible pixel must still match; original PNG SHA is checked above.
	print("Keeper art pixels: ", path, " visible_mismatches=", visible_mismatches, " transparent_rgb_changes=", transparent_rgb_changes)
	_expect(imported.get_size() == dimensions and visible_mismatches == 0, "Imported alpha and visible pixels match the original PNG exactly: " + path)
