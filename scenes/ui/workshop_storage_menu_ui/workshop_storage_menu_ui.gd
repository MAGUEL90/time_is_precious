class_name WorkshopStorageMenuUI extends CanvasLayer

signal action_selected(action_id: int)
signal pay_lot_requested(lot_id: String, menu_ui: WorkshopStorageMenuUI)
signal pay_all_requested(menu_ui: WorkshopStorageMenuUI)
signal withdraw_items_requested(
	selected_items: Dictionary,
	menu_ui: WorkshopStorageMenuUI
)
signal closed()

const ITEM_SLOT_SCENE: PackedScene = preload(
	"res://scenes/ui/item_slot/item_slot.tscn"
)
const LOCK_ICON: Texture2D = preload(
	"res://assets/ui/ui_icon/lock_icon.png"
)
const GAMEPLAY_THEME: Theme = preload(
	"res://resources/ui_gameplay_theme/ui_gameplay_theme.tres"
)

@onready var capacity_label: Label = (
	$Root/Center/TextureWindow/Margin/MainVBox/CapacityLabel
)
@onready var free_grid: GridContainer = (
	$Root/Center/TextureWindow/Margin/MainVBox/Body/FreeColumn/FreeScroll/FreeGrid
)
@onready var held_grid: GridContainer = (
	$Root/Center/TextureWindow/Margin/MainVBox/Body/HeldColumn/HeldScroll/HeldGrid
)
@onready var pending_label: Label = (
	$Root/Center/TextureWindow/Margin/MainVBox/StatusBox/PendingLabel
)
@onready var feedback_label: Label = (
	$Root/Center/TextureWindow/Margin/MainVBox/StatusBox/FeedbackLabel
)
@onready var deposit_button: Button = (
	$Root/Center/TextureWindow/Margin/MainVBox/Footer/PrimaryAction/DepositButton
)
@onready var withdraw_button: Button = (
	$Root/Center/TextureWindow/Margin/MainVBox/Footer/PrimaryAction/WithdrawButton
)
@onready var clear_button: Button = (
	$Root/Center/TextureWindow/Margin/MainVBox/Footer/SecondaryAction/ClearButton
)
@onready var pay_all_button: Button = (
	$Root/Center/TextureWindow/Margin/MainVBox/Footer/SecondaryAction/PayAllButton
)
@onready var back_button: Button = (
	$Root/Center/TextureWindow/Margin/MainVBox/Footer/BackButton
)

enum Action {DEPOSIT_ITEMS, BACK}

var storage_state: Dictionary = {}
var selected_lot_id: String = ""
var confirming_pay_all: bool = false
var active_fee_popup: WorkshopFeeConfirmUI = null
var selected_free_items: Dictionary[String, int] = {}
var free_slots_by_item_id: Dictionary = {}
var held_slots: Array[ItemSlot] = []
var pay_all_available: bool = false

func _ready() -> void:
	visible = false
	deposit_button.pressed.connect(_on_deposit_button_pressed)
	withdraw_button.pressed.connect(_on_withdraw_button_pressed)
	clear_button.pressed.connect(_clear_withdraw_selection)
	pay_all_button.pressed.connect(_on_pay_all_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)
	$Root/Center/TextureWindow/CloseButton.pressed.connect(_on_back_button_pressed)
	_refresh_withdraw_controls()

func open_menu(next_storage_state: Dictionary) -> void:
	get_tree().paused = true
	visible = true
	refresh_storage(next_storage_state)

func refresh_storage(next_storage_state: Dictionary) -> void:
	storage_state = next_storage_state.duplicate(true)
	selected_free_items.clear()
	free_slots_by_item_id.clear()
	held_slots.clear()
	_rebuild_free_stock()
	_rebuild_held_output()
	_refresh_status()
	_refresh_withdraw_controls()

func show_payment_result(
	success: bool,
	message: String,
	next_storage_state: Dictionary
) -> void:
	refresh_storage(next_storage_state)
	feedback_label.text = message
	feedback_label.remove_theme_color_override("font_color")
	if not success:
		feedback_label.add_theme_color_override(
			"font_color",
			Color(1.0, 0.55, 0.45, 1.0)
		)

func _clear_grid(grid: GridContainer) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()

