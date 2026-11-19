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

func _move_mouse(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	await get_tree().process_frame

func _click_mouse(position: Vector2) -> void:
	var button := InputEventMouseButton.new()
	button.position = position
	button.global_position = position
	button.button_index = MOUSE_BUTTON_LEFT
	button.button_mask = MOUSE_BUTTON_MASK_LEFT
	button.pressed = true
	get_viewport().push_input(button, true)
	await get_tree().process_frame
	button = InputEventMouseButton.new()
	button.position = position
	button.global_position = position
	button.button_index = MOUSE_BUTTON_LEFT
	get_viewport().push_input(button, true)
	await get_tree().process_frame

func _find_item_slot(item_id: String) -> ItemSlot:
	for child: Node in inventory.grid.get_children():
		var slot: ItemSlot = child as ItemSlot
		if slot != null and not slot.is_queued_for_deletion() and slot._item_id == item_id:
			return slot
	return null

func _test_player_side_position() -> void:
	var player: Player = inventory.player_ref
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	var saved_position: Vector2 = player.global_position
	var map_boundary: Node = content.get_node("MapBoundary")
	var walkable: Rect2 = map_boundary.get_world_rect()
	var bounds: Rect2 = get_viewport().get_visible_rect()
	for x: float in [walkable.position.x + 12.0, walkable.get_center().x, walkable.end.x - 12.0]:
		player.global_position.x = x
		camera.force_update_scroll()
		await get_tree().process_frame
		inventory.open_inventory()
		await get_tree().process_frame
		await get_tree().process_frame
		var player_screen: Vector2 = player.get_global_transform_with_canvas().origin
		var panel_rect: Rect2 = inventory.inventory_window.get_global_rect()
		var scene_rect: Rect2 = bounds.intersection(get_viewport().get_canvas_transform() * walkable.grow(16.0))
		_expect(bounds.encloses(panel_rect), "Inventory stays within the viewport at player x=%s." % x)
		_expect(scene_rect.encloses(panel_rect), "Inventory stays within the authored scene at player x=%s." % x)
		if x == walkable.position.x + 12.0:
			_expect(panel_rect.position.x >= player_screen.x + 8.0, "Inventory is to the right of a left-side player.")
		elif x == walkable.end.x - 12.0:
			_expect(panel_rect.end.x <= player_screen.x - 8.0, "Inventory is to the left of a right-side player.")
		else:
			_expect(panel_rect.end.x <= player_screen.x - 8.0 or panel_rect.position.x >= player_screen.x + 8.0,
				"Inventory does not cover a centered player.")
		print("INVENTORY_SCENE_QA scene=", scene_rect, " player=", player_screen, " panel=", panel_rect)
		if x == walkable.position.x + 12.0:
			await _capture("inventory-scene-left")
		elif x == walkable.end.x - 12.0:
			await _capture("inventory-scene-right")
		else:
			await _capture("inventory-scene-center")
		inventory.close_inventory()
	player.global_position = saved_position
	camera.force_update_scroll()
	await get_tree().process_frame

func _test_item_grid_scrolling() -> void:
	var original_items: Dictionary = Inventory.items.duplicate(true)
	Inventory.items.clear()
	Inventory.items_changed.emit()
	inventory.open_inventory()
	for _frame in range(4):
		await get_tree().process_frame
	var scroll: ScrollContainer = inventory.item_scroll
	var scrollbar: VScrollBar = scroll.get_v_scroll_bar()
	var initial_frame: Rect2 = inventory.inventory_window.get_global_rect()
	_expect(inventory.grid.columns == 4 and inventory.grid.get_child_count() == 12 and not scrollbar.visible,
		"Empty Inventory retains twelve cards in four columns without a scrollbar.")
	_expect(inventory.inventory_window.get_node_or_null("Margin/MainVBox/InventoryPageSelector") == null,
		"Inventory no longer contains page arrows or page dots.")
	var fixture_items: Dictionary[String, int] = {}
	var last_id: String = ""
	for item: ItemData in ItemDatabase.get_all_items():
		fixture_items[item.id] = 1
		last_id = item.id
		if fixture_items.size() == 23:
			break
	_expect(fixture_items.size() == 23, "The scroll fixture contains enough different item types.")
	Inventory.items = fixture_items
	Inventory.items_changed.emit()
	for _frame in range(4):
		await get_tree().process_frame
	_expect(inventory.inventory_window.get_global_rect().is_equal_approx(initial_frame),
		"Adding enough items to scroll does not resize or move Inventory.")
	_expect(scrollbar.visible and scrollbar.max_value > scrollbar.page,
		"Inventory shows a scrollbar only when more than three rows are needed.")
	_expect(scroll.size.y == 76 and scrollbar.size == Vector2(8, 76)
		and scrollbar.get_theme_stylebox("scroll") is StyleBoxTexture
		and scrollbar.get_theme_stylebox("scroll_focus") is StyleBoxTexture,
		"The fixed scrollbar rail matches three native-height item rows.")
	var grabber: StyleBoxTexture = scrollbar.get_theme_stylebox("grabber") as StyleBoxTexture
	var highlight: AtlasTexture = grabber.texture as AtlasTexture if is_instance_valid(grabber) else null
	_expect(is_instance_valid(highlight) and highlight.atlas == InventoryUI.ITEM_SCROLLBAR_TEXTURE
		and highlight.region == Rect2(3, 3, 2, 1),
		"The moving highlight uses the bright yellow pixels of the existing scrollbar artwork.")
	var fourth: ItemSlot = inventory.grid.get_child(3) as ItemSlot
	_expect(is_equal_approx(scrollbar.global_position.x - fourth.get_global_rect().end.x, 4.0),
		"The scrollbar is four pixels away from the last item column.")
	var shown: Dictionary = {}
	for slot: ItemSlot in inventory.grid.get_children():
		if not slot._item_id.is_empty():
			_expect(not shown.has(slot._item_id), "Each Inventory item has only one card.")
			shown[slot._item_id] = slot._quantity
	_expect(shown == fixture_items, "All item types and their quantities remain available in the scrolling grid.")
	await _capture("inventory-scroll-top")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = scroll.get_global_rect().get_center()
	wheel.global_position = wheel.position
	get_viewport().push_input(wheel, true)
	wheel = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.position = scroll.get_global_rect().get_center()
	wheel.global_position = wheel.position
	get_viewport().push_input(wheel, true)
	for _frame in range(3):
		await get_tree().process_frame
	_expect(scroll.scroll_vertical > 0, "The mouse wheel scrolls over the item grid.")
	scroll.scroll_vertical = 0
	await get_tree().process_frame
	var drag_start: Vector2 = scrollbar.get_global_rect().position + Vector2(scrollbar.size.x * 0.5, 5.0)
	var drag_end: Vector2 = scrollbar.get_global_rect().position + Vector2(scrollbar.size.x * 0.5, scrollbar.size.y - 5.0)
	await _move_mouse(drag_start)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = drag_start
	press.global_position = drag_start
	get_viewport().push_input(press, true)
	await get_tree().process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = drag_end
	motion.global_position = drag_end
	motion.relative = drag_end - drag_start
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = drag_end
	release.global_position = drag_end
	get_viewport().push_input(release, true)
	await get_tree().process_frame
	_expect(scroll.scroll_vertical > 0, "The yellow Inventory scrollbar can be dragged.")
	scroll.scroll_vertical = int(scrollbar.max_value - scrollbar.page)
	for _frame in range(3):
		await get_tree().process_frame
	var last: ItemSlot = _find_item_slot(last_id)
	_expect(is_instance_valid(last) and scroll.get_global_rect().encloses(last.get_global_rect()),
		"The last real item remains fully reachable at the bottom.")
	await _capture("inventory-scroll-bottom")
	var previous_scroll: int = scroll.scroll_vertical
	Inventory.items_changed.emit()
	for _frame in range(3):
		await get_tree().process_frame
	_expect(scroll.scroll_vertical == previous_scroll, "Refreshing the same items preserves the current scroll position.")
	last = _find_item_slot(last_id)
	_expect(is_instance_valid(last), "The last item remains available after refreshing the grid.")
	if is_instance_valid(last):
		await _move_mouse(Vector2(399, 1))
		await _move_mouse(last.get_global_rect().get_center())
		_expect(inventory.item_info_panel.visible
			and inventory.item_info_panel.name_label.text.contains(ItemDatabase.get_item_data(last_id).display_name),
			"Hover still displays the correct information for a scrolled item.")
		inventory._on_item_slot_clicked(last_id, 1, last)
		_expect(is_instance_valid(inventory.active_option_panel), "A scrolled item can still open its action menu.")
		scroll.scroll_vertical = 0
		await get_tree().process_frame
		_expect(not is_instance_valid(inventory.active_option_panel),
			"Scrolling away closes the item action menu instead of leaving it on a stale slot.")
	inventory.category_selector.next_button.pressed.emit()
	for _frame in range(4):
		await get_tree().process_frame
	var category: int = inventory.category_selector.get_selected_category()
	var expected: Dictionary = {}
	for item_id: String in fixture_items:
		if ItemDatabase.get_item_data(item_id).category == category:
			expected[item_id] = fixture_items[item_id]
	shown.clear()
	for slot: ItemSlot in inventory.grid.get_children():
		if not slot._item_id.is_empty():
			shown[slot._item_id] = slot._quantity
	_expect(shown == expected and scroll.scroll_vertical == 0, "Changing category resets scroll and shows exactly matching items.")
	inventory.category_selector.prev_button.pressed.emit()
	for _frame in range(3):
		await get_tree().process_frame
	_expect(Inventory.items == fixture_items, "Opening, filtering and scrolling do not change Inventory stock.")
	scroll.scroll_vertical = int(scrollbar.max_value - scrollbar.page)
	await get_tree().process_frame
	Inventory.items = {"wood_log": 2}
	Inventory.items_changed.emit()
	for _frame in range(3):
		await get_tree().process_frame
	_expect(not scrollbar.visible and scroll.scroll_vertical == 0 and inventory.grid.get_child_count() == 12,
		"Shrinking the item list hides the scrollbar and restores twelve visible cards.")
	inventory.close_inventory()
	Inventory.items = original_items
	Inventory.items_changed.emit()
	await get_tree().process_frame

func _test_item_info_hover() -> void:
	var original_items: Dictionary = Inventory.items.duplicate(true)
	Inventory.items = {"barley_bread": 3, "wood_log": 2}
	Inventory.items_changed.emit()
	inventory.open_inventory()
	await get_tree().process_frame
	await get_tree().process_frame
	var bread: ItemSlot = _find_item_slot("barley_bread")
	var wood: ItemSlot = _find_item_slot("wood_log")
	_expect(is_instance_valid(bread) and is_instance_valid(wood), "Hover fixture contains two item slots.")
	if is_instance_valid(bread) and is_instance_valid(wood):
		await _move_mouse(Vector2(399, 1))
		_expect(not inventory.item_info_panel.visible, "Item information starts hidden.")
		await _move_mouse(bread.get_global_rect().get_center())
		var info: ItemInfoPanel = inventory.item_info_panel
		_expect(info.visible and info.name_label.text.contains(ItemDatabase.get_item_data("barley_bread").display_name),
			"Hovering a populated slot shows its existing item information.")
		_expect(info.size.x == 260 and info.size.y >= 40 and info.effect_label.get_theme_color("font_color") == info.EFFECT_COLOR,
			"Inventory uses the shared item panel and highlights existing effects.")
		_expect(info.effect_label.get_theme_color("font_color") == Color(0.24, 0.52, 0.72, 1.0), "Existing effects use the requested light blue.")
		var fixed_info_rect: Rect2 = info.get_global_rect()
		_expect(get_viewport().get_visible_rect().encloses(info.get_global_rect())
			and is_equal_approx(info.get_global_rect().get_center().x, get_viewport().get_visible_rect().get_center().x)
			and info.get_global_rect().position.y >= inventory.item_scroll.get_global_rect().end.y,
			"The item information stays centered and below the item grid when it fits.")
		await _capture("inventory-item-info")
		await _move_mouse(wood.get_global_rect().get_center())
		_expect(info.visible and info.name_label.text.contains(ItemDatabase.get_item_data("wood_log").display_name),
			"Moving to another item updates the information.")
		_expect(info.get_global_rect().position == fixed_info_rect.position and info.size.x == fixed_info_rect.size.x and info.effect_label.text == "effect: none"
			and not info.effect_label.has_theme_color_override("font_color"),
			"Items without effects retain the top position and default text color.")
		info.display_item("reed_bundle")
		await get_tree().process_frame
		await get_tree().process_frame
		var bundle_name_rect: Rect2 = info.name_label.get_global_rect()
		var bundle_category_y: float = info.category_label.global_position.y
		info.display_item("reed_sandal")
		await get_tree().process_frame
		await get_tree().process_frame
		_expect(info.name_label.get_global_rect() == bundle_name_rect and is_equal_approx(info.category_label.global_position.y, bundle_category_y),
			"Names with descenders or underscores keep the same name and category alignment.")
		await _move_mouse(Vector2(399, 1))
		_expect(not info.visible, "Moving away hides the information.")
		await _move_mouse(bread.get_global_rect().get_center())
		await _click_mouse(bread.get_global_rect().get_center())
		_expect(is_instance_valid(inventory.active_option_panel) and not info.visible,
			"An item can be clicked through the information panel and the action menu hides it.")
		if is_instance_valid(inventory.active_option_panel):
			await get_tree().process_frame
			var options: OptionPanel = inventory.active_option_panel
			_expect(options.use_button.size == Vector2(40, 14) and options.drop_button.size == Vector2(40, 14),
				"Use and Drop match the City Hub Close button dimensions.")
			_expect(options.get_global_rect().encloses(options.use_button.get_global_rect())
				and options.get_global_rect().encloses(options.drop_button.get_global_rect()),
				"The compact option panel fully contains both buttons.")
			await _capture("inventory-compact-actions")
		await _move_mouse(wood.get_global_rect().get_center())
		_expect(not info.visible, "Item information stays hidden while the action menu is open.")
		inventory._close_option_panel()
		await _move_mouse(Vector2(399, 1))
		await _move_mouse(bread.get_global_rect().get_center())
		_expect(info.visible, "Hover information works again after closing the action menu.")
		bread.slot_drag_started.emit({"item_id": "barley_bread", "quantity": 3, "slot_ref": bread})
		_expect(not info.visible, "Starting a drag hides the item information.")
		bread.slot_hovered.emit("barley_bread", 3, bread)
		_expect(not info.visible, "Item information stays hidden during a drag.")
		inventory.active_drag_data.clear()
		await _move_mouse(Vector2(399, 1))
		await _move_mouse(bread.get_global_rect().get_center())
		Inventory.items_changed.emit()
		await get_tree().process_frame
		_expect(not info.visible, "Refreshing Inventory clears stale information.")
		_expect(Inventory.items == {"barley_bread": 3, "wood_log": 2},
			"Hovering and opening the action menu do not change inventory.")
	inventory.close_inventory()
	inventory.open_inventory()
	await get_tree().process_frame
	_expect(not inventory.item_info_panel.visible, "Reopening Inventory does not restore stale item information.")
	inventory.close_inventory()
	Inventory.items = original_items
	Inventory.items_changed.emit()
	await get_tree().process_frame

func _test_use_matches_drop_panel() -> void:
	var previous: Dictionary = Inventory.items.duplicate(true)
	Inventory.items = {"barley_bread": 3}
	Inventory.items_changed.emit()
	inventory.open_inventory()
	await get_tree().process_frame
	var slot: ItemSlot = _find_item_slot("barley_bread")
	_expect(is_instance_valid(slot), "Use panel fixture has a food item.")
	if is_instance_valid(slot):
		inventory._on_item_slot_clicked("barley_bread", 3, slot)
		await get_tree().process_frame
		inventory._open_item_action_confirm_panel("drop")
		await get_tree().process_frame
		var drop_rect: Rect2 = inventory.active_action_confirm_panel.get_global_rect()
		inventory._close_item_action_confirm_panel()
		await get_tree().process_frame
		inventory._open_item_action_confirm_panel("use")
		await get_tree().process_frame
		var use_panel: ItemActionConfirmPanel = inventory.active_action_confirm_panel
		_expect(use_panel.get_global_rect() == drop_rect and use_panel.size == Vector2(104, 80), "Use and Drop have the same position and compact dimensions.")
		_expect(not use_panel.get_global_rect().intersects(inventory.inventory_window.get_global_rect()), "Use does not cover the Inventory panel when there is room beside it.")
		_expect(use_panel.get_global_rect().encloses(use_panel.confirm_button.get_global_rect()) and use_panel.get_global_rect().encloses(use_panel.step_selector.get_global_rect()), "Use controls remain inside the compact panel.")
		await _capture("inventory-use-compact")
		use_panel.cancel_button.pressed.emit()
		await get_tree().process_frame
		_expect(not is_instance_valid(inventory.active_action_confirm_panel), "Cancel closes Use without changing Inventory.")
		_expect(Inventory.items == {"barley_bread": 3}, "Opening and cancelling Use does not consume items.")
	inventory.close_inventory()
	Inventory.items = previous
	Inventory.items_changed.emit()

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
		var popup: ItemActionConfirmPanel = inventory.active_action_confirm_panel
		_expect(popup.size == Vector2(104, 80), "Drop panel uses the compact dimensions.")
		_expect(popup.confirm_button.size == Vector2(40, 14) and popup.cancel_button.size == Vector2(40, 14),
			"Drop Confirm and Cancel match the compact City Hub button.")
		_expect(popup.get_global_rect().encloses(popup.confirm_button.get_global_rect())
			and popup.get_global_rect().encloses(popup.cancel_button.get_global_rect())
			and popup.get_global_rect().encloses(popup.step_selector.get_global_rect())
			and popup.get_global_rect().encloses(popup.quantity_stepper.get_global_rect()),
			"Drop controls stay inside the compact panel.")
		popup.setup("drop", "wood_log", ItemDatabase.get_item_data("wood_log"), 9223372036854775807)
		await get_tree().process_frame
		_expect(popup.get_global_rect().encloses(popup.quantity_label.get_global_rect()),
			"A long maximum quantity stays inside the compact Drop panel.")
		popup.cancel_button.pressed.emit()
		await get_tree().process_frame
		_expect(not is_instance_valid(inventory.active_action_confirm_panel) and inventory.visible,
			"Cancel closes the Drop panel without closing Inventory.")
		inventory._open_drag_drop_confirm_panel({"item_id": "wood_log", "slot_ref": wood_slot}, edge_position)
		await get_tree().process_frame
		popup = inventory.active_action_confirm_panel
		popup.confirm_button.pressed.emit()
		await get_tree().process_frame
		_expect(popup.confirm_actions.visible and not popup.initial_actions.visible,
			"Confirm opens the existing final confirmation step.")
		popup.confirm_actions.cancel_button.pressed.emit()
		await get_tree().process_frame
		_expect(popup.initial_actions.visible and not popup.confirm_actions.visible,
			"Canceling final confirmation returns to the quantity panel.")
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
	await _test_player_side_position()

	var city_ui: RaidUI = get_tree().get_first_node_in_group("city_notification_ui") as RaidUI
	_expect(is_instance_valid(city_ui), "The normal map provides the city HUD for the stacking check.")
	if is_instance_valid(city_ui):
		city_ui.open_details()
		inventory.open_inventory()
		await get_tree().process_frame
		_expect(inventory.layer > city_ui.layer, "An active Inventory renders above City Hub and its notification icon.")
		var original_items: Dictionary = Inventory.items.duplicate(true)
		Inventory.items["shekel"] = 12345
		Inventory.items_changed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		_expect(inventory.shekel_amount.text == "12345", "Inventory wallet updates from the authoritative item balance.")
		var wallet_icon: Control = inventory.shekel_amount.get_parent().get_node("ShekelIcon")
		_expect(wallet_icon.get_global_rect().position.y >= inventory.item_scroll.get_global_rect().end.y, "Currency sits below the item grid.")
		var wallet_row: Control = wallet_icon.get_parent().get_parent() as Control
		_expect(wallet_row.get_child_count() == 3 and wallet_row.get_child(0).name == "Copper" and wallet_row.get_child(1).name == "Shekel" and wallet_row.get_child(2).name == "Gold", "Copper, Shekel and Gold appear in order.")
		_expect(wallet_row.get_node("Copper/Amount").text == "0" and wallet_row.get_node("Gold/Amount").text == "0", "Unavailable denominations use zero placeholders.")
		for amount: Label in [wallet_row.get_node("Copper/Amount"), inventory.shekel_amount, wallet_row.get_node("Gold/Amount")]:
			_expect(amount.get_theme_color("font_color") == Color.WHITE, "Inventory currency text is white.")
		await _capture("inventory-wallet")
		var before_large_wallet: Rect2 = inventory.inventory_window.get_global_rect()
		Inventory.items["shekel"] = 9223372036854775807
		Inventory.items_changed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		_expect(inventory.inventory_window.get_global_rect() == before_large_wallet and inventory.shekel_amount.accessibility_name == "Shekel: 9223372036854775807", "Large Shekel totals do not resize Inventory and retain their exact accessible value.")
		Inventory.items = original_items
		Inventory.items_changed.emit()
		await _capture("inventory-over-city-hub")
		await _press(&"ui_cancel")
		_expect(not inventory.visible and city_ui.details_panel.visible, "Escape closes only the foreground Inventory and preserves City Hub below it.")
		city_ui.close_details()
	await _test_item_info_hover()
	await _test_action_popup_edge_layout()
	await _test_use_matches_drop_panel()
	await _test_item_grid_scrolling()

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
