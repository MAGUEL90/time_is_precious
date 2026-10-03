extends Node

## Small editable content backend for StorageDestination's atomic delivery API.
## A future warehouse/workshop can bind its own storage to the same endpoint.
signal changed
@export var item_id: String = "clay_lump"
@export var compact_label: bool = false
@export_range(1, 9999, 1) var capacity: int = 96
var quantity: int = 0
var _withdrawing: bool = false

func withdraw_to_inventory() -> int:
	if _withdrawing or quantity <= 0:
		return 0
	var item: ItemData = ItemDatabase.get_item_data(item_id)
	if item == null or item.weight <= 0.0:
		return 0
	var amount: int = mini(quantity, maxi(0, floori(Inventory.get_remaining_capacity() / item.weight)))
	if amount <= 0:
		return 0
	_withdrawing = true
	quantity -= amount
	if not Inventory.try_add_item(item_id, amount):
		quantity += amount
		amount = 0
	_withdrawing = false
	changed.emit()
	return amount

func _ready() -> void:
	changed.connect(_refresh_label)
	_refresh_label()

func accepts_item(delivery_item_id: String) -> bool:
	return delivery_item_id == item_id

func has_capacity_for(delivery_item_id: String, amount: int) -> bool:
	return accepts_item(delivery_item_id) and amount > 0 and quantity + amount <= capacity

func try_add_item(delivery_item_id: String, amount: int) -> bool:
	if not has_capacity_for(delivery_item_id, amount):
		return false
	quantity += amount
	changed.emit()
	return true

func _refresh_label() -> void:
	var endpoint: StorageDestination = get_parent()
	var separator: String = "\n" if compact_label else ": "
	endpoint.get_node("Label").text = "%s%s%d / %d" % [endpoint.display_name, separator, quantity, capacity]
