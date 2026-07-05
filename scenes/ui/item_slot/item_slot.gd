class_name ItemSlot extends Button

signal slot_clicked(item_id: String, quantity: int, slot_ref: ItemSlot)
signal slot_deposit_requested(item_id: String, quantity: int, node: Node)
signal slot_hovered(item_id: String, quantity: int, slot_ref: ItemSlot)
signal slot_unhovered(slot_ref: ItemSlot)
signal slot_drag_started(data: Dictionary)

@onready var target_lock_icon: TextureRect = $TargetLockIcon
@onready var asset_icon: TextureRect = $MarginContainer/AssetIcon
@onready var asset_qty: Label = $MarginContainer/AssetQty
@onready var selected_qty: Label = $SelectedQty

var _item_id: String
var _quantity: int
var is_selected: bool = false
var is_mouse_over: bool = false
var hover_locked: bool = false
var interaction_locked: bool = false

# Setup / Item data

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func set_item(item_id: String, quantity: int, item_icon: Texture2D) -> void:
	asset_icon.texture = item_icon
	asset_qty.text = str(max(quantity, 0))

	_item_id = item_id
	_quantity = quantity

# Slot callbacks

func _on_pressed() -> void:
	if interaction_locked:
		return

	slot_clicked.emit(_item_id, _quantity, self)

func _get_drag_data(at_position: Vector2) -> Variant:
	if interaction_locked:
		return null

	if _item_id.is_empty() or _quantity <= 0:
		return null

	set_drag_source_active(true)

	var preview: TextureRect = TextureRect.new()
	preview.texture = asset_icon.texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = asset_icon.size
	preview.size = asset_icon.size
	preview.pivot_offset = preview.size * 0.5
	preview.modulate = Color(1.0, 1.0, 1.0, 0.8)
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.scale = Vector2(2.0, 2.0)

	set_drag_preview(preview)

	var drag_data: Dictionary = {
		"source": "inventory_slot",
		"item_id": _item_id,
		"quantity": _quantity,
		"slot_ref": self
	}

	slot_drag_started.emit(drag_data)

	return drag_data

# Selection state

func set_selected_quantity(quantity: int) -> void:
	selected_qty.visible = quantity > 0
	selected_qty.text = str(quantity)

# Hover state

func _on_mouse_entered() -> void:
	is_mouse_over = true
	_refresh_target_lock_visibility()
	slot_hovered.emit(_item_id, _quantity, self)

func _on_mouse_exited() -> void:
	is_mouse_over = false
	_refresh_target_lock_visibility()
	slot_unhovered.emit(self)

# Selection lock state

func set_selected(value: bool) -> void:
	is_selected = value
	_refresh_target_lock_visibility()

func set_hover_locked(value: bool) -> void:
	hover_locked = value
	_refresh_target_lock_visibility()

# Drag / interaction state

func set_drag_source_active(active: bool) -> void:
	var alpha: float = 0.45 if active else 1.0

	asset_icon.modulate = Color(1.0, 1.0, 1.0, alpha)
	asset_qty.modulate = Color(1.0, 1.0, 1.0, alpha)
	selected_qty.modulate = Color(1.0, 1.0, 1.0, alpha)

	target_lock_icon.visible = false if active else _should_show_target_lock()

func set_interaction_locked(value: bool) -> void:
	interaction_locked = value
	disabled = value
	mouse_filter = Control.MOUSE_FILTER_IGNORE if value else Control.MOUSE_FILTER_STOP
	_refresh_target_lock_visibility()

func _refresh_target_lock_visibility() -> void:
	if interaction_locked:
		target_lock_icon.visible = is_selected
		return

	target_lock_icon.visible = _should_show_target_lock()

func _should_show_target_lock() -> bool:
	return is_selected or (is_mouse_over and not hover_locked)
