class_name ItemSlot extends Button

signal slot_clicked(item_id: String, quantity: int, node: Node)
signal slot_deposit_requested(item_id: String, quantity: int, node: Node)

@onready var asset_icon: TextureRect = $MarginContainer/AssetIcon
@onready var asset_qty: Label = $MarginContainer/AssetQty

var _item_id: String
var _quantity: int

func set_item(item_id: String, quantity: int, item_icon: Texture2D) -> void:
	asset_icon.texture = item_icon
	asset_qty.text = str(max(quantity, 0))
	var item_data: ItemData = ItemDatabase.get_item_data(item_id) as ItemData
	
	_item_id = item_id
	_quantity = quantity
	
	if item_data and item_data.display_name:
		tooltip_text = "%s x%s" % [item_data.display_name.capitalize(), asset_qty.text]
		if item_data.food_supply_value > 0:
			tooltip_text += "\nRight click: Send to City Stock"

func _on_pressed() -> void:
	slot_clicked.emit(_item_id, _quantity, self)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			slot_deposit_requested.emit(_item_id, _quantity, self)
