extends Node

## Small editable content backend for StorageDestination's atomic delivery API.
## A future warehouse/workshop can bind its own storage to the same endpoint.
signal changed
@export var item_id: String = "clay_lump"
@export_range(1, 9999, 1) var capacity: int = 96
var quantity: int = 0

func _ready() -> void:
	changed.connect(_refresh_label)
	_refresh_label()

func has_capacity_for(delivery_item_id: String, amount: int) -> bool:
	return delivery_item_id == item_id and amount > 0 and quantity + amount <= capacity

func try_add_item(delivery_item_id: String, amount: int) -> bool:
	if not has_capacity_for(delivery_item_id, amount):
		return false
	quantity += amount
	changed.emit()
	return true

func _refresh_label() -> void:
	var endpoint: StorageDestination = get_parent()
	endpoint.get_node("Label").text = "%s: %d / %d" % [endpoint.display_name, quantity, capacity]
