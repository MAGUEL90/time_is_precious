extends Node

const CONTENT_SCENE: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const WORKSHOP_MENU_SCENE: PackedScene = preload("res://scenes/ui/workshop_menu_ui/workshop_menu_ui.tscn")

var failures: int = 0
var content: Node
var inventory: InventoryUI
var workshop_menu: WorkshopMenuUI
var capture_directory: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	capture_directory = OS.get_environment("TIP_INVENTORY_CAPTURE_DIR")
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _press(action: StringName) -> void:
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

func _clock_minute_stamp() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _wait_for_paused_clock_check() -> bool:
	var before: int = _clock_minute_stamp()
	await get_tree().create_timer(TimeComponentManager.seconds_per_minute + 0.15, true).timeout
	return _clock_minute_stamp() == before

func _expect_action_popup_inside_viewport(entry_path: String) -> void:
	var popup: Control = inventory.active_action_confirm_panel
	_expect(is_instance_valid(popup), entry_path + " opens an item action confirmation panel.")
	if not is_instance_valid(popup):
		return
	var bounds: Rect2 = get_viewport().get_visible_rect()
	var popup_rect: Rect2 = popup.get_global_rect()
	var margin: float = InventoryUI.INVENTORY_SCREEN_MARGIN
	_expect(popup_rect.position.x >= bounds.position.x + margin
		and popup_rect.position.y >= bounds.position.y + margin
		and popup_rect.end.x <= bounds.end.x - margin
		and popup_rect.end.y <= bounds.end.y - margin,
		entry_path + " keeps the complete confirmation panel inside the viewport margin.")

func _test_action_popup_edge_layout() -> void:
	var original_items: Dictionary = Inventory.items.duplicate(true)
	Inventory.items = {"wood_log": 1}
	Inventory.items_changed.emit()
	inventory.open_inventory()
	await get_tree().process_frame

	var wood_slot: ItemSlot
	for child: Node in inventory.grid.get_children():
		var slot: ItemSlot = child as ItemSlot
		if slot != null and slot._item_id == "wood_log":
			wood_slot = slot
			break
	_expect(is_instance_valid(wood_slot), "The popup geometry fixture finds its staged wood slot.")
	if is_instance_valid(wood_slot):
		var edge_position: Vector2 = get_viewport().get_visible_rect().end - Vector2.ONE
		inventory._open_drag_drop_confirm_panel(
			{"item_id": "wood_log", "slot_ref": wood_slot}, edge_position
		)
		await get_tree().process_frame
		_expect_action_popup_inside_viewport("Drag-drop")
		await _capture("inventory-drag-drop-confirm")
		inventory._close_inventory_floating_panels()
		await get_tree().process_frame

		inventory._on_item_slot_clicked("wood_log", 1, wood_slot)
		await get_tree().process_frame
		_expect(is_instance_valid(inventory.active_option_panel),
			"Clicking an item opens its existing action menu.")
		if is_instance_valid(inventory.active_option_panel):
			inventory.active_option_panel.global_position = edge_position
			inventory._open_item_action_confirm_panel("drop")
			await get_tree().process_frame
			_expect_action_popup_inside_viewport("Click action")
			await _capture("inventory-click-action-confirm")
		inventory._close_inventory_floating_panels()
		await get_tree().process_frame

	inventory.close_inventory()
	Inventory.items = original_items
	Inventory.items_changed.emit()
	await get_tree().process_frame

func _capture(name: String) -> void:
	if capture_directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var save_error: Error = get_viewport().get_texture().get_image().save_png(
		capture_directory.path_join(name + ".png")
	)
	_expect(save_error == OK, "Saved rendered evidence: " + name)

