extends Node

## Focused behavior and layout regression for the standalone building menu.
const MENU_SCENE: PackedScene = preload("res://scenes/ui/building_selection_ui/building_selection_ui.tscn")
const LOCK_ICON: Texture2D = preload("res://assets/ui/ui_icon/lock_icon.png")
const PLACEHOLDER_ICON: Texture2D = preload("res://assets/ui/ui_icon/plus_icon_2.png")
const SELECTOR_SHEET: Texture2D = preload("res://assets/ui/ui_icon/icon_24.06.2026.png")
const CATEGORY_ORDER: Array[String] = [
	"residential", "production", "food_farming", "storage_logistic", "civic_services",
]
const CATEGORY_CAPTIONS: Array[String] = [
	"Residential", "Production", "Food & Farming", "Storage & Logistic", "Civic & Services",
]

var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _frames(count: int = 3) -> void:
	for _index: int in range(count):
		await get_tree().process_frame

func _move_mouse(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	get_viewport().push_input(motion, true)
	await _frames()

func _press_action(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	get_viewport().push_input(event)
	await _frames()
	event = InputEventAction.new()
	event.action = action
	get_viewport().push_input(event)
	await _frames()

func _rect_contains(outer: Rect2, inner: Rect2, tolerance: float = 1.0) -> bool:
	return (
		inner.position.x >= outer.position.x - tolerance
		and inner.position.y >= outer.position.y - tolerance
		and inner.end.x <= outer.end.x + tolerance
		and inner.end.y <= outer.end.y + tolerance
	)

func _check_compact_frame(menu: Variant, max_size: Vector2, context: String) -> void:
	var frame: Control = menu.get_node("Root/Center/Window") as Control
	var frame_rect: Rect2 = frame.get_global_rect()
	var interior: Rect2 = frame_rect.grow(-16.0)
	_expect(frame.size.x <= max_size.x and frame.size.y <= max_size.y, context + " panel remains compact.")
	for path: String in ["Margin/Content/Header", "Margin/Content/Subtitle", "Margin/Content/Choices"]:
		var control: Control = frame.get_node(path) as Control
		_expect(_rect_contains(interior, control.get_global_rect()), context + " keeps " + path + " inside its margins.")
	_expect(_rect_contains(interior, menu.close_button.get_global_rect()), context + " keeps X inside its margins.")
	var title: Label = menu.title_label
	var title_font: Font = title.get_theme_font("font")
	var title_width: float = title_font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title.get_theme_font_size("font_size")).x
	_expect(title_width <= title.size.x + 1.0, context + " title fits without clipping.")
	if menu.back_button.visible:
		var back_rect: Rect2 = menu.back_button.get_global_rect()
		_expect(_rect_contains(interior, back_rect), context + " keeps Back inside its margins.")
		_expect(is_equal_approx(back_rect.position.x, interior.position.x), context + " keeps Back at the lower left.")
		_expect(is_equal_approx(back_rect.end.y, interior.end.y), context + " keeps the bottom margin below Back.")
		_expect(not back_rect.intersects(menu.choices.get_global_rect()), context + " keeps Back separate from the choices.")
	var notice: Label = menu.choices.get_node_or_null("Notice") as Label
	if notice != null:
		_expect(_rect_contains(interior, notice.get_global_rect()), context + " keeps the notice inside its margins.")
		_expect(notice.get_line_count() * notice.get_line_height() <= notice.size.y + 1.0, context + " notice fits vertically.")

func _check_button_row(menu: Variant, ids: Array[String], captions: Array[String], context: String, hover_caption: bool = false) -> void:
	var row: HBoxContainer = menu.choices.find_child("ChoiceRow", true, false) as HBoxContainer
	_expect(row != null, context + " uses the dynamic ChoiceRow HBox.")
	if row == null:
		return
	var row_rect: Rect2 = row.get_global_rect()
	var choices_rect: Rect2 = menu.choices.get_global_rect()
	_expect(_rect_contains(choices_rect, row_rect), context + " row stays inside the choices area.")
	_expect(absf(row_rect.get_center().x - menu.window.get_global_rect().get_center().x) <= 0.5, context + " row is centered in the panel.")

	var previous_rect: Rect2 = Rect2()
	var first_center_x: float = 0.0
	var last_center_x: float = 0.0
	for index: int in range(ids.size()):
		var id: String = ids[index]
		var button: Button = menu.buttons.get(id) as Button
		_expect(button != null, context + " keeps " + id + " in menu.buttons.")
		if button == null:
			continue
		_expect(button.is_visible_in_tree(), context + " button " + id + " is visible.")
		var button_rect: Rect2 = button.get_global_rect()
		if index == 0:
			first_center_x = button_rect.get_center().x
		last_center_x = button_rect.get_center().x
		_expect(button_rect.size.is_equal_approx(Vector2(16, 16)), context + " button " + id + " is 16x16.")
		_expect(_rect_contains(row_rect, button_rect), context + " button " + id + " does not overflow its row.")
		_expect(_rect_contains(choices_rect, button_rect), context + " button " + id + " stays inside choices.")
		if index > 0:
			_expect(button_rect.position.x >= previous_rect.end.x, context + " icons appear left to right without overlapping.")
			_expect(is_equal_approx(button_rect.position.y, previous_rect.position.y), context + " icons share one row.")
			if hover_caption:
				_expect(is_equal_approx(button_rect.position.x - previous_rect.end.x, 8.0), context + " icons have an 8px gap.")
		previous_rect = button_rect

		var caption: Label = button.get_parent().get_node_or_null("Caption") as Label
		_expect(button.accessibility_name == captions[index], context + " button " + id + " keeps its accessible name.")
		_expect((caption == null) == hover_caption, context + " button " + id + " uses the expected name presentation.")
		if caption != null:
			_expect(caption.is_visible_in_tree(), context + " caption for " + id + " is visible.")
			_expect(caption.text == captions[index], context + " caption names " + captions[index] + " without a Locked suffix.")
			_expect(caption.get_global_rect().position.y >= button_rect.end.y, context + " caption for " + id + " appears below its icon.")
			_expect(_rect_contains(choices_rect, caption.get_global_rect()), context + " caption for " + id + " stays inside choices.")
			var font: Font = caption.get_theme_font("font")
			var text_height: float = caption.get_line_count() * font.get_height(caption.get_theme_font_size("font_size"))
			_expect(text_height <= caption.size.y + 1.0, context + " caption for " + id + " fits vertically.")

		var expected_icon: Texture2D = LOCK_ICON if button.disabled else PLACEHOLDER_ICON
		_expect(button.icon == expected_icon, context + " uses the lock inside the disabled panel and the placeholder otherwise for " + id + ".")
		if button.icon != null:
			_expect(button.icon.get_size().x <= 16 and button.icon.get_size().y <= 16 and not button.expand_icon, context + " icon for " + id + " fits at its native size inside the panel.")
		_expect(button.get_node_or_null("LockIcon") == null, context + " does not add a separate lock beside " + id + ".")
		var selection: NinePatchRect = button.get_node_or_null("SelectionFrame") as NinePatchRect
		_expect(selection != null and selection.mouse_filter == Control.MOUSE_FILTER_IGNORE, context + " has a non-intercepting selection frame for " + id + ".")
		if selection != null:
			var atlas: AtlasTexture = selection.texture as AtlasTexture
			_expect(atlas != null and atlas.atlas == SELECTOR_SHEET and atlas.region == Rect2(133, 101, 22, 22), context + " uses the Inventory/Work Order selector for " + id + ".")
			_expect(selection.size.is_equal_approx(Vector2(16, 16)), context + " keeps the selector aligned to the icon panel.")
			_expect(not button.has_theme_stylebox_override("focus"), context + " has no custom white focus border.")
	if not ids.is_empty():
		_expect(absf((first_center_x + last_center_x) * 0.5 - row_rect.get_center().x) <= 0.5, context + " icons are centered as a group.")

func _check_inventory_unchanged(before: Dictionary, max_load_before: float, bulk_before: bool, change_count: int) -> void:
	_expect(Inventory.items == before, "The menu leaves in-memory Inventory items unchanged.")
	_expect(is_equal_approx(Inventory.max_load, max_load_before), "The menu leaves Inventory capacity unchanged.")
	_expect(Inventory._bulk_transaction_in_progress == bulk_before, "The menu leaves Inventory transaction state unchanged.")
	_expect(change_count == 0, "The menu does not emit Inventory.items_changed.")

func _run() -> void:
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	var inventory_max_load_before: float = Inventory.max_load
	var inventory_bulk_before: bool = Inventory._bulk_transaction_in_progress
	var inventory_change_events: Dictionary = {"count": 0}
	Inventory.items_changed.connect(func() -> void: inventory_change_events["count"] += 1)

	var events: Dictionary = {"house": 0, "workshop": 0, "closed": 0}
	var menu: Variant = MENU_SCENE.instantiate()
	menu.workshop_enabled = false
	menu.house_requested.connect(func() -> void: events["house"] += 1)
	menu.workshop_requested.connect(func() -> void: events["workshop"] += 1)
	menu.closed.connect(func() -> void: events["closed"] += 1)
	add_child(menu)
	menu.open_menu("Plot 1")
	await _frames()

	_expect(menu.visible, "Opening the menu displays it in the test tree.")
	_expect(not menu.subtitle.text.contains("Plot 1"), "The subtitle omits the plot label.")
	_check_compact_frame(menu, Vector2(290, 105), "Category menu")
	_check_button_row(menu, CATEGORY_ORDER, CATEGORY_CAPTIONS, "Category menu")
	_expect((menu.buttons["residential"].get_parent().get_node("Caption") as Label).modulate.a == 1.0, "Category names remain visible.")
	_expect(menu.buttons["residential"].has_focus(), "Keyboard focus starts on Residential.")
	await _move_mouse(Vector2(1, 1))
	var residential_frame: NinePatchRect = menu.buttons["residential"].get_node("SelectionFrame") as NinePatchRect
	var production_frame: NinePatchRect = menu.buttons["production"].get_node("SelectionFrame") as NinePatchRect
	var civic_button: Button = menu.buttons["civic_services"] as Button
	var civic_frame: NinePatchRect = civic_button.get_node("SelectionFrame") as NinePatchRect
	_expect(residential_frame.visible, "Focused category uses the existing corner selector.")
	await _move_mouse(civic_button.get_global_rect().get_center())
	_expect(civic_frame.visible and not residential_frame.visible, "Mouse hover highlights only the hovered category.")
	await _press_action("ui_right")
	_expect(menu.buttons["production"].has_focus() and production_frame.visible and not civic_frame.visible, "Keyboard navigation highlights the focused category.")
	await _move_mouse(civic_button.get_global_rect().get_center() + Vector2(1, 0))
	_expect(civic_frame.visible and not production_frame.visible, "Moving the mouse restores the hovered highlight.")
	await _move_mouse(Vector2(1, 1))
	menu.buttons["residential"].grab_focus()
	await _frames()

	menu.buttons["residential"].emit_signal("pressed")
	await _frames()
	_expect(menu.current_category == "residential", "Residential opens its building choices.")
	_check_compact_frame(menu, Vector2(200, 135), "Residential menu")
	_check_button_row(menu, ["house", "courtyard_house"], ["House", "Courtyard House"], "Residential menu", true)
	var house_button: Button = menu.buttons.get("house") as Button
	var courtyard_button: Button = menu.buttons.get("courtyard_house") as Button
	_expect(house_button != null and not house_button.disabled, "House is enabled.")
	_expect(courtyard_button != null and courtyard_button.disabled, "Courtyard House is locked.")
	await _move_mouse(Vector2(1, 1))
	var frame_before_hover: Rect2 = menu.window.get_global_rect()
	_expect(not menu.hover_name.visible, "Building names are hidden without a hover.")
	var mouse_position: Vector2 = house_button.get_global_rect().get_center()
	await _move_mouse(mouse_position)
	_expect(menu.hover_name.visible and menu.hover_name.text == "House", "Hovering House shows its name.")
	_expect(menu.hover_name.position.x > mouse_position.x and menu.hover_name.position.y < mouse_position.y, "The name appears above and to the right of the mouse.")
	_expect(not menu.hover_name.get_global_rect().intersects(menu.subtitle.get_global_rect()), "The name does not overlap the subtitle.")
	_expect(not menu.hover_name.get_global_rect().intersects(house_button.get_global_rect()) and not menu.hover_name.get_global_rect().intersects(courtyard_button.get_global_rect()), "The name does not overlap the building icons.")
	_expect(menu.hover_name.mouse_filter == Control.MOUSE_FILTER_IGNORE, "The hover name does not intercept mouse input.")
	_expect(menu.window.get_global_rect().is_equal_approx(frame_before_hover), "The panel stays in place while hovering House.")
	var prior_name_position: Vector2 = menu.hover_name.position
	await _move_mouse(mouse_position + Vector2(4, 0))
	_expect(is_equal_approx(menu.hover_name.position.x - prior_name_position.x, 4.0), "The name follows the mouse within the icon.")
	for pointer_y: float in [1.0, 15.0]:
		await _move_mouse(house_button.get_global_rect().position + Vector2(8.0, pointer_y))
		_expect(not menu.hover_name.get_global_rect().intersects(menu.subtitle.get_global_rect()), "The name clears the subtitle throughout the icon.")
		_expect(not menu.hover_name.get_global_rect().intersects(courtyard_button.get_global_rect()), "The name clears the adjacent icon throughout the icon.")
	mouse_position = courtyard_button.get_global_rect().get_center()
	await _move_mouse(mouse_position)
	_expect(menu.hover_name.visible and menu.hover_name.text == "Courtyard House", "Hovering locked Courtyard House shows its name.")
	_expect(not (courtyard_button.get_node("SelectionFrame") as NinePatchRect).visible and not (house_button.get_node("SelectionFrame") as NinePatchRect).visible, "Locked hover does not show a selection frame.")
	_expect(menu.hover_name.position.x > mouse_position.x and menu.hover_name.position.y < mouse_position.y, "The locked building name appears above and to the right of the mouse.")
	_expect(not menu.hover_name.get_global_rect().intersects(menu.subtitle.get_global_rect()), "The locked building name does not overlap the subtitle.")
	_expect(not menu.hover_name.get_global_rect().intersects(house_button.get_global_rect()) and not menu.hover_name.get_global_rect().intersects(courtyard_button.get_global_rect()), "The locked building name does not overlap the icons.")
	_expect(menu.window.get_global_rect().is_equal_approx(frame_before_hover), "The panel stays in place while hovering a locked building.")
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	menu._position_hover_name(Vector2(viewport_rect.end.x - 1.0, viewport_rect.position.y + 1.0))
	_expect(_rect_contains(viewport_rect, menu.hover_name.get_global_rect()), "A name near the screen edge stays within the viewport.")
	await _move_mouse(Vector2(1, 1))
	_expect(not menu.hover_name.visible, "Building names disappear after the pointer leaves.")
	if house_button != null:
		_expect(house_button.has_focus(), "Keyboard focus starts on House.")
	if courtyard_button != null:
		courtyard_button.emit_signal("pressed")
	_expect(events["house"] == 0, "The locked Courtyard House has no action.")
	if house_button != null:
		house_button.emit_signal("pressed")
	_expect(events["house"] == 1, "Choosing House emits house_requested exactly once.")
	_expect(events["workshop"] == 0, "Choosing a residential item does not request a workshop.")
	menu._add_button("qa_extra_building", "Extra", Callable(), true, true)
	await _frames()
	_check_button_row(menu, ["house", "courtyard_house", "qa_extra_building"], ["House", "Courtyard House", "Extra"], "Three building choices", true)
	var expanded_ids: Array[String] = ["house", "courtyard_house", "qa_extra_building"]
	var expanded_names: Array[String] = ["House", "Courtyard House", "Extra"]
	for index: int in range(2, 6):
		var id: String = "qa_extra_%d" % index
		var name_text: String = "Extra %d" % index
		menu._add_button(id, name_text, Callable(), true, true)
		expanded_ids.append(id)
		expanded_names.append(name_text)
	await _frames()
	_check_button_row(menu, expanded_ids, expanded_names, "Seven building choices", true)

	menu.back_button.emit_signal("pressed")
	await _frames()
	_expect(menu.current_category.is_empty(), "Back from residential returns to the category menu.")
	_check_compact_frame(menu, Vector2(290, 105), "Category menu after Back")
	_check_button_row(menu, CATEGORY_ORDER, CATEGORY_CAPTIONS, "Category menu after Back")

	menu.buttons["production"].emit_signal("pressed")
	await _frames()
	var workshop_button: Button = menu.buttons.get("mudbrick_workshop") as Button
	_expect(menu.current_category == "production", "Production opens its building choices.")
	_check_compact_frame(menu, Vector2(200, 145), "Locked Production menu")
	_check_button_row(menu, ["mudbrick_workshop"], ["Mudbrick Workshop"], "Locked Production menu", true)
	_expect(workshop_button != null and workshop_button.disabled, "Workshop is disabled when workshop_enabled is false.")
	await _move_mouse(workshop_button.get_global_rect().get_center())
	_expect(menu.hover_name.visible and menu.hover_name.text == "Mudbrick Workshop", "Hovering locked Workshop shows its name.")
	await _move_mouse(Vector2(1, 1))
	_expect(not menu.hover_name.visible, "Workshop name disappears after the pointer leaves.")
	_expect(menu.choices.get_node_or_null("Notice") == null, "The locked Production choice has no extra notice.")
	_expect(menu.back_button.visible, "Back remains visible in the Production menu.")
	await _frames()
	_expect(menu.back_button.has_focus(), "Back receives keyboard focus for the locked Production choice.")
	if workshop_button != null:
		workshop_button.emit_signal("pressed")
	_expect(events["workshop"] == 0, "The locked Workshop has no action.")
	menu.back_button.emit_signal("pressed")
	await _frames()
	_expect(menu.current_category.is_empty(), "Back from locked Production returns to categories.")
	_expect(menu.buttons.has("production"), "Production is available again after Back.")
	for category: String in ["food_farming", "storage_logistic", "civic_services"]:
		menu.buttons[category].emit_signal("pressed")
		await _frames()
		_expect(menu.buttons.is_empty(), category + " keeps its empty state.")
		_check_compact_frame(menu, Vector2(230, 110), category + " menu")
		menu.back_button.emit_signal("pressed")
		await _frames()
		_expect(menu.current_category.is_empty(), "Back from " + category + " returns to categories.")
		_check_compact_frame(menu, Vector2(290, 105), "Category menu after " + category)

	# A longer existing notice must also fit if a workshop has reached its limit.
	menu.workshop_enabled = true
	menu.workshop_available = false
	menu.buttons["production"].emit_signal("pressed")
	await _frames()
	_check_compact_frame(menu, Vector2(200, 160), "Workshop limit menu")
	_check_button_row(menu, ["mudbrick_workshop"], ["Mudbrick Workshop (Limit: 1)"], "Workshop limit menu", true)
	_expect(menu.buttons["mudbrick_workshop"].disabled, "A workshop at its limit remains disabled.")
	menu.back_button.emit_signal("pressed")
	await _frames()

	var close_button: TextureButton = menu.get_node("Root/Center/Window/Margin/Content/Header/CloseButton") as TextureButton
	close_button.emit_signal("pressed")
	await _frames()
	_expect(events["closed"] == 1, "The X button emits closed exactly once, including during tree exit.")
	_check_inventory_unchanged(inventory_before, inventory_max_load_before, inventory_bulk_before, int(inventory_change_events["count"]))

	print("BuildingIconMenuTest: %s (%d failed)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
