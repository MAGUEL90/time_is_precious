extends Node
var failures := 0

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
		for cycle in range(2):
			await tab(true)
			check(hud.visible and hud.status_drawer.is_visible_in_tree(), "Physical Tab reveals status")
			check(is_equal_approx(hud.status_drawer.offset_top, hud.DRAWER_OPEN_Y), "Status opens inside viewport")
			check(hud.hunger_bar.value == 100 - player.get_hunger_percent(), "Status displays current satiety")
			var folder := OS.get_environment("TIP_STATUS_CAPTURE_DIR")
			if cycle == 0 and not folder.is_empty() and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(folder.path_join(str(map.name) + ".png"))
			await tab(false)
			check(not hud.status_drawer.visible, "Releasing Tab hides drawer")
		var inventory = map.get_node_or_null("InventoryUI")
		if inventory != null:
			inventory.open_inventory()
			await tab(true)
			check(not hud.status_drawer.visible, "Inventory modal keeps status shortcut blocked")
			await tab(false)
			inventory.close_inventory()
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
