extends Button

@onready var asset_icon: TextureRect = $MarginContainer/AssetIcon
@onready var asset_qty: Label = $MarginContainer/AssetQty

func set_item(item_id: String, quantity: int, icon: Texture2D) -> void:
	asset_icon.texture = icon
	asset_qty.text = str(max(quantity, 0))
	tooltip_text = "%s x%s" % [item_id.replace("_", " ").capitalize(), asset_qty.text]
