extends CanvasLayer

signal closed

const PANEL_SIZE := Vector2(240, 208)
const ITEM_SCROLLBAR_THEME: Theme = preload("res://resources/ui_gameplay_theme/ui_gameplay_theme.tres")
const ITEM_SCROLLBAR_TEXTURE: Texture2D = preload("res://assets/ui/ui_icon/vertical_scrollbar.png")
const ITEM_VIEW_HEIGHT: float = 102.0 # Four 24px rows and three 2px gaps.
const ITEM_VIEW_COMPACT_HEIGHT: float = 76.0 # Three rows for the Annex context.
const ITEM_SCROLLBAR_WIDTH: float = 8.0
const CURRENCY_ICONS: Array[Texture2D] = [
	preload("res://resources/ui_icons/small_copper.tres"),
	preload("res://resources/ui_icons/small_shekel.tres"),
	preload("res://resources/ui_icons/small_gold.tres"),
]
const BACK_ICON: Texture2D = preload("res://assets/ui/ui_icon/back_button.png")
const DEPOSIT_ICON: Texture2D = preload("res://assets/ui/ui_icon/deposit_icon.png")
const SEND_ICON: Texture2D = preload("res://assets/ui/ui_icon/send_forward_icon.png")

@onready var view: Control = $Root/Center/CityStorage
@onready var grid: GridContainer = $Root/Center/CityStorage/Margin/Content/BagGrid/Margin/MainVBox/Scroll/Grid
@onready var item_scroll: ScrollContainer = $Root/Center/CityStorage/Margin/Content/BagGrid/Margin/MainVBox/Scroll
@onready var categories: InventoryCategorySelector = $Root/Center/CityStorage/Margin/Content/Header/Categories
@onready var feedback: Label = $Root/Center/CityStorage/Margin/Content/Feedback
@onready var context: Label = $Root/Center/CityStorage/Margin/Content/ContextLabel
@onready var food_summary: Label = $Root/CitySupplyPanel/Margin/Content/FoodSummary
@onready var clothing_summary: Label = $Root/CitySupplyPanel/Margin/Content/ClothingSummary

var stock_summary: HBoxContainer
var _status_row: HBoxContainer
var _currency_amounts: Array[Label] = []

var storage: Node
var storage_id: String = "city"
var access_check: Callable
var read_only: bool = false
var deposit_button: Button
var haul_button: Button
var transfer_ui: ItemTransferUI
var haul_ui: Control
var clear_button: Button
var _transfer_mode: String = ""
var _previous_tree_paused: bool = false
var _owns_pause: bool = false
var _citizen_manager: Node
var _needs_manager: Node
var item_info_panel: ItemInfoPanel
var _hovered_item_slot: ItemSlot
var _transaction_feedback_tween: Tween
var _transaction_feedback_font_size: int = 6

