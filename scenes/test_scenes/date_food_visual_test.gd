extends Node
var failures: int = 0

func capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var folder: String = OS.get_environment("TIP_FOOD_CAPTURE_DIR")
	if not folder.is_empty():
		get_viewport().get_texture().get_image().save_png(folder.path_join(file_name + ".png"))

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	TimeComponentManager.set_process(false)
	var map = load("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(map)
	await get_tree().process_frame
	var tree = map.get_node("YSortWorld/DatePalmTree")
	var player = map.get_node("YSortWorld/Player")
	player.global_position = tree.global_position + Vector2(12, 52)
	await get_tree().create_timer(0.6).timeout
	await capture("map")
	var pickup = tree._pickups[0]
	player.global_position = pickup.global_position + Vector2(0, -6)
	for frame in range(6):
		await get_tree().physics_frame
	await capture("pickup-focus")
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	player._unhandled_input(event)
	await get_tree().create_timer(1.0).timeout
	check(Inventory.items.get("date_cluster", 0) == 1, "Graphical E interaction adds a date")
	var overlay = map.get_node("TimeDebugOverlay")
	overlay.panel.show()
	overlay._refresh_controls()
	await get_tree().process_frame
	await get_tree().process_frame
	overlay.panel.get_child(0).scroll_vertical = 10000
	await get_tree().create_timer(0.3).timeout
	var bounds: Rect2 = overlay.panel.get_global_rect()
	check(get_viewport().get_visible_rect().encloses(bounds), "Debug panel fits logical viewport")
	check(overlay.date_refill_button.get_global_rect().end.y <= bounds.end.y, "Refill button is visible after scroll")
	await capture("debug")
	overlay.date_refill_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	check(tree._pickups.size() == 3, "Graphical debug refill restores capacity")
	overlay.panel.hide()
	var ui = map.get_node("InventoryUI")
	ui.open_inventory()
	await get_tree().create_timer(0.3).timeout
	await capture("inventory")
	ui.close_inventory()
	await get_tree().create_timer(0.3).timeout
	map.queue_free()
	await get_tree().process_frame
	print("DateFoodVisualTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().call_deferred("quit", 0 if failures == 0 else 1)
