extends CanvasLayer

signal closed

@onready var view: Control = $Root/Center/CityStorage
@onready var grid: GridContainer = $Root/Center/CityStorage/Margin/Content/BagGrid/Margin/MainVBox/Scroll/Grid
@onready var categories: InventoryCategorySelector = $Root/Center/CityStorage/Margin/Content/Header/Categories
@onready var feedback: Label = $Root/Center/CityStorage/Margin/Content/Feedback
@onready var context: Label = $Root/Center/CityStorage/Margin/Content/ContextLabel
@onready var food_summary: Label = $Root/CitySupplyPanel/Margin/Content/FoodSummary
@onready var clothing_summary: Label = $Root/CitySupplyPanel/Margin/Content/ClothingSummary

var stock_summary: RichTextLabel

var storage: Node
var access_check: Callable
var deposit_button: Button
var transfer_ui: ItemTransferUI
var clear_button: Button
var item_info: ItemInfoPanel
var _transfer_mode: String = ""
var _previous_tree_paused: bool = false
var _owns_pause: bool = false
var _feedback_text: String = ""
var _citizen_manager: Node
var _needs_manager: Node

func _ready() -> void:
	visible = false
	context.hide()
	stock_summary = RichTextLabel.new()
	stock_summary.name = "StockSummary"
	stock_summary.bbcode_enabled = true
	stock_summary.fit_content = true
	stock_summary.scroll_active = false
	stock_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stock_summary.add_theme_font_override("normal_font", context.get_theme_font("font"))
	stock_summary.add_theme_font_size_override("normal_font_size", 6)
	context.get_parent().add_child(stock_summary)
	context.get_parent().move_child(stock_summary, context.get_index() + 1)
	view.get_node("Margin/Content/Footer/Back").pressed.connect(close)
	view.get_node("Close").pressed.connect(close)
	var footer: Node = view.get_node("Margin/Content/Footer")
	deposit_button = _make_button("Deposit", footer)
	deposit_button.pressed.connect(_open_transfer.bind("deposit"))
	categories.category_changed.connect(func(_category): _refresh_view())
	grid.get_parent().vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	item_info = preload("res://scenes/ui/item_info_panel_root/item_info_panel.tscn").instantiate()
	$Root.add_child(item_info)
	_connect_refresh_signals()
	_add_supply_icon(food_summary, preload("res://assets/items/butcher’s_cut.png"))
	_add_supply_icon(clothing_summary, preload("res://assets/items/trimmed_robe.png"))

func _add_supply_icon(summary: Label, texture: Texture2D) -> void:
	var parent: Node = summary.get_parent()
	var index: int = summary.get_index()
	var row := HBoxContainer.new()
	row.name = summary.name + "Row"
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	parent.move_child(row, index)
	var frame := TextureRect.new()
	frame.name = "IconPanel"
	var panel_texture := AtlasTexture.new()
	panel_texture.atlas = preload("res://assets/ui/ui_panel/brown_panel_24x24.png")
	panel_texture.region = Rect2(1, 1, 24, 24)
	frame.texture = panel_texture
	frame.custom_minimum_size = Vector2(24, 24)
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(frame)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(20, 20)
	icon.texture = texture
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	summary.reparent(row)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	summary.mouse_filter = Control.MOUSE_FILTER_STOP

func open(provider: Node, gate: Callable) -> void:
	storage = provider
	access_check = gate
	if not _has_access():
		close()
		return
	_previous_tree_paused = get_tree().paused
	_owns_pause = true
	get_tree().paused = true
	visible = true
	if not Inventory.items_changed.is_connected(_on_stock_changed):
		Inventory.items_changed.connect(_on_stock_changed, CONNECT_DEFERRED)
	if storage.has_signal("changed") and not storage.changed.is_connected(_on_stock_changed):
		storage.changed.connect(_on_stock_changed, CONNECT_DEFERRED)
	_refresh_view()

func _has_access() -> bool:
	return is_instance_valid(storage) and access_check.is_valid() and bool(access_check.call())

func _process(_delta: float) -> void:
	if visible and not _has_access():
		close()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		if is_instance_valid(transfer_ui):
			transfer_ui._on_back_pressed()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_worker_hub") or event.is_action_pressed("open_inventory") or event.is_action_pressed("open_work_progress") or event.is_action_pressed("show_player_status"):
		get_viewport().set_input_as_handled()

func close() -> void:
	visible = false
	if is_instance_valid(transfer_ui):
		transfer_ui.hide()
		transfer_ui.queue_free()
	transfer_ui = null
	if Inventory.items_changed.is_connected(_on_stock_changed):
		Inventory.items_changed.disconnect(_on_stock_changed)
	if is_instance_valid(storage) and storage.changed.is_connected(_on_stock_changed):
		storage.changed.disconnect(_on_stock_changed)
	_disconnect_refresh_signals()
	_restore_pause()
	closed.emit()
	queue_free()

