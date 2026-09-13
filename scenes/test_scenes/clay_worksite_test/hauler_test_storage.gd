extends Node

# Fixture-only backend; real destinations bind their existing storage instead.
signal changed
@export var capacity: int = 96
var quantity: int = 0

func has_capacity_for(item_id: String, amount: int) -> bool:
	return item_id == "clay_lump" and amount > 0 and quantity + amount <= capacity

func try_add_item(item_id: String, amount: int) -> bool:
	if not has_capacity_for(item_id, amount):
		return false
	quantity += amount
	changed.emit()
	return true