func _run() -> void:
	var original_tree_paused: bool = get_tree().paused
	var original_clock_paused: bool = TimeComponentManager.is_paused
	get_tree().paused = false
	TimeComponentManager.is_paused = false

	content = CONTENT_SCENE.instantiate()
	add_child(content)
	await get_tree().process_frame
	await get_tree().process_frame
	inventory = content.get_node_or_null("InventoryUI") as InventoryUI
	_expect(inventory != null, "Normal ContentScene entrypoint must provide InventoryUI.")
	if inventory == null:
		_finish(original_tree_paused, original_clock_paused)
		return

	var city_ui: RaidUI = get_tree().get_first_node_in_group("city_notification_ui") as RaidUI
	_expect(is_instance_valid(city_ui), "The normal map provides the city HUD for the stacking check.")
	if is_instance_valid(city_ui):
		city_ui.open_details()
		inventory.open_inventory()
		await get_tree().process_frame
		_expect(inventory.layer > city_ui.layer, "An active Inventory renders above City Hub and its notification icon.")
		await _capture("inventory-over-city-hub")
		await _press(&"ui_cancel")
		_expect(not inventory.visible and city_ui.details_panel.visible, "Escape closes only the foreground Inventory and preserves City Hub below it.")
		city_ui.close_details()
	await _test_action_popup_edge_layout()

	for cycle: int in range(2):
		await _press(&"open_inventory")
		_expect(inventory.visible and get_tree().paused, "Inventory shortcut opens and pauses the normal scene on cycle %d." % cycle)
		await _press(&"open_inventory")
		_expect(not inventory.visible and not get_tree().paused, "Inventory shortcut closes and resumes the normal scene on cycle %d." % cycle)

	for cycle: int in range(2):
		workshop_menu = WORKSHOP_MENU_SCENE.instantiate() as WorkshopMenuUI
		content.add_child(workshop_menu)
		await get_tree().process_frame
		workshop_menu.open_menu({})
		_expect(workshop_menu.visible and get_tree().paused, "Workshop Menu owns the pause before cycle %d." % cycle)

		await _press(&"open_inventory")
		_expect(not inventory.visible, "Inventory shortcut is blocked over Workshop Menu on cycle %d." % cycle)
		_expect(workshop_menu.visible and get_tree().paused, "Blocked Inventory shortcut preserves Workshop Menu and its pause on cycle %d." % cycle)
		var clock_stayed_paused: bool = await _wait_for_paused_clock_check()
		_expect(clock_stayed_paused, "World clock must stay stopped while Workshop Menu remains visible on cycle %d." % cycle)

		inventory.open_inventory()
		inventory.open_inventory()
		_expect(inventory.visible and get_tree().paused, "Repeated programmatic opens preserve the existing modal pause on cycle %d." % cycle)
		clock_stayed_paused = await _wait_for_paused_clock_check()
		_expect(clock_stayed_paused, "World clock must stay stopped while Inventory is programmatically open over Workshop Menu on cycle %d." % cycle)
		inventory.close_button.pressed.emit()
		_expect(not inventory.visible and workshop_menu.visible and get_tree().paused, "Inventory close restores the prior paused state on cycle %d." % cycle)
		inventory.close_inventory()
		_expect(workshop_menu.visible and get_tree().paused, "Repeated Inventory close cannot release Workshop Menu's pause on cycle %d." % cycle)
		clock_stayed_paused = await _wait_for_paused_clock_check()
		_expect(clock_stayed_paused, "World clock must stay stopped after Inventory closes beneath Workshop Menu on cycle %d." % cycle)

		workshop_menu.close_button.pressed.emit()
		await get_tree().process_frame
		_expect((not is_instance_valid(workshop_menu) or not workshop_menu.visible) and not get_tree().paused, "Closing Workshop Menu resumes the normal scene on cycle %d." % cycle)
		workshop_menu = null

	inventory.open_inventory()
	await get_tree().process_frame
	_expect(inventory.visible and get_tree().paused, "Inventory pauses the normal scene before exit cleanup.")
	inventory.free()
	inventory = null
	_expect(not get_tree().paused, "Removing an open Inventory restores its prior pause state.")

	_finish(original_tree_paused, original_clock_paused)

func _finish(original_tree_paused: bool, original_clock_paused: bool) -> void:
	if is_instance_valid(workshop_menu):
		workshop_menu.close_button.pressed.emit()
	if is_instance_valid(inventory):
		if inventory.visible:
			inventory.close_inventory()
	if is_instance_valid(content):
		content.free()
	TimeComponentManager.is_paused = original_clock_paused
	get_tree().paused = original_tree_paused
	print("InventoryModalPauseTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