func _exit_tree() -> void:
	_disconnect_refresh_signals()
	_restore_pause()

func _connect_refresh_signals() -> void:
	if TimeComponentManager.has_signal("time_changed") and not TimeComponentManager.time_changed.is_connected(_on_time_changed):
		TimeComponentManager.time_changed.connect(_on_time_changed, CONNECT_DEFERRED)
	_citizen_manager = get_node_or_null("/root/CitizenManager")
	if is_instance_valid(_citizen_manager) and _citizen_manager.has_signal("citizen_added") and not _citizen_manager.is_connected("citizen_added", _on_citizen_added):
		_citizen_manager.connect("citizen_added", _on_citizen_added, CONNECT_DEFERRED)
	_needs_manager = get_node_or_null("/root/CitizenNeedsManager")
	if is_instance_valid(_needs_manager) and not _needs_manager.is_connected("needs_changed", _on_needs_changed):
		_needs_manager.connect("needs_changed", _on_needs_changed, CONNECT_DEFERRED)

func _disconnect_refresh_signals() -> void:
	if TimeComponentManager.has_signal("time_changed") and TimeComponentManager.time_changed.is_connected(_on_time_changed):
		TimeComponentManager.time_changed.disconnect(_on_time_changed)
	if is_instance_valid(_citizen_manager) and _citizen_manager.has_signal("citizen_added") and _citizen_manager.is_connected("citizen_added", _on_citizen_added):
		_citizen_manager.disconnect("citizen_added", _on_citizen_added)
	if is_instance_valid(_needs_manager) and _needs_manager.is_connected("needs_changed", _on_needs_changed):
		_needs_manager.disconnect("needs_changed", _on_needs_changed)

func _on_time_changed(_day: int, _hour: int, _minute: int, _weather: String) -> void:
	if visible:
		_refresh_food_summary()
		_refresh_clothing_summary()

func _on_citizen_added(_citizen: Variant) -> void:
	if visible:
		_refresh_food_summary()
		_refresh_clothing_summary()

func _on_needs_changed() -> void:
	if visible:
		_refresh_food_summary()
		_refresh_clothing_summary()

func _restore_pause() -> void:
	if _owns_pause:
		get_tree().paused = _previous_tree_paused
		_owns_pause = false

func _on_stock_changed() -> void:
	if not visible:
		return
	_refresh_view()
	if is_instance_valid(transfer_ui):
		_refresh_transfer()

func _refresh_view() -> void:
	if not is_instance_valid(storage):
		return
	var food_supply_summary: Dictionary = _refresh_food_summary()
	_refresh_clothing_summary()
	item_info.clear_item()
	for child: Node in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var items: Dictionary = storage.get_available_items()
	var item_ids: Array = items.keys()
	item_ids.sort()
	var quantity: int = 0
	var equipped: int = 0
	for unit: Dictionary in storage.units.values():
		if not str(unit.get("worker_id", "")).is_empty():
			equipped += 1
	for item_id: String in item_ids:
		quantity += int(items[item_id])
		var item: ItemData = ItemDatabase.get_item_data(item_id)
		if item == null or (categories.get_selected_category() != -1 and item.category != categories.get_selected_category()):
			continue
		var slot: ItemSlot = preload("res://scenes/ui/item_slot/item_slot.tscn").instantiate()
		grid.add_child(slot)
		slot.set_item(item_id, int(items[item_id]), item.icon)
		slot.interaction_locked = true
		slot.mouse_entered.connect(_show_item_info.bind(item_id))
		slot.mouse_exited.connect(item_info.clear_item)
	stock_summary.text = "[center]Available: %d [img=2x6]res://assets/ui/ui_icon/separator_icon_2.png[/img] Equipped: %d[/center]" % [quantity, equipped]
	feedback.text = _feedback_text
	if feedback.text.is_empty() and grid.get_child_count() == 0:
		if items.is_empty() and int(food_supply_summary.get("portion_points", 0)) > 0:
			feedback.text = "Prepared food remains."
		else:
			feedback.text = "No available items." if items.is_empty() else "No items in this category."
	for index: int in range(maxi(15 - grid.get_child_count(), 0)):
		var slot: ItemSlot = preload("res://scenes/ui/item_slot/item_slot.tscn").instantiate()
		grid.add_child(slot)
		slot.set_empty()
	deposit_button.disabled = storage.get_depositable_items().is_empty()
	if feedback.text.is_empty():
		feedback.text = "Food, clothes, Shekel, tools."

