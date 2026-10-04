class_name TravelingMerchantUI extends CanvasLayer

signal closed
signal trade_requested(item_id: String, quantity: int, buying: bool)

const GAMEPLAY_THEME: Theme = preload(
	"res://resources/ui_gameplay_theme/ui_gameplay_theme.tres"
)
const DEFAULT_ITEM_ICON: Texture2D = preload(
	"res://assets/ui/default_icon.png"
)
const PIXEL_FONT: Font = preload("res://assets/font/pixel_rpg.ttf")
const SHEKEL_ITEM_ID: String = "shekel"
const LIGHT_TEXT_COLOR: Color = Color(1.0, 0.90, 0.67, 1.0)
const DISABLED_TEXT_COLOR: Color = Color(0.76, 0.69, 0.56, 1.0)

@onready var player_shekel_label: Label = $Root/Center/TextureWindow/Margin/MainVBox/WalletRow/PlayerWallet/PlayerShekelLabel
@onready var merchant_budget_label: Label = $Root/Center/TextureWindow/Margin/MainVBox/WalletRow/TraderWallet/MerchantBudgetLabel
@onready var status_label: Label = $Root/Center/TextureWindow/Margin/MainVBox/StatusLabel
@onready var catalog_list: VBoxContainer = $Root/Center/TextureWindow/Margin/MainVBox/Body/CatalogColumn/CatalogScroll/CatalogList
@onready var buy_tab: Button = $Root/Center/TextureWindow/Margin/MainVBox/ModeRow/BuyTab
@onready var sell_tab: Button = $Root/Center/TextureWindow/Margin/MainVBox/ModeRow/SellTab
@onready var selected_icon: TextureRect = $Root/Center/TextureWindow/Margin/MainVBox/Body/TradePanel/TradeMargin/TradeVBox/SelectedRow/SelectedIcon
@onready var selected_name_label: Label = $Root/Center/TextureWindow/Margin/MainVBox/Body/TradePanel/TradeMargin/TradeVBox/SelectedRow/SelectedNameLabel
@onready var unit_price_label: Label = $Root/Center/TextureWindow/Margin/MainVBox/Body/TradePanel/TradeMargin/TradeVBox/UnitPriceRow/UnitPriceLabel
@onready var unit_price_icon: TextureRect = $Root/Center/TextureWindow/Margin/MainVBox/Body/TradePanel/TradeMargin/TradeVBox/UnitPriceRow/UnitPriceIcon
@onready var quantity_label: Label = $Root/Center/TextureWindow/Margin/MainVBox/Body/TradePanel/TradeMargin/TradeVBox/QuantityRow/QuantityLabel
@onready var quantity_spin_box: SpinBox = $Root/Center/TextureWindow/Margin/MainVBox/Body/TradePanel/TradeMargin/TradeVBox/QuantityRow/QuantitySpinBox
@onready var max_button: Button = $Root/Center/TextureWindow/Margin/MainVBox/Body/TradePanel/TradeMargin/TradeVBox/QuantityRow/MaxButton
@onready var total_label: Label = $Root/Center/TextureWindow/Margin/MainVBox/Body/TradePanel/TradeMargin/TradeVBox/TotalRow/TotalLabel
@onready var total_icon: TextureRect = $Root/Center/TextureWindow/Margin/MainVBox/Body/TradePanel/TradeMargin/TradeVBox/TotalRow/TotalIcon
@onready var quote_message_label: Label = $Root/Center/TextureWindow/Margin/MainVBox/Body/TradePanel/TradeMargin/TradeVBox/QuoteMessageLabel
@onready var confirm_button: Button = $Root/Center/TextureWindow/Margin/MainVBox/Body/TradePanel/TradeMargin/TradeVBox/ConfirmButton
@onready var close_button: BaseButton = $Root/Center/TextureWindow/Margin/MainVBox/HeaderRow/CloseButton

var merchant_state: Node
var selected_item_id: String = ""
var buying: bool = true
var _catalog_rows: Array[Dictionary] = []
var _result_message: String = ""
var _updating_quantity: bool = false

