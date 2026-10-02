extends Marker2D

## Configuration only; execution, inspection, assignments and hauling stay in Worksites.
@export var item_id: String = "clay_lump"
@export_range(1.0, 120.0, 0.5) var minutes_per_unit: float = 10.0
@export_range(1, 1000, 1) var daily_stock: int = 72

func configure_session(session) -> void:
	session.item_id = item_id
	session.minutes_per_unit = minutes_per_unit
	session.stock = daily_stock
	session.daily_stock_min = daily_stock
	session.daily_stock_max = daily_stock

func _ready() -> void:
	var item: ItemData = ItemDatabase.get_item_data(item_id)
	if item != null and has_node("ResourceIcon"):
		$ResourceIcon.texture = item.icon
