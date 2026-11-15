extends Node

## Focused behavior and layout regression for the standalone building menu.
const MENU_SCENE: PackedScene = preload("res://scenes/ui/building_selection_ui/building_selection_ui.tscn")
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

func _rect_contains(outer: Rect2, inner: Rect2, tolerance: float = 1.0) -> bool:
	return (
		inner.position.x >= outer.position.x - tolerance
		and inner.position.y >= outer.position.y - tolerance
		and inner.end.x <= outer.end.x + tolerance
		and inner.end.y <= outer.end.y + tolerance
	)

func _check_button_row(menu: Variant, ids: Array[String], captions: Array[String], context: String) -> void:
	var row: HBoxContainer = menu.choices.find_child("ChoiceRow", true, false) as HBoxContainer
	_expect(row != null, context + " uses the dynamic ChoiceRow HBox.")
	if row == null:
		return
	var row_rect: Rect2 = row.get_global_rect()
	var choices_rect: Rect2 = menu.choices.get_global_rect()
	_expect(_rect_contains(choices_rect, row_rect), context + " row stays inside the choices area.")

	var previous_rect: Rect2 = Rect2()
	for index: int in range(ids.size()):
		var id: String = ids[index]
		var button: Button = menu.buttons.get(id) as Button
		_expect(button != null, context + " keeps " + id + " in menu.buttons.")
		if button == null:
			continue
		_expect(button.is_visible_in_tree(), context + " button " + id + " is visible.")
		var button_rect: Rect2 = button.get_global_rect()
		_expect(button_rect.size.is_equal_approx(Vector2(16, 16)), context + " button " + id + " is 16x16.")
		_expect(_rect_contains(row_rect, button_rect), context + " button " + id + " does not overflow its row.")
		_expect(_rect_contains(choices_rect, button_rect), context + " button " + id + " stays inside choices.")
		if index > 0:
			_expect(button_rect.position.x >= previous_rect.end.x, context + " icons appear left to right without overlapping.")
			_expect(is_equal_approx(button_rect.position.y, previous_rect.position.y), context + " icons share one row.")
		previous_rect = button_rect

		var caption: Label = button.get_parent().get_node_or_null("Caption") as Label
		_expect(caption != null, context + " button " + id + " has a Caption label.")
		if caption != null:
			_expect(caption.is_visible_in_tree(), context + " caption for " + id + " is visible.")
			_expect(caption.text.contains(captions[index]), context + " caption names " + captions[index] + ".")
			_expect(caption.get_global_rect().position.y >= button_rect.end.y, context + " caption for " + id + " appears below its icon.")
			_expect(_rect_contains(choices_rect, caption.get_global_rect()), context + " caption for " + id + " stays inside choices.")
			var font: Font = caption.get_theme_font("font")
			var text_height: float = caption.get_line_count() * font.get_height(caption.get_theme_font_size("font_size"))
			_expect(text_height <= caption.size.y + 1.0, context + " caption for " + id + " fits vertically.")

		_expect(button.icon != null, context + " button " + id + " has a placeholder icon.")
		if button.icon != null:
			_expect(button.icon.get_size().x <= 16 and button.icon.get_size().y <= 16, context + " placeholder for " + id + " fits inside the icon panel.")

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
	_check_button_row(menu, CATEGORY_ORDER, CATEGORY_CAPTIONS, "Category menu")
	_expect(menu.buttons["residential"].has_focus(), "Keyboard focus starts on Residential.")

	menu.buttons["residential"].emit_signal("pressed")
	await _frames()
	_expect(menu.current_category == "residential", "Residential opens its building choices.")
	_check_button_row(menu, ["house", "courtyard_house"], ["House", "Courtyard House"], "Residential menu")
	var house_button: Button = menu.buttons.get("house") as Button
	var courtyard_button: Button = menu.buttons.get("courtyard_house") as Button
	_expect(house_button != null and not house_button.disabled, "House is enabled.")
	_expect(courtyard_button != null and courtyard_button.disabled, "Courtyard House is locked.")
	if house_button != null:
		_expect(house_button.has_focus(), "Keyboard focus starts on House.")
	if courtyard_button != null:
		courtyard_button.emit_signal("pressed")
	_expect(events["house"] == 0, "The locked Courtyard House has no action.")
	if house_button != null:
		house_button.emit_signal("pressed")
	_expect(events["house"] == 1, "Choosing House emits house_requested exactly once.")
	_expect(events["workshop"] == 0, "Choosing a residential item does not request a workshop.")

	menu.back_button.emit_signal("pressed")
	await _frames()
	_expect(menu.current_category.is_empty(), "Back from residential returns to the category menu.")
	_check_button_row(menu, CATEGORY_ORDER, CATEGORY_CAPTIONS, "Category menu after Back")

	menu.buttons["production"].emit_signal("pressed")
	await _frames()
	var workshop_button: Button = menu.buttons.get("mudbrick_workshop") as Button
	_expect(menu.current_category == "production", "Production opens its building choices.")
	_check_button_row(menu, ["mudbrick_workshop"], ["Mudbrick Workshop"], "Locked Production menu")
	_expect(workshop_button != null and workshop_button.disabled, "Workshop is disabled when workshop_enabled is false.")
	var notice: Label = menu.choices.find_child("Notice", true, false) as Label
	_expect(notice != null and notice.text.contains("Not available yet"), "The locked Production choice explains its availability.")
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

	var close_button: TextureButton = menu.get_node("Root/Center/Window/Margin/Content/Header/CloseButton") as TextureButton
	close_button.emit_signal("pressed")
	await _frames()
	_expect(events["closed"] == 1, "The X button emits closed exactly once, including during tree exit.")
	_check_inventory_unchanged(inventory_before, inventory_max_load_before, inventory_bulk_before, int(inventory_change_events["count"]))

	print("BuildingIconMenuTest: %s (%d failed)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