func _ready() -> void:
	visible = false
	buy_tab.toggle_mode = true
	sell_tab.toggle_mode = true
	buy_tab.pressed.connect(_on_buy_tab_pressed)
	sell_tab.pressed.connect(_on_sell_tab_pressed)
	quantity_spin_box.value_changed.connect(_on_quantity_changed)
	confirm_button.pressed.connect(_on_confirm_pressed)
	max_button.pressed.connect(_on_max_pressed)
	close_button.pressed.connect(close_menu)
	var quantity_line_edit: LineEdit = quantity_spin_box.get_line_edit()
	quantity_line_edit.add_theme_font_override("font", PIXEL_FONT)
	quantity_line_edit.add_theme_font_size_override("font_size", 6)
	_set_quantity_arrows()
	quantity_line_edit.add_theme_stylebox_override("normal", GAMEPLAY_THEME.get_stylebox("normal", "HudShortcutButton"))
	quantity_line_edit.add_theme_stylebox_override("read_only", GAMEPLAY_THEME.get_stylebox("disabled", "HudShortcutButton"))
	quantity_line_edit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	quantity_line_edit.add_theme_color_override("font_color", LIGHT_TEXT_COLOR)
	quantity_line_edit.add_theme_color_override("caret_color", LIGHT_TEXT_COLOR)
	quote_message_label.add_theme_color_override("font_color", LIGHT_TEXT_COLOR)
	confirm_button.add_theme_color_override("font_color", LIGHT_TEXT_COLOR)
	confirm_button.add_theme_color_override("font_hover_color", LIGHT_TEXT_COLOR)
	confirm_button.add_theme_color_override("font_pressed_color", LIGHT_TEXT_COLOR)
	confirm_button.add_theme_color_override("font_focus_color", LIGHT_TEXT_COLOR)
	confirm_button.add_theme_color_override("font_disabled_color", DISABLED_TEXT_COLOR)
	_update_mode_tabs()

func _exit_tree() -> void:
	_disconnect_inventory()
	_unbind_state()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_menu()
		get_viewport().set_input_as_handled()
		return
	for action_name: String in [
		"interact",
		"open_inventory",
		"open_work_progress",
		"open_worker_hub",
		"show_player_status"
	]:
		if event.is_action_pressed(action_name):
			get_viewport().set_input_as_handled()
			return

func open_menu(state: Node) -> void:
	if not is_instance_valid(state):
		return

	if merchant_state != state:
		_unbind_state()
		merchant_state = state

	if merchant_state.has_signal("changed"):
		var changed_callable: Callable = Callable(self, "_on_state_changed")
		if not merchant_state.is_connected("changed", changed_callable):
			merchant_state.connect("changed", changed_callable)

	_connect_inventory()
	visible = true
	_result_message = ""
	_refresh_view()

func close_menu() -> void:
	if not visible:
		return

	visible = false
	_disconnect_inventory()
	_unbind_state()
	merchant_state = null
	closed.emit()
	queue_free()

func show_result(message: String) -> void:
	if message.begins_with("Bought ") or message.begins_with("Sold "):
		_result_message = message.get_slice(" for ", 0).trim_suffix(".") + "."
	else:
		_result_message = _present_result_message(message)
	_refresh_quote()

func _present_result_message(message: String) -> String:
	if message == "Not enough Shekel.":
		return "Not enough coins."
	if message == "The merchant does not have enough Shekel.":
		var row: Dictionary = _get_selected_row()
		var price: int = int(row.get("sell_price", 0))
		@warning_ignore("integer_division")
		var affordable: int = merchant_state.get_budget() / maxi(price, 1)
		return "Merchant can afford only %d." % affordable
	if message == "Merchant request limit reached.":
		var remaining: int = int(_get_selected_row().get("demand", 0))
		return "Request fulfilled." if remaining == 0 else "Merchant needs only %d more." % remaining
	if message == "Not enough merchant stock.":
		return "Only %d in stock." % int(_get_selected_row().get("stock", 0))
	if message == "Not enough inventory capacity for this trade.":
		return "Not enough bag space."
	if message == "Not enough items in your inventory.":
		return "Not enough items."
	return message

