extends Node

signal items_changed()

var items: Dictionary[String, int] = {}
var max_load: float = 5.0

func _emit_items_changed() -> void:
	emit_signal("items_changed")

func has_item(id: String, qty: int) -> bool:
	if qty <= 0:
		return true
	return items.get(id, 0) >= qty

func get_item_data(item_id: String) -> ItemData:
	if not ItemDatabase:
		push_error("Item Database not exist")
		return null
	
	if item_id == "":
		return null
	
	return ItemDatabase.get_item_data(item_id)

func get_item_total_weight(item_id: String, qty: int) -> float:
	
	if item_id == "" or qty <= 0:
		return 0.0
	
	var item_data: ItemData = get_item_data(item_id)
	if item_data == null:
		return 0.0
	
	if item_data.weight <= 0.0:
		return 0.0
		
	return item_data.weight * qty

func get_total_inventory_weight() -> float:
	var total_weight: float = 0.0
	
	for item in items.keys():
		total_weight += get_item_total_weight(item, items[item])
	
	return total_weight

func get_remaining_capacity() -> float:
	var total_weight: float = get_total_inventory_weight()
	
	return max_load - total_weight

func has_capacity_for(item_id: String, qty: int) -> bool:
	return get_remaining_capacity() >= get_item_total_weight(item_id, qty)

func try_add_item(item_id: String, qty: int) -> bool:
	if item_id == "" or qty <= 0:
		return false

	if get_item_data(item_id) == null:
		return false
	
	if get_item_total_weight(item_id, qty) <= 0:
		return false
	
	if not has_capacity_for(item_id, qty):
		return false

	add_item(item_id, qty)
	return true

func add_item(id: String, qty: int) -> void:
	if qty <= 0:
		return # tidak melakukan apa-apa kalau qty tidak valid
	items[id] = items.get(id, 0) + qty # tambah stok dengan aman (auto buat key jika belum ada)
	_emit_items_changed()

func add_bulk_item(items_to_add: Dictionary) -> void:
	var has_mutation: bool = false
	for item_identifier in items_to_add.keys():
		var qty: int = int(items_to_add[item_identifier])
		if qty <= 0: continue
		items[item_identifier] = items.get(item_identifier, 0) + qty
		has_mutation = true
		
	if has_mutation:
		_emit_items_changed()

func remove_item(id: String, qty: int) -> bool:
	if qty <= 0:
		return true 
	
	var current: int = items.get(id, 0)
	if current < qty:
		return false
	var new_qty: int = current - qty
	if new_qty <= 0:
		items.erase(id) # kalau habis, hapus key biar bersih
	else:
		items[id] = new_qty
	_emit_items_changed()
	
	return true


	
	