func _ready() -> void:
	visible = false
	# Keep one fixed frame for every category, including empty stock.
	view.custom_minimum_size = PANEL_SIZE
	var content_margin: MarginContainer = view.get_node("Margin") as MarginContainer
	content_margin.add_theme_constant_override("margin_left", 16)
	content_margin.add_theme_constant_override("margin_top", 16)
	content_margin.add_theme_constant_override("margin_right", 16)
	content_margin.add_theme_constant_override("margin_bottom", 16)
	context.custom_minimum_size.y = 0
	var bag_grid: Control = view.get_node("Margin/Content/BagGrid")
	bag_grid.custom_minimum_size = Vector2.ZERO
	bag_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	context.hide()
	$Root/CitySupplyPanel.hide()
	_build_currency_summary()
	feedback.reparent(view)
	feedback.set_anchors_preset(Control.PRESET_TOP_LEFT)
	feedback.theme = preload("res://resources/ui_inventory_theme/ui_inventory_theme.tres")
	feedback.theme_type_variation = &"InventoryTextSmall"
	feedback.add_theme_font_size_override("font_size", _transaction_feedback_font_size)
	feedback.add_theme_color_override("font_shadow_color", Color(0.12, 0.08, 0.05, 0.85))
	feedback.add_theme_constant_override("shadow_offset_x", 1)
	feedback.add_theme_constant_override("shadow_offset_y", 1)
	feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	feedback.autowrap_mode = TextServer.AUTOWRAP_OFF
	feedback.max_lines_visible = 1
	feedback.clip_text = true
	feedback.z_index = 20
	feedback.hide()
	item_info_panel = preload("res://scenes/ui/item_info_panel_root/item_info_panel.tscn").instantiate() as ItemInfoPanel
	$Root.add_child(item_info_panel)
	var back_button: Button = view.get_node("Margin/Content/Footer/Back") as Button
	back_button.custom_minimum_size = Vector2(64, 18)
	_set_action_icon(back_button, BACK_ICON)
	back_button.pressed.connect(close)
	view.get_node("Close").pressed.connect(close)
	var footer: Node = view.get_node("Margin/Content/Footer")
	deposit_button = _make_button("Deposit", footer, 64.0)
	_set_action_icon(deposit_button, DEPOSIT_ICON)
	deposit_button.pressed.connect(_open_transfer.bind("deposit"))
	categories.category_changed.connect(func(_category): _refresh_view())
	# The shared ItemGrid supplies Inventory's slot spacing.
	grid.columns = 7
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	item_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	item_scroll.custom_minimum_size.y = ITEM_VIEW_HEIGHT
	item_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var scrollbar: VScrollBar = item_scroll.get_v_scroll_bar()
	scrollbar.theme = ITEM_SCROLLBAR_THEME
	scrollbar.custom_minimum_size.x = ITEM_SCROLLBAR_WIDTH
	_configure_item_scrollbar(scrollbar)
	_connect_refresh_signals()
	_add_supply_icon(food_summary, preload("res://assets/items/butcher’s_cut.png"))
	_add_supply_icon(clothing_summary, preload("res://assets/items/trimmed_robe.png"))

func _configure_item_scrollbar(scrollbar: VScrollBar) -> void:
	# Match Inventory: the existing artwork is a fixed rail with a moving highlight.
	var rail_image: Image = ITEM_SCROLLBAR_TEXTURE.get_image()
	var rail_color: Color = rail_image.get_pixel(3, 7)
	for y in range(3, 7):
		for x in range(3, 5):
			rail_image.set_pixel(x, y, rail_color)
	var rail := StyleBoxTexture.new()
	rail.texture = ImageTexture.create_from_image(rail_image)
	rail.texture_margin_left = 2.0
	rail.texture_margin_right = 2.0
	rail.texture_margin_top = 3.0
	rail.texture_margin_bottom = 3.0
	scrollbar.add_theme_stylebox_override("scroll", rail)
	scrollbar.add_theme_stylebox_override("scroll_focus", rail)
	var highlight := AtlasTexture.new()
	highlight.atlas = ITEM_SCROLLBAR_TEXTURE
	highlight.region = Rect2(3, 3, 2, 1)
	var thumb := StyleBoxTexture.new()
	thumb.texture = highlight
	thumb.expand_margin_left = -3.0
	thumb.expand_margin_right = -3.0
	thumb.expand_margin_top = -3.0
	thumb.expand_margin_bottom = -3.0
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		scrollbar.add_theme_stylebox_override(state, thumb)

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

func open(provider: Node, gate: Callable, next_storage_id: String = "city", browse_only: bool = false) -> void:
	storage_id = "annex" if next_storage_id == "annex" else "city"
	read_only = browse_only
	storage = _resolve_storage_provider(provider)
	access_check = gate
	if not _has_access():
		close()
		return
	_set_location_presentation()
	_ensure_haul_button()
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

func _resolve_storage_provider(provider: Node) -> Node:
	var manager: Node = _get_transport_manager()
	if is_instance_valid(manager) and manager.has_method("get_storage"):
		var resolved: Variant = manager.call("get_storage", storage_id)
		if resolved is Node and is_instance_valid(resolved):
			return resolved
	# Annex stock is only defined by the city transport runtime. Falling back to
	# the central provider here could make the two physical locations look alike.
	if storage_id == "annex":
		return null
	return provider if is_instance_valid(provider) else null

func _get_transport_manager() -> Node:
	return get_tree().get_first_node_in_group("city_storage_transport")

func _set_location_presentation() -> void:
	var title: Label = view.get_node("Margin/Content/TitleRow/Title")
	$Root/CitySupplyPanel.hide()
	if storage_id == "annex":
		title.text = "City-Owned\nAnnex"
		context.text = "Citizens use Central Storage.\nPlayer deposits go to Central."
		context.show()
		deposit_button.disabled = true
	else:
		title.text = "City Storage"
		context.text = ""
		context.hide()
		deposit_button.disabled = false

