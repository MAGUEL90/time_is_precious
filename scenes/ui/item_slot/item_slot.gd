extends Button

@onready var asset_icon: TextureRect = $MarginContainer/AssetIcon
@onready var asset_qty: Label = $MarginContainer/AssetQty

func set_item(item_id: String, quantity: int, item_icon: Texture2D) -> void:
	asset_icon.texture = item_icon
	asset_qty.text = str(max(quantity, 0))
	var item_data: ItemData = ItemDatabase.get_item_data(item_id) as ItemData
	if item_data and item_data.display_name:
		tooltip_text = "%s x%s" % [item_data.display_name.capitalize(), asset_qty.text]