func _refresh_food_summary() -> Dictionary:
	if not is_instance_valid(food_summary):
		return {}
	var summary: Dictionary = _get_food_supply_summary(storage)
	var points: int = int(summary.get("points", 0))
	var daily_need: int = int(summary.get("daily_need", 0))
	var days_remaining: int = int(summary.get("days_remaining", -1))
	food_summary.text = "Food  %d pt\n%d pt / day\n%s" % [points, daily_need, "%d days" % days_remaining if days_remaining >= 0 and daily_need > 0 else "-"]
	if daily_need > 0 and points < daily_need:
		food_summary.text += "\nShortage"
	return summary

func _get_food_supply_summary(provider: Node = null) -> Dictionary:
	var manager: Node = get_node_or_null("/root/CitizenNeedsManager")
	if not is_instance_valid(manager) or not manager.has_method("get_food_supply_summary"):
		return {}
	var result: Variant = manager.call("get_food_supply_summary", provider)
	return result if result is Dictionary else {}

func _refresh_clothing_summary() -> void:
	if not is_instance_valid(clothing_summary):
		return
	if not is_instance_valid(_needs_manager):
		clothing_summary.text = "Clothing Supply\nUnavailable"
		return
	var summary: Dictionary = _needs_manager.get_clothing_supply_summary(storage)
	var people: int = int(summary.consumer_count)
	var covered: int = int(summary.covered_count)
	var reserve: int = int(summary.stock_items)
	var awaiting: int = int(summary.replacement_need)
	var shortage: int = maxi(0, awaiting - reserve)
	clothing_summary.text = "Clothing  %d/%d\nReserve: %d" % [covered, people, reserve]
	if shortage > 0:
		clothing_summary.text += "\nShort: %d" % shortage
	elif awaiting > 0:
		clothing_summary.text += "\nReady tomorrow"

func _show_item_info(item_id: String) -> void:
	if not view.visible or not item_info.display_item(item_id):
		return
	var footer: Control = view.get_node("Margin/Content/Footer")
	item_info.position_lower_center(footer.global_position.y)

func _open_transfer(mode: String) -> void:
	if not visible or not view.visible or is_instance_valid(transfer_ui) or mode != "deposit":
		return
	if not _has_access():
		close()
		return
	_transfer_mode = mode
	_feedback_text = ""
	item_info.clear_item()
	$Root.hide()
	transfer_ui = preload("res://scenes/ui/item_transfer_ui/item_transfer_ui.tscn").instantiate()
	add_child(transfer_ui)
	transfer_ui.allowed_category = InventoryCategorySelector.CATEGORY_ALL
	transfer_ui.transfer_confirmed.connect(_confirm_transfer.bind(transfer_ui))
	transfer_ui.transfer_back_requested.connect(_return_from_transfer.bind(transfer_ui))
	transfer_ui.transfer_cancelled.connect(_return_from_transfer.bind(transfer_ui))
	clear_button = _make_button("Clear", transfer_ui.back_button.get_parent())
	clear_button.get_parent().move_child(clear_button, transfer_ui.back_button.get_index())
	clear_button.pressed.connect(_clear_transfer.bind(transfer_ui))
	_refresh_transfer()

func _refresh_transfer() -> void:
	var items: Dictionary = {}
	for row: Dictionary in storage.get_depositable_items():
		items[str(row.item_id)] = int(row.quantity)
	transfer_ui.open_transfer("Deposit to City (no return)", items, "Deposit")

func _clear_transfer(source: ItemTransferUI) -> void:
	if not is_instance_valid(transfer_ui) or transfer_ui != source:
		return
	source.selected_items.clear()
	for slot: ItemSlot in source.grid_container.get_children():
		slot.set_selected_quantity(0)
	source._refresh_summary()

func _confirm_transfer(items: Dictionary, source: ItemTransferUI) -> void:
	if _owns_pause:
		get_tree().paused = true
	if not visible or not is_instance_valid(transfer_ui) or transfer_ui != source:
		return
	if not _has_access():
		close()
		return
	_return_from_transfer(source)
	var result: Dictionary = storage.deposit_items_from_inventory(items)
	_feedback_text = str(result.message)
	_refresh_view()

func _return_from_transfer(source: ItemTransferUI) -> void:
	# The quantity dialog releases its own pause before emitting.
	if _owns_pause:
		get_tree().paused = true
	if not visible or not is_instance_valid(transfer_ui) or transfer_ui != source:
		return
	transfer_ui = null
	clear_button = null
	_transfer_mode = ""
	if not _has_access():
		close()
		return
	$Root.show()
	_refresh_view()

func _make_button(text: String, parent: Node) -> Button:
	var button := Button.new()
	button.name = text + "Button"
	button.text = text
	button.custom_minimum_size = Vector2(44, 16)
	button.theme_type_variation = &"HudShortcutButton"
	button.add_theme_font_size_override("font_size", 6)
	parent.add_child(button)
	return button
