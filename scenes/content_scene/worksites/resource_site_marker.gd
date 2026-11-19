extends Marker2D

## Configuration only; execution, inspection, assignments and hauling stay in Worksites.
const GATHERING_CONFIG = preload("res://scenes/content_scene/worksites/gathering_config.gd")
@export var item_id: String = GATHERING_CONFIG.DEFAULT_ITEM_ID
@export_range(1.0, 120.0, 0.5) var minutes_per_unit: float = GATHERING_CONFIG.DEFAULT_MINUTES_PER_UNIT
@export_range(1, 1000, 1) var daily_stock: int = GATHERING_CONFIG.DEFAULT_STOCK

func configure_session(session) -> void:
	session.item_id = item_id
	session.minutes_per_unit = minutes_per_unit
	session.stock = daily_stock
	session.daily_stock_min = daily_stock
	session.daily_stock_max = daily_stock

func _ready() -> void:
	var item: ItemData = ItemDatabase.get_item_data(item_id)
	if item != null and has_node("ResourceIcon") and $ResourceIcon.texture == null:
		$ResourceIcon.texture = item.icon