func _connect_inventory() -> void:
	if Inventory == null or not Inventory.has_signal("items_changed"):
		return
	var items_callable: Callable = Callable(self, "_on_inventory_changed")
	if not Inventory.is_connected("items_changed", items_callable):
		Inventory.items_changed.connect(items_callable)

func _disconnect_inventory() -> void:
	if Inventory == null or not Inventory.has_signal("items_changed"):
		return
	var items_callable: Callable = Callable(self, "_on_inventory_changed")
	if Inventory.is_connected("items_changed", items_callable):
		Inventory.items_changed.disconnect(items_callable)

func _unbind_state() -> void:
	if not is_instance_valid(merchant_state):
		return
	if not merchant_state.has_signal("changed"):
		return
	var changed_callable: Callable = Callable(self, "_on_state_changed")
	if merchant_state.is_connected("changed", changed_callable):
		merchant_state.disconnect("changed", changed_callable)

func _on_state_changed() -> void:
	_refresh_view()

func _on_inventory_changed() -> void:
	_refresh_view()

func _refresh_view() -> void:
	if not visible:
		return

	player_shekel_label.text = str(int(Inventory.items.get(SHEKEL_ITEM_ID, 0)))
	var budget: int = 0
	var status_text: String = ""
	var next_catalog_rows: Array[Dictionary] = []

	if is_instance_valid(merchant_state):
		if merchant_state.has_method("get_budget"):
			budget = int(merchant_state.call("get_budget"))
		if merchant_state.has_method("get_status_text"):
			status_text = str(merchant_state.call("get_status_text"))
		if merchant_state.has_method("get_catalog"):
			var catalog_value: Variant = merchant_state.call("get_catalog")
			if catalog_value is Array:
				for row_value in catalog_value:
					if row_value is Dictionary:
						next_catalog_rows.append(row_value.duplicate())

	merchant_budget_label.text = str(budget)
	status_label.text = status_text if not status_text.is_empty() else "Merchant is in town."
	var catalog_changed: bool = _catalog_rows != next_catalog_rows
	_catalog_rows = next_catalog_rows
	if not _contains_selected_item():
		selected_item_id = ""
		for row: Dictionary in _catalog_rows:
			if _row_visible(row):
				selected_item_id = str(row.get("item_id", ""))
				break

	if catalog_changed:
		_render_catalog()
	_refresh_selected_item()
	_refresh_quote()

func _row_visible(row: Dictionary) -> bool:
	return int(row.get("buy_price" if buying else "sell_price", 0)) > 0

func _contains_selected_item() -> bool:
	if selected_item_id.is_empty():
		return false
	for row in _catalog_rows:
		if _row_visible(row) and str(row.get("item_id", "")) == selected_item_id:
			return true
	return false

