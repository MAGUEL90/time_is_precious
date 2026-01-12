extends Node


var items: Dictionary[String, int] = {}



func has_item(id: String, qty: int) -> bool:
	if items.has(id):
		return items[id] == qty
	
	return false

func add_item(id: String, qty: int) -> Dictionary:
	if items[id]:
		items[id] += qty

	return items

func remove_item(id: String, qty: int) -> bool:
	if 0 != items[id] - qty:
		items[id] - qty
	return false

# INI HINT, BARIS KE BERAPA AKU?
