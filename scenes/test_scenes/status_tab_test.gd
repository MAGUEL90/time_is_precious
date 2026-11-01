extends Node
var failures := 0
var world_clicks := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func tab(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_TAB
	event.physical_keycode = KEY_TAB
	event.pressed = pressed
	get_viewport().push_input(event)
	await get_tree().create_timer(0.2).timeout

func move_mouse(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	get_viewport().push_input(event, true)
	await get_tree().process_frame

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		world_clicks += 1

func click(at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	get_viewport().push_input(event, true)
	await get_tree().process_frame
	event.pressed = false
	get_viewport().push_input(event, true)
	await get_tree().process_frame

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	TimeComponentManager.set_process(false)
	for scene_path in ["res://scenes/content_scene/content_scene.tscn", "res://scenes/player_home_interior/player_home_interior.tscn", "res://scenes/content_scene/content_scene.tscn"]:
		var map = load(scene_path).instantiate()
		add_child(map)
		await get_tree().process_frame
		var hud = map.get_node("BottomHUD")
		var player = map.get_node("YSortWorld/Player")
		check(hud.visible, "Status HUD visible on normal scene entry: " + scene_path)
		check(not hud.status_drawer.visible, "Drawer starts closed")
		check(hud.fatigue_indicator.is_visible_in_tree() and hud.hunger_indicator.is_visible_in_tree(), "Both condition indicators are always visible during gameplay")
		check(not hud.fatigue_label.visible and not hud.hunger_label.visible, "Neither label is shown by default")
		var top_bar: Control = map.get_node("TopHUD/Root/Bar")
		check(not hud.fatigue_indicator.get_global_rect().intersects(top_bar.get_global_rect()) and not hud.hunger_indicator.get_global_rect().intersects(top_bar.get_global_rect()), "Condition indicators do not overlap the time and weather bar")
		check(absf(hud.fatigue_indicator.global_position.y - top_bar.global_position.y) <= 1.0, "Condition indicators align with the top bar")
		await move_mouse(Vector2(399, 224))
		await move_mouse(hud.fatigue_indicator.get_node("Icon").get_global_rect().get_center())
		check(hud.fatigue_label.visible and not hud.hunger_label.visible, "Hovering the Energy icon shows only Energy")
		await move_mouse(hud.hunger_indicator.get_node("Icon").get_global_rect().get_center())
		check(not hud.fatigue_label.visible and hud.hunger_label.visible, "Hovering the Belly icon shows only Belly")
		await move_mouse(hud.hunger_bar.get_global_rect().get_center())
		check(not hud.fatigue_label.visible and not hud.hunger_label.visible, "Hovering a bar does not show a label")
		var clicks_before: int = world_clicks
		await click(hud.fatigue_indicator.get_node("Icon").get_global_rect().get_center())
		await click(hud.hunger_indicator.get_node("Icon").get_global_rect().get_center())
		check(world_clicks == clicks_before + 2, "Status icons do not consume ordinary world clicks")
		for cycle in range(2):
			await tab(true)
			check(hud.visible and hud.status_drawer.is_visible_in_tree(), "Physical Tab reveals status")
			check(is_equal_approx(hud.status_drawer.offset_top, hud.DRAWER_OPEN_Y), "Status opens inside viewport")
			check(hud.hunger_bar.value == 100 - player.get_hunger_percent(), "Status displays current Belly")
			var folder := OS.get_environment("TIP_STATUS_CAPTURE_DIR")
			if cycle == 0 and not folder.is_empty() and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(folder.path_join(str(map.name) + ".png"))
			await tab(false)
			check(not hud.status_drawer.visible, "Releasing Tab hides drawer")
		var inventory = map.get_node_or_null("InventoryUI")
		if inventory != null:
			await move_mouse(hud.fatigue_indicator.get_node("Icon").get_global_rect().get_center())
			check(hud.fatigue_label.visible, "Energy label opens before the inventory interruption")
			await tab(true)
			inventory.open_inventory()
			check(not hud.status_drawer.visible, "Opening inventory closes an already held EXP drawer")
			check(not hud.fatigue_label.visible and not hud.hunger_label.visible, "Opening inventory clears condition hover labels")
			await tab(false)
			inventory.close_inventory()
			check(not hud.status_drawer.visible, "Releasing Tab during inventory cannot leave EXP stuck open")
			inventory.open_inventory()
			await tab(true)
			check(not hud.status_drawer.visible, "Inventory modal keeps status shortcut blocked")
			await tab(false)
			inventory.close_inventory()
			await tab(true)
			var balloon = load("res://dialogue/game_dialogue_balloon/game_dialogue_balloon.tscn").instantiate()
			add_child(balloon)
			var resource = DialogueManager.create_resource_from_text("~ start\nNarrator: Test.\n=> END")
			balloon.start(resource, "start")
			await get_tree().create_timer(0.2).timeout
			await move_mouse(Vector2(399, 224))
			await move_mouse(hud.fatigue_indicator.get_node("Icon").get_global_rect().get_center())
			check(not hud.fatigue_label.visible and not hud.hunger_label.visible, "A dialogue overlay blocks condition hover labels")
			await tab(false)
			check(not hud.status_drawer.visible, "Releasing Tab during dialogue closes EXP")
			await tab(true)
			check(not hud.status_drawer.visible, "Dialogue blocks the status shortcut")
			await tab(false)
			balloon.queue_free()
			await get_tree().process_frame
		await tab(true)
		hud.nightmare_world_ref.nightmare_active_changed.emit(true)
		check(not hud.visible and not hud.is_processing_unhandled_input(), "Nightmare hides status and disables input")
		await tab(false)
		check(not hud.status_drawer.visible, "Nightmare resets held drawer")
		hud.nightmare_world_ref.nightmare_active_changed.emit(false)
		await tab(true)
		check(hud.visible and hud.status_drawer.is_visible_in_tree(), "Tab works after Nightmare visibility reset")
		await tab(false)
		map.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("StatusTabTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().call_deferred("quit", 0 if failures == 0 else 1)