func _rebuild_free_stock() -> void:
	_clear_grid(free_grid)
	var free_items: Dictionary = storage_state.get("free_items", {})
	for item_id_value in free_items.keys():
		var item_id: String = str(item_id_value)
		var quantity: int = int(free_items[item_id_value])
		var item_data: ItemData = ItemDatabase.get_item_data(item_id)
		if item_data == null or quantity <= 0:
			continue

		var slot: ItemSlot = ITEM_SLOT_SCENE.instantiate() as ItemSlot
		if slot == null:
			continue
		free_grid.add_child(slot)
		_apply_workshop_slot_style(slot, true)
		slot.set_item(item_id, quantity, item_data.icon)
		slot.set_right_click_action_enabled(true)
		slot.slot_clicked.connect(_on_free_slot_clicked)
		slot.slot_deposit_requested.connect(
			_on_free_slot_decrease_requested
		)
		free_slots_by_item_id[item_id] = slot

func _rebuild_held_output() -> void:
	_clear_grid(held_grid)
	var held_lots: Array = storage_state.get("held_lots", [])
	for lot_value in held_lots:
		var lot: Dictionary = lot_value
		var lot_id: String = str(lot.get("lot_id", ""))
		var lot_items: Dictionary = lot.get("items", {})
		for item_id_value in lot_items.keys():
			var item_id: String = str(item_id_value)
			var quantity: int = int(lot_items[item_id_value])
			var item_data: ItemData = ItemDatabase.get_item_data(item_id)
			if item_data == null or quantity <= 0 or lot_id.is_empty():
				continue

			var slot: ItemSlot = ITEM_SLOT_SCENE.instantiate() as ItemSlot
			if slot == null:
				continue
			held_grid.add_child(slot)
			_apply_workshop_slot_style(slot, false)
			slot.set_item(item_id, quantity, item_data.icon)
			held_slots.append(slot)
			slot.slot_clicked.connect(
				_on_held_slot_clicked.bind(lot_id)
			)
			_add_lock_badge(slot)

func _apply_workshop_slot_style(
	slot: ItemSlot,
	persistent_selection: bool
) -> void:
	slot.theme = GAMEPLAY_THEME
	slot.theme_type_variation = &"WorkshopSquareButton24"
	slot.toggle_mode = persistent_selection
	var default_icon: CanvasItem = slot.get_node_or_null("DefaultIcon") as CanvasItem
	if default_icon != null:
		default_icon.hide()

func _add_lock_badge(slot: Control) -> void:
	var lock_badge := TextureRect.new()
	lock_badge.texture = LOCK_ICON
	lock_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lock_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lock_badge.anchor_left = 1.0
	lock_badge.anchor_right = 1.0
	lock_badge.offset_left = -10.0
	lock_badge.offset_top = 1.0
	lock_badge.offset_right = -1.0
	lock_badge.offset_bottom = 10.0
	slot.add_child(lock_badge)

func _refresh_status() -> void:
	var used_capacity: float = float(storage_state.get("used_capacity", 0.0))
	var max_capacity: float = float(storage_state.get("max_capacity", 0.0))
	var pending_count: int = int(storage_state.get("pending_count", 0))
	var free_items: Dictionary = storage_state.get("free_items", {})
	var held_lots: Array = storage_state.get("held_lots", [])
	var held_fee_totals: Dictionary = storage_state.get("held_fee_totals", {})
	var active_processes: Array = storage_state.get(
		"active_processes",
		[]
	)

	capacity_label.text = "Load %.0f / %.0f" % [used_capacity, max_capacity]
	pending_label.text = (
		"Pending Delivery: %d - free storage space" % pending_count
		if pending_count > 0
		else "Pending Delivery: None"
	)
	pay_all_available = not held_lots.is_empty() and not held_fee_totals.is_empty()
	pay_all_button.disabled = not pay_all_available
	feedback_label.text = (
		_format_active_processes(active_processes)
		if not active_processes.is_empty()
		else "Click Held Output to pay its fee."
	)

