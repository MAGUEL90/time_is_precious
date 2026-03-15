extends Node

signal items_changed()

var items: Dictionary[String, int] = {}

func _emit_items_changed() -> void:
	emit_signal("items_changed")

func has_item(id: String, qty: int) -> bool:
	if qty <= 0:
		return true
	return items.get(id, 0) >= qty

func add_item(id: String, qty: int) -> void:
	if qty <= 0:
		return # tidak melakukan apa-apa kalau qty tidak valid
	items[id] = items.get(id, 0) + qty # tambah stok dengan aman (auto buat key jika belum ada)
	_emit_items_changed()


func add_bulk_item(items_to_add: Dictionary) -> void:
	var has_mutation: bool = false
	for item_identifier in items_to_add.keys():
		var qty: int = int(items_to_add[item_identifier])
		if qty <= 0:
			continue
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
	
	
	
	