func _render_catalog() -> void:
	for child in catalog_list.get_children():
		catalog_list.remove_child(child)
		child.queue_free()

	var visible_rows: Array[Dictionary] = []
	for row: Dictionary in _catalog_rows:
		if _row_visible(row):
			visible_rows.append(row)
	if visible_rows.is_empty():
		var empty_label := _make_label("No goods offered" if buying else "No requests this visit", 6)
		empty_label.custom_minimum_size = Vector2(0, 16)
		catalog_list.add_child(empty_label)
		return

	for row in visible_rows:
		var item_id: String = str(row.get("item_id", ""))
		if item_id.is_empty():
			continue
		var item_data: ItemData = ItemDatabase.get_item_data(item_id)
		var item_name: String = item_id.replace("_", " ").capitalize()
		var item_icon: Texture2D = DEFAULT_ITEM_ICON
		if item_data != null:
			item_name = item_data.display_name
			if item_data.icon != null:
				item_icon = item_data.icon

		var row_button := Button.new()
		row_button.custom_minimum_size = Vector2(188, 20)
		row_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_button.theme = GAMEPLAY_THEME
		row_button.theme_type_variation = &"HudShortcutButton"
		row_button.set_meta("merchant_item_id", item_id)
		row_button.pressed.connect(_on_catalog_item_pressed.bind(item_id))
		var empty_style := StyleBoxEmpty.new()
		for style_name: String in ["normal", "disabled"]:
			row_button.add_theme_stylebox_override(style_name, empty_style)
		row_button.focus_mode = Control.FOCUS_NONE
		catalog_list.add_child(row_button)

		var row_box := HBoxContainer.new()
		row_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row_box.offset_left = 3.0
		row_box.offset_top = 0.0
		row_box.offset_right = -3.0
		row_box.offset_bottom = 0.0
		row_box.add_theme_constant_override("separation", 3)
		row_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_button.add_child(row_box)

		var icon_center := CenterContainer.new()
		icon_center.custom_minimum_size = Vector2(20, 20)
		icon_center.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_box.add_child(icon_center)

		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(16, 16)
		icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_rect.texture = item_icon
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_center.add_child(icon_rect)

		var name_label := _make_label(item_name, 6)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row_box.add_child(name_label)

		var available_key: String = "stock" if buying else "demand"
		var stock_label := _make_label(
			("x%d" if buying else "Need %d") % int(row.get(available_key, 0)),
			6
		)
		stock_label.custom_minimum_size = Vector2(34, 0)
		stock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row_box.add_child(stock_label)