func _format_active_processes(active_processes: Array) -> String:
	var parts: PackedStringArray = []
	for process_value in active_processes:
		var process_entry: Dictionary = process_value
		var input_text: String = _format_items(
			process_entry.get("inputs", {})
		)
		var output_text: String = _format_items(
			process_entry.get("outputs", {})
		)
		parts.append("%s into %s" % [input_text, output_text])

	return "In Process: %s" % "; ".join(parts)

func _on_held_slot_clicked(
	_item_id: String,
	_quantity: int,
	_slot_ref: ItemSlot,
	lot_id: String
) -> void:
	if is_instance_valid(active_fee_popup):
		return

	var lot: Dictionary = _find_lot(lot_id)
	if lot.is_empty():
		return

	selected_lot_id = lot_id
	confirming_pay_all = false
	var popup_scene: PackedScene = preload(
		"res://scenes/ui/workshop_fee_confirm_ui/workshop_fee_confirm_ui.tscn"
	)
	active_fee_popup = popup_scene.instantiate() as WorkshopFeeConfirmUI
	if active_fee_popup == null:
		return

	get_tree().current_scene.add_child(active_fee_popup)
	active_fee_popup.payment_selected.connect(_on_lot_payment_selected)
	active_fee_popup.cancelled.connect(_on_lot_payment_cancelled)
	active_fee_popup.open_output_fee(
		_format_items(lot.get("items", {})),
		_format_fee_totals(lot.get("fee_totals", {}))
	)

func _on_free_slot_clicked(
	item_id: String,
	available_quantity: int,
	slot_ref: ItemSlot
) -> void:
	var item_data: ItemData = ItemDatabase.get_item_data(item_id)
	if item_data == null or available_quantity <= 0:
		return

	var max_withdrawable: int = _get_max_withdrawable_quantity(
		item_id,
		item_data,
		available_quantity
	)
	if max_withdrawable <= 0:
		feedback_label.text = "Inventory has no room for %s." % (
			item_data.display_name
		)
		feedback_label.add_theme_color_override(
			"font_color",
			Color(1.0, 0.55, 0.45, 1.0)
		)
		return

	feedback_label.remove_theme_color_override("font_color")
	var current_quantity: int = int(
		selected_free_items.get(item_id, 0)
	)
	var next_quantity: int = mini(
		current_quantity + _get_withdraw_step(),
		max_withdrawable
	)
	if next_quantity <= current_quantity:
		return

	selected_free_items[item_id] = next_quantity
	slot_ref.set_selected_quantity(next_quantity)
	slot_ref.set_selected(true)
	_refresh_withdraw_controls()

func _on_free_slot_decrease_requested(
	item_id: String,
	_available_quantity: int,
	slot_ref: ItemSlot
) -> void:
	var current_quantity: int = int(
		selected_free_items.get(item_id, 0)
	)
	if current_quantity <= 0:
		return

	var next_quantity: int = maxi(
		current_quantity - _get_withdraw_step(),
		0
	)
	if next_quantity <= 0:
		selected_free_items.erase(item_id)
	else:
		selected_free_items[item_id] = next_quantity

	slot_ref.set_selected_quantity(next_quantity)
	slot_ref.set_selected(next_quantity > 0)
	_refresh_withdraw_controls()

func _get_max_withdrawable_quantity(
	item_id: String,
	item_data: ItemData,
	available_quantity: int
) -> int:
	if item_data.weight <= 0.0:
		return available_quantity

	var other_selection_weight: float = 0.0
	for selected_item_id in selected_free_items.keys():
		if str(selected_item_id) == item_id:
			continue
		other_selection_weight += Inventory.get_item_total_weight(
			str(selected_item_id),
			int(selected_free_items[selected_item_id])
		)

	var capacity_quantity: int = floori(
		maxf(
			Inventory.get_remaining_capacity()
			- other_selection_weight,
			0.0
		)
		/ item_data.weight
	)
	return mini(available_quantity, capacity_quantity)

func _get_withdraw_step() -> int:
	if Input.is_key_pressed(KEY_CTRL):
		return 50
	if Input.is_key_pressed(KEY_SHIFT):
		return 10
	return 1