func _ensure_haul_button() -> void:
	var manager: Node = _get_transport_manager()
	if not is_instance_valid(manager):
		return
	if is_instance_valid(haul_button):
		return
	haul_button = _make_button("Send", deposit_button.get_parent(), 64.0)
	_set_action_icon(haul_button, SEND_ICON)
	haul_button.pressed.connect(_open_haul)

func _open_haul() -> void:
	if read_only or not visible or not view.visible or is_instance_valid(transfer_ui) or is_instance_valid(haul_ui):
		return
	if not _has_access():
		close()
		return
	var manager: Node = _get_transport_manager()
	if not is_instance_valid(manager):
		return
	_clear_item_info()
	$Root.hide()
	haul_ui = preload("res://scenes/storage_destination/city_storage_haul_ui.tscn").instantiate()
	add_child(haul_ui)
	_cancel_transaction_feedback()
	feedback.reparent(haul_ui.get_node("Center/Panel"))
	haul_ui.connect("action_feedback", Callable(self, "_show_transaction_feedback"))
	haul_ui.connect("closed", Callable(self, "_on_haul_ui_closed").bind(haul_ui))
	haul_ui.call("open", manager, storage_id)

func _on_haul_ui_closed(source: Control) -> void:
	if haul_ui != source:
		return
	_cancel_transaction_feedback()
	feedback.reparent(view)
	haul_ui = null
	if not _has_access():
		close()
		return
	$Root.show()
	_refresh_view()

func _process(_delta: float) -> void:
	if visible and not _has_access():
		close()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if read_only and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C \
		and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and not event.shift_pressed:
		close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		if is_instance_valid(haul_ui):
			haul_ui.call("close")
		elif is_instance_valid(transfer_ui):
			transfer_ui._on_back_pressed()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_worker_hub") or event.is_action_pressed("open_inventory") or event.is_action_pressed("open_work_progress") or event.is_action_pressed("show_player_status"):
		get_viewport().set_input_as_handled()

func close() -> void:
	_clear_item_info()
	_cancel_transaction_feedback()
	visible = false
	if is_instance_valid(transfer_ui):
		transfer_ui.hide()
		transfer_ui.queue_free()
	transfer_ui = null
	if is_instance_valid(haul_ui):
		haul_ui.queue_free()
	haul_ui = null
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
	if visible and storage_id == "city":
		_refresh_food_summary()
		_refresh_clothing_summary()

func _on_citizen_added(_citizen: Variant) -> void:
	if visible and storage_id == "city":
		_refresh_food_summary()
		_refresh_clothing_summary()

func _on_needs_changed() -> void:
	if visible and storage_id == "city":
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
	_clear_item_info()
	if storage_id == "city":
		_refresh_food_summary()
		_refresh_clothing_summary()
	else:
		food_summary.text = "Citizens use Central Storage."
		clothing_summary.text = "Citizens use Central Storage."
	for child: Node in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var items: Dictionary = _get_available_items(storage_id)
	var item_ids: Array = items.keys()
	item_ids.sort()
	for item_id: String in item_ids:
		var item: ItemData = ItemDatabase.get_item_data(item_id)
		if item == null or (categories.get_selected_category() != -1 and item.category != categories.get_selected_category()):
			continue
		var slot: ItemSlot = preload("res://scenes/ui/item_slot/item_slot.tscn").instantiate()
		grid.add_child(slot)
		slot.set_item(item_id, int(items[item_id]), item.icon)
		# Large counts must not spill into neighboring cards; keep the exact
		# value available to accessibility clients.
		slot.asset_qty.clip_text = true
		slot.asset_qty.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		slot.accessibility_name = "%s: %d" % [item.display_name, int(items[item_id])]
		slot.asset_qty.accessibility_name = str(int(items[item_id]))
		slot.interaction_locked = true
		slot.slot_hovered.connect(_on_item_slot_hovered)
		slot.slot_unhovered.connect(_on_item_slot_unhovered)
	stock_summary.visible = storage_id == "city"
	_status_row.visible = stock_summary.visible
	_status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var content: VBoxContainer = context.get_parent() as VBoxContainer
	content.add_theme_constant_override("separation", 4)
	item_scroll.custom_minimum_size.y = ITEM_VIEW_HEIGHT
	if context.visible:
		item_scroll.custom_minimum_size.y = ITEM_VIEW_COMPACT_HEIGHT
	stock_summary.custom_minimum_size.x = 0.0
	stock_summary.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for index: int in range(stock_summary.get_child_count()):
		var entry: Control = stock_summary.get_child(index) as Control
		entry.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# The fixed grid viewport remains present for empty and short categories.
	# ScrollContainer clips overflow; changing stock never changes the frame.
	deposit_button.disabled = read_only or storage_id != "city" or not storage.has_method("get_depositable_items") or storage.call("get_depositable_items").is_empty()
	if is_instance_valid(haul_button):
		haul_button.disabled = read_only or not _has_access()