func _make_label(label_text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = label_text
	label.theme = GAMEPLAY_THEME
	label.theme_type_variation = &"HudLabelShortcut"
	label.add_theme_font_size_override("font_size", font_size)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _on_catalog_item_pressed(item_id: String) -> void:
	selected_item_id = item_id
	_result_message = ""
	_refresh_selected_item()
	_refresh_quote()


func _refresh_selected_item() -> void:
	var row: Dictionary = _get_selected_row()
	if row.is_empty():
		selected_name_label.text = "Select an item"
		selected_icon.texture = DEFAULT_ITEM_ICON
		unit_price_label.text = ""
		unit_price_icon.hide()
		quantity_spin_box.editable = false
		return

	var item_data: ItemData = ItemDatabase.get_item_data(selected_item_id)
	selected_name_label.text = (
		item_data.display_name
		if item_data != null
		else selected_item_id.replace("_", " ").capitalize()
	)
	selected_icon.texture = (
		item_data.icon
		if item_data != null and item_data.icon != null
		else DEFAULT_ITEM_ICON
	)
	selected_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var unit_price: int = int(row.get("buy_price" if buying else "sell_price", 0))
	unit_price_label.text = str(unit_price) if unit_price > 0 else "—"
	unit_price_icon.visible = unit_price > 0
	quantity_label.text = "Quantity" if buying else "Have %d" % int(row.get("player_qty", 0))
	quantity_label.clip_text = true
	quantity_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	quantity_label.tooltip_text = quantity_label.text
	quantity_spin_box.tooltip_text = "Quantity to buy" if buying else "Quantity to sell"
	quantity_spin_box.editable = true
	_update_quantity_limit(row)

func _update_quantity_limit(_row: Dictionary) -> void:
	# Preserve the player's choice even when stock or affordability changes.
	_updating_quantity = true
	quantity_spin_box.min_value = 1
	quantity_spin_box.max_value = 999
	quantity_spin_box.step = 1
	_updating_quantity = false

func _maximum_quantity() -> int:
	if not is_instance_valid(merchant_state):
		return 0
	var row: Dictionary = _get_selected_row()
	var available: int = int(row.get("stock" if buying else "player_qty", 0))
	var price: int = int(row.get("buy_price" if buying else "sell_price", 0))
	if not buying:
		available = mini(available, int(row.get("demand", 0)))
	if price <= 0:
		return 0
	var wallet: int = int(Inventory.items.get(SHEKEL_ITEM_ID, 0)) if buying else int(merchant_state.get_budget())
	@warning_ignore("integer_division")
	var affordable: int = wallet / price
	var upper: int = mini(999, mini(available, affordable))
	# Bounded by the input control; authoritative quotes enforce final inventory capacity.
	for quantity: int in range(upper, 0, -1):
		if merchant_state.quote(selected_item_id, quantity, buying).get("ok", false):
			return quantity
	return 0

func _on_max_pressed() -> void:
	var maximum: int = _maximum_quantity()
	if maximum > 0:
		_result_message = ""
		quantity_spin_box.value = maximum
		_refresh_quote()

func _get_selected_row() -> Dictionary:
	for row in _catalog_rows:
		if _row_visible(row) and str(row.get("item_id", "")) == selected_item_id:
			return row
	return {}

func _on_buy_tab_pressed() -> void:
	_set_buying(true)

func _on_sell_tab_pressed() -> void:
	_set_buying(false)

func _set_buying(next_buying: bool) -> void:
	if buying == next_buying:
		_update_mode_tabs()
		return
	buying = next_buying
	_result_message = ""
	_update_mode_tabs()
	_render_catalog()
	_refresh_view()

func _update_mode_tabs() -> void:
	buy_tab.button_pressed = buying
	sell_tab.button_pressed = not buying

func _on_quantity_changed(_value: float) -> void:
	if _updating_quantity:
		return
	_result_message = ""
	_refresh_quote()

func _current_quote() -> Dictionary:
	if not is_instance_valid(merchant_state) or not merchant_state.has_method("quote"):
		return {"ok": false, "message": "Merchant is unavailable."}
	if selected_item_id.is_empty():
		return {"ok": false, "message": "Select an item."}
	return merchant_state.call(
		"quote",
		selected_item_id,
		int(quantity_spin_box.value),
		buying
	)

func _refresh_quote() -> void:
	if not visible:
		return
	var quote: Dictionary = _current_quote()
	var quote_ok: bool = bool(quote.get("ok", false))
	var reason: String = _present_result_message(str(quote.get("message", "")))
	var price: int = int(_get_selected_row().get("buy_price" if buying else "sell_price", 0))
	var quantity: int = int(quantity_spin_box.value)
	@warning_ignore("integer_division")
	var total_safe: bool = price > 0 and price <= 9223372036854775807 / maxi(quantity, 1)
	total_label.text = str(price * quantity) if total_safe else "—"
	total_icon.visible = total_safe
	quote_message_label.text = _result_message if not _result_message.is_empty() else ("" if quote_ok else reason)
	quote_message_label.add_theme_color_override("font_color", LIGHT_TEXT_COLOR if quote_ok else Color(1.0, 0.79, 0.48))
	max_button.disabled = _maximum_quantity() == 0
	confirm_button.text = "Buy" if buying else "Sell"
	confirm_button.disabled = not quote_ok

func _on_confirm_pressed() -> void:
	var quote: Dictionary = _current_quote()
	if not bool(quote.get("ok", false)):
		_refresh_quote()
		return
	_result_message = ""
	_refresh_quote()
	trade_requested.emit(selected_item_id, int(quantity_spin_box.value), buying)

func _set_quantity_arrows() -> void:
	# Keep native SpinBox input/stepping; rotate the game's existing arrow art.
	var up: Image = preload("res://assets/ui/ui_icon/left_arrow_icon.png").get_image()
	var down: Image = preload("res://assets/ui/ui_icon/right_arrow_icon.png").get_image()
	up.rotate_90(CLOCKWISE)
	down.rotate_90(CLOCKWISE)
	var arrows := Image.create(up.get_width(), up.get_height() + down.get_height(), false, Image.FORMAT_RGBA8)
	arrows.blit_rect(up, Rect2i(Vector2i.ZERO, up.get_size()), Vector2i.ZERO)
	arrows.blit_rect(down, Rect2i(Vector2i.ZERO, down.get_size()), Vector2i(0, up.get_height()))
	quantity_spin_box.add_theme_icon_override("updown", ImageTexture.create_from_image(arrows))
	quantity_spin_box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
