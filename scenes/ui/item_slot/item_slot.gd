class_name ItemSlot extends Button

signal slot_clicked(item_id: String, quantity: int, slot_ref: ItemSlot)
signal slot_deposit_requested(item_id: String, quantity: int, node: Node)
signal slot_hovered(item_id: String, quantity: int, slot_ref: ItemSlot)
signal slot_unhovered(slot_ref: ItemSlot)

@onready var target_lock_icon: TextureRect = $TargetLockIcon
@onready var asset_icon: TextureRect = $MarginContainer/AssetIcon
@onready var asset_qty: Label = $MarginContainer/AssetQty
@onready var selected_qty: Label = $SelectedQty

var _item_id: String
var _quantity: int
var is_selected: bool = false
var is_mouse_over: bool = false
var hover_locked: bool = false

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
	slot_clicked.emit(_item_id, _quantity, self)

func _gui_input(event: InputEvent) -> void:
	pass

# Selection state

func set_selected_quantity(quantity: int) -> void:
	selected_qty.visible = quantity > 0
	selected_qty.text = str(quantity)

# Hover state

func _on_mouse_entered() -> void:
	is_mouse_over = true

	if not hover_locked:
		target_lock_icon.visible = true

	slot_hovered.emit(_item_id, _quantity, self)

func _on_mouse_exited() -> void:
	is_mouse_over = false
	target_lock_icon.visible = is_selected
	slot_unhovered.emit(self)

# Selection lock state

func set_selected(value: bool) -> void:
	is_selected = value
	target_lock_icon.visible = is_selected or (is_mouse_over and not hover_locked)

func set_hover_locked(value: bool) -> void:
	hover_locked = value
	target_lock_icon.visible = is_selected or (is_mouse_over and not hover_locked)