func _on_item_slot_hovered(item_id: String, _quantity: int, slot: ItemSlot) -> void:
	if not visible or not view.is_visible_in_tree():
		return
	_hovered_item_slot = slot
	if item_info_panel.display_item(item_id):
		item_info_panel.position_lower_center(get_viewport().get_visible_rect().end.y)

func _on_item_slot_unhovered(slot: ItemSlot) -> void:
	if _hovered_item_slot == slot:
		_clear_item_info()

func _clear_item_info() -> void:
	_hovered_item_slot = null
	if is_instance_valid(item_info_panel):
		item_info_panel.clear_item()

func _build_currency_summary() -> void:
	stock_summary = HBoxContainer.new()
	stock_summary.name = "StockSummary"
	stock_summary.add_theme_constant_override("separation", 12)
	stock_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var content: VBoxContainer = context.get_parent() as VBoxContainer
	_status_row = HBoxContainer.new()
	_status_row.name = "StatusRow"
	_status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_row.add_theme_constant_override("separation", 4)
	content.add_child(_status_row)
	content.move_child(_status_row, feedback.get_index())
	feedback.reparent(_status_row)
	feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stock_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stock_summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_row.add_child(stock_summary)
	for index: int in range(CURRENCY_ICONS.size()):
		var row := HBoxContainer.new()
		row.name = ["Copper", "Shekel", "Gold"][index]
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 2)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stock_summary.add_child(row)
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.texture = CURRENCY_ICONS[index]
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var amount := Label.new()
		amount.name = "Amount"
		amount.text = "0"
		amount.accessibility_name = "%s: 0, placeholder" % row.name
		amount.theme_type_variation = &"HudLabelShortcut"
		amount.custom_minimum_size.x = 6.0
		amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		amount.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		amount.clip_text = true
		amount.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		amount.add_theme_font_size_override("font_size", 6)
		amount.add_theme_color_override("font_color", Color.WHITE)
		amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(amount)
		_currency_amounts.append(amount)

func _get_available_items(location_id: String) -> Dictionary:
	if is_instance_valid(storage) and storage.has_method("get_available_items"):
		var result: Variant = storage.call("get_available_items")
		if result is Dictionary:
			return result
	var manager: Node = _get_transport_manager()
	if is_instance_valid(manager) and manager.has_method("available_items"):
		var result: Variant = manager.call("available_items", location_id)
		if result is Dictionary:
			return result
	return {}

func _get_storage_units() -> Dictionary:
	if not is_instance_valid(storage):
		return {}
	for property: Dictionary in storage.get_property_list():
		if str(property.get("name", "")) == "units":
			var value: Variant = storage.get("units")
			return value if value is Dictionary else {}
	return {}

func _refresh_food_summary() -> Dictionary:
	if not is_instance_valid(food_summary):
		return {}
	if storage_id != "city":
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
	if storage_id != "city":
		clothing_summary.text = "Citizens use Central Storage."
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