func _refresh_withdraw_controls() -> void:
	var has_selection: bool = not selected_free_items.is_empty()
	deposit_button.visible = not has_selection
	pay_all_button.visible = not has_selection
	withdraw_button.visible = has_selection
	clear_button.visible = has_selection
	withdraw_button.disabled = not has_selection
	pay_all_button.disabled = not pay_all_available

	for held_slot in held_slots:
		if is_instance_valid(held_slot):
			held_slot.set_interaction_locked(has_selection)

	if has_selection:
		feedback_label.remove_theme_color_override("font_color")
		feedback_label.text = ""

func _clear_withdraw_selection() -> void:
	for item_id in free_slots_by_item_id.keys():
		var slot: ItemSlot = (
			free_slots_by_item_id[item_id] as ItemSlot
		)
		if is_instance_valid(slot):
			slot.set_selected_quantity(0)
			slot.set_selected(false)

	selected_free_items.clear()
	_refresh_status()
	_refresh_withdraw_controls()

func _on_withdraw_button_pressed() -> void:
	if selected_free_items.is_empty():
		return
	withdraw_items_requested.emit(
		selected_free_items.duplicate(true),
		self
	)

func _find_lot(lot_id: String) -> Dictionary:
	var held_lots: Array = storage_state.get("held_lots", [])
	for lot_value in held_lots:
		var lot: Dictionary = lot_value
		if str(lot.get("lot_id", "")) == lot_id:
			return lot

	return {}

func _format_items(lot_items: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item_id_value in lot_items.keys():
		var item_id: String = str(item_id_value)
		var display_name: String = item_id.replace("_", " ").capitalize()
		var item_data: ItemData = ItemDatabase.get_item_data(item_id)
		if item_data != null:
			display_name = item_data.display_name
		parts.append("%s x%d" % [display_name, int(lot_items[item_id_value])])

	return ", ".join(parts)

func _format_fee_totals(fee_totals: Dictionary) -> String:
	if fee_totals.is_empty():
		return "-"

	var parts: PackedStringArray = []
	for currency_id_value in fee_totals.keys():
		var currency_id: String = str(currency_id_value)
		var display_name: String = currency_id.replace("_", " ").capitalize()
		var currency_data: ItemData = ItemDatabase.get_item_data(currency_id)
		if currency_data != null:
			display_name = currency_data.display_name
		parts.append(
			"%d %s" % [int(fee_totals[currency_id_value]), display_name]
		)

	return ", ".join(parts)

func _selected_action(action_id: int) -> void:
	get_tree().paused = false
	hide()
	action_selected.emit(action_id)
	queue_free()

func _on_deposit_button_pressed() -> void:
	_selected_action(Action.DEPOSIT_ITEMS)

func _on_pay_all_button_pressed() -> void:
	if is_instance_valid(active_fee_popup):
		return

	var held_fee_totals: Dictionary = storage_state.get(
		"held_fee_totals",
		{}
	)
	if held_fee_totals.is_empty():
		return

	confirming_pay_all = true
	selected_lot_id = ""
	_open_pay_all_popup(_format_fee_totals(held_fee_totals))

func _on_back_button_pressed() -> void:
	get_tree().paused = false
	hide()
	closed.emit()
	queue_free()

func _on_lot_payment_selected(will_pay_fee: bool) -> void:
	active_fee_popup = null
	if will_pay_fee and confirming_pay_all:
		pay_all_requested.emit(self)
	elif will_pay_fee and not selected_lot_id.is_empty():
		pay_lot_requested.emit(selected_lot_id, self)
	confirming_pay_all = false
	selected_lot_id = ""

func _on_lot_payment_cancelled() -> void:
	active_fee_popup = null
	confirming_pay_all = false
	selected_lot_id = ""

func _open_pay_all_popup(fee_summary: String) -> void:
	var popup_scene: PackedScene = preload(
		"res://scenes/ui/workshop_fee_confirm_ui/workshop_fee_confirm_ui.tscn"
	)
	active_fee_popup = popup_scene.instantiate() as WorkshopFeeConfirmUI
	if active_fee_popup == null:
		confirming_pay_all = false
		return

	get_tree().current_scene.add_child(active_fee_popup)
	active_fee_popup.payment_selected.connect(_on_lot_payment_selected)
	active_fee_popup.cancelled.connect(_on_lot_payment_cancelled)
	active_fee_popup.open_all_output_fees(fee_summary)
