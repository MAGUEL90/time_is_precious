class_name WorkShopStorage extends Node

var items: Dictionary[String, int] = {} # stok item milik workshop (bukan inventory player)
var claimable_outputs: Array[Dictionary] = [] # daftar output yang harus di-claim (escrow)

func has_item(item_identifier: String, quantity: int) -> bool:
	if quantity <= 0:
		return true # qty 0 dianggap cukup agar aman untuk edge-case
	return items.get(item_identifier, 0) >= quantity # cek stok workshop

func add_item(item_identifier: String, quantity: int) -> void:
	if quantity <= 0:
		return
	
	items[item_identifier] = items.get(item_identifier, 0) + quantity # tambah stok workshop

func add_bulk_item(items_to_add: Dictionary) -> void:
	for item_identifier in items_to_add.keys():
		add_item(item_identifier, int(items_to_add[item_identifier])) # helper tambah banyak item sekaligus
	
func remove_item(item_identifier: String, quantity: int) -> bool:
	if quantity <= 0:
		return true # remove 0 dianggap sukses
	
	var current_quantity: int = items.get(item_identifier, 0) # aman walau item belum ada
	if current_quantity < quantity: 
		return false # stok workshop tidak cukup
	var new_quantity: int = current_quantity - quantity # hitung sisa
	if new_quantity <= 0:
		items.erase(item_identifier) # habis -> hapus key agar rapi
	else:
		items[item_identifier] = new_quantity # update sisa
	return true

func add_claimable_output(
	items_ready: Dictionary[String, int], 
	service_fee_shekel: int,
	worker_identifier: String, 
	completed_total_minutes: int, 
	expires_total_minutes: int = -1) -> void:
		
	claimable_outputs.append(
		{
			"items": items_ready, # output yang siap diambil
			"service_fee_shekel": max(service_fee_shekel, 0), # biaya jasa minimal 0
			"worker_identifier": worker_identifier, # siapa pekerjanya (NPC id)
			"completed_total_minutes": completed_total_minutes, # kapan selesai
			"expires_total_minutes": expires_total_minutes # -1 = tidak kadaluarsa dulu
		}
	)
	
	
	
	
	
	
	
