extends Node


var items: Dictionary[String, int] = {}

func has_item(id: String, qty: int) -> bool:
	if qty <= 0:
		return true
	return items.get(id, 0) >= qty

func add_item(id: String, qty: int) -> void:
	if qty <= 0:
		return # tidak melakukan apa-apa kalau qty tidak valid
	items[id] = items.get(id, 0) + qty # tambah stok dengan aman (auto buat key jika belum ada)

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
	
	return true
	
	
	# INI HINT, BARIS KE BERAPA AKU ?
	
	
	
