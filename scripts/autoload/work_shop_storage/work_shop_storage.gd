extends Node

var items: Dictionary[String, int] = {} # stok item milik workshop (bukan inventory player)
var claimable_outputs: Array[Dictionary] = [] # daftar output yang harus di-claim (escrow)

var player_is_in_claim_area: bool = false # true jika player sedang berada di area workshop untuk claim

enum ClaimAction {TAKE_TO_PLAYER, STORE_IN_WORKSHOP, CONTINUE_PROCESS}

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

func set_player_in_claim_area(is_inside: bool) -> void:
	player_is_in_claim_area = is_inside

func claim_output(claimable_index: int) -> bool:
	# Backward compatible: default = simpan ke Inventory Workshop
	return claim_output_with_action(claimable_index, ClaimAction.STORE_IN_WORKSHOP, null)

func claim_output_with_action(
	claimable_index: int, 
	claim_action: int, 
	player_inventory: Node = null) -> bool:
	# Claim hanya boleh kalau player sedang di area workshop
	if not player_is_in_claim_area:
		return false
	
	if claimable_index < 0 or claimable_index >= claimable_outputs.size():
		return false
		
	var entry: Dictionary = claimable_outputs[claimable_index]
	var items_ready: Dictionary = entry.get("items", {})
	
	# TODO: fee / hutang / barter diproses disini
	
	if claim_action == ClaimAction.TAKE_TO_PLAYER:
		if player_inventory == null:
			return false
			
		if player_inventory.has_method("add_bulk_item"):
			player_inventory.call("add_bulk_item", items_ready)
		else:
			for item_identifier in items_ready.keys():
				if player_inventory.has_method("add_item"):
					player_inventory.call("add_item", item_identifier, int(items_ready[item_identifier]))
				else:
					return false
		
	elif claim_action == ClaimAction.STORE_IN_WORKSHOP:
		
		# (🟢 +) DEBUG OPSI 2
		print("OPT2: claimable_size(before)=", claimable_outputs.size())
		print("OPT2: claimable_index=", claimable_index)
		print("OPT2: entry(before)=", entry)
		
		add_bulk_item(items_ready)
		
		print("OPT2: items_after_adding_to_workshop_storage: workshop items = ", items)
	
	elif claim_action == ClaimAction.CONTINUE_PROCESS:
		print("OPT3: before_adding_to_workshop_storage: workshop items = ", items)
		print("OPT3: before: claimable count = ", claimable_outputs.size())
		# Untuk sekarang: taruh dulu ke inventory workshop
		# Lalu minta ProcessManager auto-pull (kalau tersedia)
		
		add_bulk_item(items_ready)
		print("OPT3: items_after_adding_to_workshop_storage: workshop items = ", items)
		
		var process_manager: Node = get_node("/root/ProcessManager")
		if process_manager != null and process_manager.has_method("request_auto_pull"):
			process_manager.call("request_auto_pull")
		
		print("OPT3: items_after_sending_to_continue_process: workshop items = ", items)
		
		
	else:
		return false
		
	claimable_outputs.remove_at(claimable_index)
	print("Claimable count = ", claimable_outputs.size())
	return true

			
			
			
			
			
			
			
