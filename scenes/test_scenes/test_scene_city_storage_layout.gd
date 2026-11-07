extends Node

## Explicit fixture stock; no player save is loaded or written.
const CITY_UI: PackedScene = preload("res://scenes/storage_destination/city_storage_access_ui.tscn")
const CITY_STORAGE: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")

class TransportStub extends Node:
	var provider: Node
	func get_storage(_id: String) -> Node:
		return provider

var failures: int = 0
var storage: Node
var panel: CanvasLayer
var capture_directory: String


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	capture_directory = OS.get_environment("TIP_UNIFIED_CAPTURE_DIR")
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _frames(count: int = 3) -> void:
	for _index: int in range(count):
		await get_tree().process_frame


func _capture(filename: String) -> void:
	await _frames()
	if capture_directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_expect(get_viewport().get_texture().get_image().save_png(capture_directory.path_join(filename)) == OK,
		"Capture saved: " + filename)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		get_window().size = Vector2i(1200, 675)
		await _frames()
	_expect(get_viewport().get_visible_rect().size == Vector2(400, 225), "Storage uses a 400x225 logical viewport.")
	TimeComponentManager.set_process(false)
	storage = CITY_STORAGE.new()
	add_child(storage)
	var item_ids: Array[String] = []
	for item: ItemData in ItemDatabase.get_all_items():
		item_ids.append(item.id)
	item_ids.sort()
	for index: int in range(item_ids.size()):
		_expect(storage.try_add_worksite_output(item_ids[index], index % 9 + 1), "Fixture can add " + item_ids[index])
	storage.items["barley_bread"] = 999999999
	storage.items["stone"] = 9223372036854775807
	var expected: Dictionary = storage.get_available_items()
	_expect(expected.size() > 27, "Fixture contains enough distinct registered stock for scrolling.")
	var before_items: Dictionary = storage.items.duplicate(true)
	var before_units: Dictionary = storage.units.duplicate(true)
	var treasury: int = CityStockManager.treasury_shekel
	panel = CITY_UI.instantiate()
	add_child(panel)
	panel.open(storage, func() -> bool: return true)
	await _frames(5)
	await _capture("storage-many-top.png")
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var scroll: ScrollContainer = panel.grid.get_parent() as ScrollContainer
	var footer: Control = panel.view.get_node("Margin/Content/Footer")
	var bag: Control = panel.view.get_node("Margin/Content/BagGrid")
	_expect(panel.view.size == Vector2(156, 208) and panel.grid.columns == 4,
		"Storage keeps the requested fixed 3:4 portrait frame and four native-size columns.")
	var fixed_panel_rect: Rect2 = panel.view.get_global_rect()
	_expect(panel.stock_summary.get_child_count() == 3, "All three currency entries use icons.")
	for index: int in range(3):
		var entry: HBoxContainer = panel.stock_summary.get_child(index)
		var icon: TextureRect = entry.get_node("Icon")
		var amount: Label = entry.get_node("Amount")
		_expect(icon.texture == panel.CURRENCY_ICONS[index] and icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
			"Currency artwork uses the existing native asset.")
		_expect(amount.text == (str(treasury) if index == 1 else "--"),
			"Currency values preserve the actual treasury and unavailable placeholders.")
		_expect(entry.get_global_rect().encloses(icon.get_global_rect()) and panel.view.get_global_rect().encloses(entry.get_global_rect()),
			"Currency icon and value remain inside the frame.")
	_expect(viewport_rect.encloses(panel.view.get_global_rect()), "Entire storage panel fits in the logical viewport.")
	_expect(panel.view.get_global_rect().encloses(footer.get_global_rect()) and footer.get_global_rect().end.y <= viewport_rect.end.y,
		"All action buttons remain inside the panel and viewport.")
	_expect(panel.view.get_global_rect().encloses(bag.get_global_rect()), "Grid viewport remains inside the panel.")
	_expect(not panel.context.visible, "No explanatory text appears beneath City Storage.")
	_expect(panel.view.get_node("Margin/Content/TitleRow/Title").get_theme_font_size("font_size") == 12,
		"The panel title uses the 12-pixel UI font.")
	var shown: Dictionary = {}
	for slot: ItemSlot in panel.grid.get_children():
		if slot._item_id.is_empty():
			continue
		shown[slot._item_id] = slot._quantity
		_expect(slot.asset_qty.text == str(expected.get(slot._item_id, -1)), "Card shows exact stored quantity: " + slot._item_id)
		_expect(slot.asset_qty.clip_text and slot.asset_qty.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS
			and slot.asset_qty.accessibility_name == str(slot._quantity)
			and slot.accessibility_name == "%s: %d" % [ItemDatabase.get_item_data(slot._item_id).display_name, slot._quantity],
			"Large quantities stay contained and retain their full accessible value: " + slot._item_id)
		_expect(slot.size == Vector2(24, 24), "Card keeps native dimensions: " + slot._item_id)
		_expect(slot.get_global_rect().encloses(slot.asset_qty.get_global_rect())
			and slot.asset_qty.get_theme_font_size("font_size") == 6
			and slot.get_global_rect().position.x >= scroll.get_global_rect().position.x
			and slot.get_global_rect().end.x <= scroll.get_global_rect().end.x,
			"The 6-pixel quantity and card stay within the grid horizontally: " + slot._item_id)
	_expect(shown == expected, "All available registered items appear exactly once with their actual quantities.")
	_expect(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page, "Many items produce a real vertical scroll range.")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = scroll.get_global_rect().get_center()
	wheel.global_position = wheel.position
	get_viewport().push_input(wheel, true)
	await _frames()
	_expect(scroll.scroll_vertical > 0, "Mouse wheel scrolls the actual storage grid.")
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await _frames()
	await _capture("storage-many-bottom.png")
	var last: Control = panel.grid.get_child(panel.grid.get_child_count() - 1) as Control
	_expect(scroll.get_global_rect().encloses(last.get_global_rect()), "Last item is fully reachable at the bottom of the scroll.")
	panel.categories.next_button.pressed.emit()
	await _frames()
	var category: int = panel.categories.get_selected_category()
	var filtered: Dictionary = {}
	for id: String in expected:
		if ItemDatabase.get_item_data(id).category == category:
			filtered[id] = expected[id]
	shown.clear()
	for slot: ItemSlot in panel.grid.get_children():
		if not slot._item_id.is_empty():
			shown[slot._item_id] = slot._quantity
	_expect(shown == filtered, "Category navigation shows the exact matching stock.")
	for _step: int in range(12):
		panel.categories.next_button.pressed.emit()
		await _frames()
		_expect(panel.view.get_global_rect() == fixed_panel_rect, "Every category retains exactly the same frame size and position.")
	CityStockManager.treasury_shekel = 9223372036854775807
	panel._refresh_view()
	await _frames()
	_expect(panel.view.get_global_rect() == fixed_panel_rect, "A very large currency value cannot resize the panel.")
	_expect(panel._currency_amounts[1].text == "9223372036854775807"
		and panel._currency_amounts[1].accessibility_name == "Shekel: 9223372036854775807", "Large treasury remains exact and accessible.")
	CityStockManager.treasury_shekel = treasury
	_expect(storage.items == before_items and storage.units == before_units and CityStockManager.treasury_shekel == treasury,
		"Browsing, filtering and scrolling do not alter stock or treasury.")
	panel.close()
	await _frames()
	_expect(not get_tree().paused, "Closing physical storage restores the prior pause state.")
	panel = CITY_UI.instantiate()
	add_child(panel)
	panel.open(storage, func() -> bool: return true, "city", true)
	await _frames()
	_expect(not panel.context.visible and panel.deposit_button.disabled, "Hub browsing hides the explanation and preserves read-only access.")
	await _capture("storage-hub.png")
	panel.close()
	await _frames()
	var transport := TransportStub.new()
	transport.provider = storage
	transport.add_to_group("city_storage_transport")
	add_child(transport)
	panel = CITY_UI.instantiate()
	add_child(panel)
	panel.open(storage, func() -> bool: return true, "annex")
	await _frames()
	_expect(panel.context.visible and panel.deposit_button.disabled
		and viewport_rect.encloses(panel.view.get_global_rect())
		and panel.view.get_global_rect().encloses(panel.view.get_node("Margin/Content/Footer").get_global_rect()),
		"The annex retains its existing context and actions within the viewport.")
	await _capture("storage-annex.png")
	panel.close()
	await _frames()
	transport.free()
	storage.items = {"stone": 1}
	storage.units.clear()
	panel = CITY_UI.instantiate()
	add_child(panel)
	panel.open(storage, func() -> bool: return true)
	await _frames()
	_expect(panel.grid.get_child_count() == 1 and panel.grid.get_child(0)._quantity == 1,
		"A single real item stays one item; browsing does not fabricate stock.")
	_expect(panel.view.get_global_rect() == fixed_panel_rect, "Single-item stock retains the fixed frame.")
	panel.categories.next_button.pressed.emit()
	await _frames()
	_expect(panel.view.get_global_rect() == fixed_panel_rect, "A category with no matching stock retains the fixed frame.")
	await _capture("storage-one-item.png")
	panel.close()
	await _frames()
	storage.items.clear()
	panel = CITY_UI.instantiate()
	add_child(panel)
	panel.open(storage, func() -> bool: return true)
	await _frames()
	_expect(panel.grid.get_child_count() == 0 and panel.feedback.text == "No available items.",
		"Empty storage has no fabricated cards and reports its empty state.")
	_expect(panel.view.get_global_rect() == fixed_panel_rect, "Empty storage retains the fixed frame.")
	await _capture("storage-empty.png")
	panel.close()
	await _frames()
	storage.free()
	print("CityStorageLayoutTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)
