extends Node

## Explicit fixture stock; no player save is loaded or written.
const CITY_UI: PackedScene = preload("res://scenes/storage_destination/city_storage_access_ui.tscn")
const CITY_STORAGE: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")
const BACK_ICON: Texture2D = preload("res://assets/ui/ui_icon/back_button.png")
const DEPOSIT_ICON: Texture2D = preload("res://assets/ui/ui_icon/deposit_icon.png")

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
	var back_button: Button = footer.get_node("Back") as Button
	var content: Control = panel.view.get_node("Margin/Content")
	var bag: Control = panel.view.get_node("Margin/Content/BagGrid")
	_expect(panel.view.size == Vector2(240, 208) and panel.grid.columns == 7,
		"Storage keeps a fixed frame wide enough for seven native-size columns and the scrollbar.")
	_expect(panel.grid.get_theme_constant("h_separation") == 4
		and panel.grid.get_theme_constant("v_separation") == 2,
		"Storage uses the same horizontal and vertical slot spacing as Inventory.")
	var fixed_panel_rect: Rect2 = panel.view.get_global_rect()
	_expect(panel.stock_summary.get_child_count() == 3, "All three currency entries use icons.")
	_expect(back_button.text == "Back" and back_button.icon == BACK_ICON
		and back_button.icon.get_size() == Vector2(16, 16),
		"Back keeps its label and displays the native 16x16 icon.")
	_expect(back_button.custom_minimum_size == Vector2(64, 18)
		and panel.deposit_button.custom_minimum_size == Vector2(64, 18)
		and panel.deposit_button.text == "Deposit" and panel.deposit_button.icon == DEPOSIT_ICON,
		"Back and Deposit keep matching action widths, labels and native icon assets.")
	var content_rect: Rect2 = content.get_global_rect()
	_expect(is_equal_approx(content_rect.position.x - fixed_panel_rect.position.x, 16.0)
		and is_equal_approx(fixed_panel_rect.end.x - content_rect.end.x, 16.0)
		and is_equal_approx(content_rect.position.y - fixed_panel_rect.position.y, 16.0)
		and is_equal_approx(fixed_panel_rect.end.y - content_rect.end.y, 16.0),
		"Storage content retains a 16-pixel inset on all four sides.")
	for index: int in range(3):
		var entry: HBoxContainer = panel.stock_summary.get_child(index)
		var icon: TextureRect = entry.get_node("Icon")
		var amount: Label = entry.get_node("Amount")
		_expect(amount.get_theme_color("font_color") == Color.WHITE, "City Storage currency text is white.")
		_expect(icon.texture == panel.CURRENCY_ICONS[index] and icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
			"Currency artwork uses the existing native asset.")
		_expect(amount.text == "0" and amount.get_theme_font_size("font_size") == 6
			and amount.get_theme_font("font") == panel.view.theme.get_font("font", "HudLabelShortcut")
			and amount.accessibility_name == "%s: 0, placeholder" % entry.name,
			"Each currency uses the 6-pixel project font and a zero placeholder.")
		_expect(entry.get_global_rect().encloses(icon.get_global_rect()) and panel.view.get_global_rect().encloses(entry.get_global_rect()),
			"Currency icon and value remain inside the frame.")
	var copper: Control = panel.stock_summary.get_child(0) as Control
	var shekel: Control = panel.stock_summary.get_child(1) as Control
	var gold: Control = panel.stock_summary.get_child(2) as Control
	_expect(is_equal_approx(shekel.global_position.x - copper.get_global_rect().end.x, 12.0)
		and is_equal_approx(gold.global_position.x - shekel.get_global_rect().end.x, 12.0)
		and is_equal_approx(panel.stock_summary.get_global_rect().get_center().x, panel.view.get_global_rect().get_center().x),
		"Currency entries have even gaps and are centered when no feedback is shown.")
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
	var hovered_slot: ItemSlot = panel.grid.get_child(0) as ItemSlot
	var move := InputEventMouseMotion.new()
	move.position = hovered_slot.get_global_rect().get_center()
	move.global_position = move.position
	get_viewport().push_input(move, true)
	await _frames(5)
	_expect(panel.item_info_panel.visible and panel.item_info_panel.name_label.text.contains(ItemDatabase.get_item_data(hovered_slot._item_id).display_name),
		"Hovering an actual storage item shows its own information.")
	var info_rect: Rect2 = panel.item_info_panel.get_global_rect()
	_expect(info_rect.size.x == 260 and info_rect.size.y >= 40, "City Storage uses the shared content-sized item panel.")
	_expect(viewport_rect.encloses(info_rect) and absf(info_rect.get_center().x - viewport_rect.get_center().x) <= 1.0
		and is_equal_approx(viewport_rect.end.y - info_rect.position.y, 68.0),
		"Item information stays at the lower center of the viewport.")
	_expect(panel.item_info_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE and panel.view.get_global_rect() == fixed_panel_rect,
		"Information does not block input or resize City Storage.")
	await _capture("storage-item-information.png")
	var next_slot: ItemSlot = panel.grid.get_child(1) as ItemSlot
	move = InputEventMouseMotion.new()
	move.position = next_slot.get_global_rect().get_center()
	move.global_position = move.position
	get_viewport().push_input(move, true)
	await _frames()
	_expect(panel.item_info_panel.visible and panel.item_info_panel.name_label.text.contains(ItemDatabase.get_item_data(next_slot._item_id).display_name),
		"Moving between items updates the information.")
	_expect(panel.item_info_panel.get_global_rect().position == info_rect.position and panel.item_info_panel.size.x == info_rect.size.x, "City Storage item information retains its top position and width.")
	move = InputEventMouseMotion.new()
	move.position = Vector2(1, 1)
	move.global_position = move.position
	get_viewport().push_input(move, true)
	await _frames()
	_expect(not panel.item_info_panel.visible, "Moving away hides item information.")
	_expect(storage.items == before_items and storage.units == before_units, "Inspecting an item does not change stock.")
	var scrollbar: VScrollBar = scroll.get_v_scroll_bar()
	_expect(scrollbar.visible and scrollbar.max_value > scrollbar.page, "Many items produce a real vertical scroll range.")
	_expect(scroll.size.y == 102 and scrollbar.size == Vector2(8, 102)
		and scrollbar.get_theme_stylebox("scroll") is StyleBoxTexture
		and scrollbar.get_theme_stylebox("scroll_focus") is StyleBoxTexture,
		"The fixed scrollbar rail aligns with four item rows.")
	var thumb: StyleBoxTexture = scrollbar.get_theme_stylebox("grabber") as StyleBoxTexture
	var highlight: AtlasTexture = thumb.texture as AtlasTexture if is_instance_valid(thumb) else null
	_expect(is_instance_valid(highlight) and highlight.atlas == panel.ITEM_SCROLLBAR_TEXTURE
		and highlight.region == Rect2(3, 3, 2, 1),
		"The moving highlight uses the existing scrollbar artwork.")
	if panel.grid.get_child_count() >= 8:
		var first: ItemSlot = panel.grid.get_child(0) as ItemSlot
		var second: ItemSlot = panel.grid.get_child(1) as ItemSlot
		var seventh: ItemSlot = panel.grid.get_child(6) as ItemSlot
		var eighth: ItemSlot = panel.grid.get_child(7) as ItemSlot
		_expect(is_equal_approx(second.global_position.x - first.get_global_rect().end.x, 4.0)
			and is_equal_approx(seventh.global_position.y, first.global_position.y)
			and is_equal_approx(eighth.global_position.y - first.get_global_rect().end.y, 2.0),
			"Seven slots fit across with the Inventory spacing before the next row.")
		_expect(is_equal_approx(scrollbar.global_position.x - seventh.get_global_rect().end.x, 4.0),
			"The seventh slot and scrollbar are separated by four pixels.")
	panel._refresh_view()
	await _frames()
	_expect(not panel.feedback.visible and scroll.size.y == 102 and scrollbar.size.y == 102
		and panel.view.get_global_rect() == fixed_panel_rect
		and is_equal_approx(panel.view.get_global_rect().end.y - footer.get_global_rect().end.y, 16.0),
		"Storage hides feedback and keeps four rows and the footer within its fixed frame.")
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
	await _frames()
	_expect(scroll.scroll_vertical > 0, "Mouse wheel scrolls the actual storage grid.")
	scroll.scroll_vertical = 0
	await _frames()
	var start: Vector2 = scrollbar.get_global_rect().position + Vector2(scrollbar.size.x * 0.5, 5.0)
	var finish: Vector2 = scrollbar.get_global_rect().position + Vector2(scrollbar.size.x * 0.5, scrollbar.size.y - 5.0)
	var enter := InputEventMouseMotion.new()
	enter.position = start
	enter.global_position = start
	get_viewport().push_input(enter, true)
	await _frames()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	press.global_position = start
	get_viewport().push_input(press, true)
	await _frames()
	var motion := InputEventMouseMotion.new()
	motion.position = finish
	motion.global_position = finish
	motion.relative = finish - start
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion, true)
	await _frames()
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = finish
	release.global_position = finish
	get_viewport().push_input(release, true)
	await _frames()
	_expect(scroll.scroll_vertical > 0, "The City Storage scrollbar can be dragged.")
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
	_expect(panel._currency_amounts[1].text == "0"
		and panel._currency_amounts[1].accessibility_name == "Shekel: 0, placeholder", "Treasury changes do not alter the requested placeholder.")
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
	var annex_scroll: ScrollContainer = panel.grid.get_parent() as ScrollContainer
	var annex_footer: Control = panel.view.get_node("Margin/Content/Footer") as Control
	_expect(annex_scroll.size.y == 76
		and is_equal_approx(panel.view.get_global_rect().end.y - annex_footer.get_global_rect().end.y, 16.0),
		"Annex context retains complete rows and the bottom inset.")
	_expect(not panel.feedback.visible, "Annex storage also hides the feedback label.")
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
	for i in range(6):
		if panel.grid.get_child_count() == 0:
			break
		panel.categories.next_button.pressed.emit()
		await _frames()
	_expect(panel.grid.get_child_count() == 0 and not panel.feedback.visible and panel.feedback.text.is_empty(),
		"An empty category does not show a feedback message.")
	await _capture("storage-one-item.png")
	panel.close()
	await _frames()
	storage.items.clear()
	panel = CITY_UI.instantiate()
	add_child(panel)
	panel.open(storage, func() -> bool: return true)
	await _frames()
	_expect(panel.grid.get_child_count() == 0 and not panel.feedback.visible,
		"Empty storage has no fabricated cards or feedback message.")
	_expect(panel.view.get_global_rect() == fixed_panel_rect, "Empty storage retains the fixed frame.")
	_expect(panel.view.get_global_rect().encloses(panel.view.get_node("Margin/Content/Footer").get_global_rect())
		and is_equal_approx(panel.view.get_global_rect().end.y - panel.view.get_node("Margin/Content/Footer").get_global_rect().end.y, 16.0),
		"The footer remains inside the empty frame with the bottom inset.")
	await _capture("storage-empty.png")
	panel.close()
	await _frames()
	storage.free()
	print("CityStorageLayoutTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)