func _open_transfer(mode: String) -> void:
	if read_only or not visible or not view.visible or is_instance_valid(transfer_ui) or is_instance_valid(haul_ui) or storage_id != "city" or mode != "deposit":
		return
	if not _has_access():
		close()
		return
	_transfer_mode = mode
	_clear_item_info()
	$Root.hide()
	transfer_ui = preload("res://scenes/ui/item_transfer_ui/item_transfer_ui.tscn").instantiate()
	add_child(transfer_ui)
	transfer_ui.allowed_category = InventoryCategorySelector.CATEGORY_ALL
	var transfer_window: Control = transfer_ui.get_node("Root/Center/Window") as Control
	transfer_window.custom_minimum_size = Vector2(240, 156)
	transfer_ui.title_label.add_theme_font_size_override("font_size", 12)
	var title_margin: MarginContainer = transfer_ui.title_label.get_parent() as MarginContainer
	title_margin.add_theme_constant_override("margin_left", 0)
	title_margin.add_theme_constant_override("margin_right", 0)
	transfer_ui.grid_container.columns = 6
	transfer_ui.grid_container.add_theme_constant_override("h_separation", 4)
	transfer_ui.grid_container.add_theme_constant_override("v_separation", 2)
	transfer_ui.item_scroll.custom_minimum_size = Vector2(176, ITEM_VIEW_COMPACT_HEIGHT)
	transfer_ui.item_scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	transfer_ui.item_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	transfer_ui.item_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var transfer_scrollbar: VScrollBar = transfer_ui.item_scroll.get_v_scroll_bar()
	transfer_scrollbar.theme = ITEM_SCROLLBAR_THEME
	transfer_scrollbar.custom_minimum_size.x = ITEM_SCROLLBAR_WIDTH
	_configure_item_scrollbar(transfer_scrollbar)
	_cancel_transaction_feedback()
	feedback.reparent(transfer_window)
	_set_action_icon(transfer_ui.back_button, BACK_ICON)
	_set_action_icon(transfer_ui.confirm_button, DEPOSIT_ICON)
	transfer_ui.back_button.custom_minimum_size = Vector2(64, 18)
	transfer_ui.confirm_button.custom_minimum_size = Vector2(64, 18)
	var transfer_footer: HBoxContainer = transfer_ui.back_button.get_parent() as HBoxContainer
	transfer_footer.get_node("Spacer").hide()
	transfer_footer.alignment = BoxContainer.ALIGNMENT_CENTER
	transfer_footer.add_theme_constant_override("separation", 8)
	transfer_ui.transfer_confirmed.connect(_confirm_transfer.bind(transfer_ui))
	transfer_ui.transfer_back_requested.connect(_return_from_transfer.bind(transfer_ui))
	transfer_ui.transfer_cancelled.connect(_return_from_transfer.bind(transfer_ui))
	clear_button = _make_button("Clear", transfer_ui.back_button.get_parent(), 64.0)
	clear_button.get_parent().move_child(clear_button, transfer_ui.confirm_button.get_index())
	clear_button.pressed.connect(_clear_transfer.bind(transfer_ui))
	_refresh_transfer()

func _refresh_transfer(message: String = "") -> void:
	var items: Dictionary = {}
	for row: Dictionary in storage.get_depositable_items():
		items[str(row.item_id)] = int(row.quantity)
	transfer_ui.open_transfer("Deposit to City (no return)", items, "Deposit")
	if not message.is_empty():
		transfer_ui.refresh_items(items, message)

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
	if read_only or not visible or not is_instance_valid(transfer_ui) or transfer_ui != source:
		return
	if not _has_access():
		close()
		return
	var result: Dictionary = storage.deposit_items_from_inventory(items, true)
	_refresh_view()
	_refresh_transfer()
	var succeeded: bool = bool(result.get("ok", false))
	_show_transaction_feedback("Deposited." if succeeded else str(result.get("message", "")), not succeeded)

func _return_from_transfer(source: ItemTransferUI) -> void:
	# The quantity dialog releases its own pause before emitting.
	if _owns_pause:
		get_tree().paused = true
	if not visible or not is_instance_valid(transfer_ui) or transfer_ui != source:
		return
	_cancel_transaction_feedback()
	feedback.reparent(view)
	transfer_ui = null
	clear_button = null
	_transfer_mode = ""
	if not _has_access():
		close()
		return
	$Root.show()
	_refresh_view()

func _cancel_transaction_feedback() -> void:
	if _transaction_feedback_tween != null and _transaction_feedback_tween.is_valid():
		_transaction_feedback_tween.kill()
	_transaction_feedback_tween = null
	feedback.hide()

func _show_transaction_feedback(message: String, is_error: bool) -> void:
	_cancel_transaction_feedback()
	if message.is_empty():
		return
	var parent: Control = feedback.get_parent() as Control
	feedback.size = Vector2(maxf(1.0, parent.size.x - 32.0), 16.0)
	feedback.position = ((parent.size - feedback.size) * 0.5).round()
	if is_instance_valid(haul_ui) and parent == haul_ui.get_node("Center/Panel"):
		# Centered vertically would cover the quantity controls. Use the clear
		# gap between the route summary and actions without reserving layout space.
		var route: Control = haul_ui.get_node("Center/Panel/Margin/Content/Route") as Control
		var start_button: Control = haul_ui.get_node("Center/Panel/Margin/Content/Footer/Start") as Control
		var gap_start: float = route.get_global_rect().end.y - parent.global_position.y
		var gap_end: float = start_button.global_position.y - parent.global_position.y
		if gap_end - gap_start >= feedback.size.y:
			feedback.position.y = roundf((gap_start + gap_end - feedback.size.y) * 0.5)
	var origin: Vector2 = feedback.position
	var pages: Array[String] = _split_transaction_feedback(message)
	_set_transaction_feedback_page(pages[0])
	feedback.add_theme_color_override("font_color", Color(0.90, 0.38, 0.32) if is_error else Color(0.28, 0.68, 0.31))
	feedback.modulate = Color(1, 1, 1, 0)
	feedback.show()
	_transaction_feedback_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_transaction_feedback_tween.tween_property(feedback, "modulate:a", 1.0, 0.10)
	if is_error:
		for offset: float in [2.0, -2.0, 1.0, 0.0]:
			_transaction_feedback_tween.tween_property(feedback, "position:x", origin.x + offset, 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		_transaction_feedback_tween.tween_property(feedback, "position:y", origin.y - 3.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_transaction_feedback_tween.tween_property(feedback, "position:y", origin.y, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for index in range(pages.size()):
		if index > 0:
			_transaction_feedback_tween.tween_callback(_set_transaction_feedback_page.bind(pages[index]))
		_transaction_feedback_tween.tween_interval(1.5)
	_transaction_feedback_tween.tween_property(feedback, "modulate:a", 0.0, 0.20)
	_transaction_feedback_tween.tween_callback(feedback.hide)

func _split_transaction_feedback(message: String) -> Array[String]:
	var pages: Array[String] = []
	var remaining: String = message.strip_edges()
	var font: Font = feedback.get_theme_font("font")
	var width: float = maxf(feedback.size.x, 1.0)
	while not remaining.is_empty():
		var count: int = 0
		while count < remaining.length() and remaining[count] != "\n":
			if font.get_string_size(remaining.left(count + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, _transaction_feedback_font_size).x > width:
				break
			count += 1
		if count == remaining.length():
			pages.append(remaining)
			break
		if count < remaining.length() and remaining[count] != "\n" and remaining[count] != " ":
			var last_space: int = remaining.left(count).rfind(" ")
			if last_space > 0:
				count = last_space
			else:
				var next_space: int = remaining.find(" ", count)
				var next_line: int = remaining.find("\n", count)
				count = remaining.length()
				if next_space >= 0:
					count = mini(count, next_space)
				if next_line >= 0:
					count = mini(count, next_line)
		if count == 0:
			count = 1
		pages.append(remaining.left(count).strip_edges())
		remaining = remaining.substr(count).strip_edges()
	if pages.is_empty():
		pages.append("")
	return pages

func _set_transaction_feedback_page(page: String) -> void:
	var font: Font = feedback.get_theme_font("font")
	var font_size: int = _transaction_feedback_font_size
	while font_size > 1 and font.get_string_size(page, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > feedback.size.x:
		font_size -= 1
	feedback.add_theme_font_size_override("font_size", font_size)
	feedback.text = page

func _make_button(text: String, parent: Node, min_width: float = 36.0) -> Button:
	var button := Button.new()
	button.name = text + "Button"
	button.text = text
	button.custom_minimum_size = Vector2(min_width, 18)
	button.theme_type_variation = &"HudShortcutButton"
	button.add_theme_font_size_override("font_size", 6)
	parent.add_child(button)
	return button

func _set_action_icon(button: Button, texture: Texture2D) -> void:
	button.icon = texture
	button.expand_icon = false
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Keep the 16px artwork at native size inside the shared 18px action height.
	for style_name: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style: StyleBox = button.get_theme_stylebox(style_name).duplicate() as StyleBox
		style.content_margin_top = 1.0
		style.content_margin_bottom = 1.0
		button.add_theme_stylebox_override(style_name, style)
	button.custom_minimum_size = Vector2(button.custom_minimum_size.x, maxf(button.custom_minimum_size.y, 18.0))
