extends Node

var items: Dictionary[String, int] = {} # stok item milik workshop (bukan inventory player)
var claimable_outputs: Array[Dictionary] = [] # daftar output yang harus di-claim (escrow)
var unpaid_claims_ledger: Array[Dictionary] = [] # catatan claim yang belum bayar fee
var player_is_in_claim_area: bool = false # true jika player sedang berada di area workshop untuk claim

@export var fee_currency_item_id: String = "Shekel"
@export var unpaid_fee_due_days: int = 3
@export var overdue_penalty_percent_per_day: int = 10

enum ClaimAction {TAKE_TO_PLAYER, STORE_IN_WORKSHOP, CONTINUE_PROCESS}

func _ready() -> void:
	if TimeComponentManager != null and TimeComponentManager.has_signal("day_changed"):
		var day_changed_callable: Callable = Callable(self, "_on_day_changed")
		if not TimeComponentManager.is_connected("day_changed", day_changed_callable):
			TimeComponentManager.connect("day_changed", day_changed_callable)

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
	player_inventory: Node = null,
	will_pay_fee: bool = true) -> bool:
	# Claim hanya boleh kalau player sedang di area workshop
	if not player_is_in_claim_area:
		return false
	
	if claimable_index < 0 or claimable_index >= claimable_outputs.size():
		return false
		
	var entry: Dictionary = claimable_outputs[claimable_index]
	var items_ready: Dictionary = entry.get("items", {})
	var service_fee_shekel: int = max(int(entry.get("service_fee_shekel", 0)), 0)
	
	if claim_action == ClaimAction.TAKE_TO_PLAYER:
		if player_inventory == null:
			return false
		
		if not will_pay_fee:
			# Tidak bayar -> output disimpan ke workshop + catat hutang fee
			add_bulk_item(items_ready)
			_register_unpaid_fee(entry)
			claimable_outputs.remove_at(claimable_index)
			print("Claim di tunda bayar fee, item tersimpan di Workshop")
			print("Claimable count = ", claimable_outputs.size())
			return true
		
		if not _try_pay_service_fee(player_inventory, service_fee_shekel):
			print("Fee tidak cukup, claim gagal!")
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

func transfer_all_items_to_player(player_inventory: Node) -> bool:
	if player_inventory == null:
		return false
	
	if items.is_empty():
		return false
	
	var workshop_items_snapshot: Dictionary = items.duplicate(true)
	
	if player_inventory.has_method("add_bulk_item"):
		player_inventory.call("add_bulk_item", workshop_items_snapshot)
	else:
		for item_identifier in workshop_items_snapshot.keys():
			if player_inventory.has_method("add_item"):
				player_inventory.call("add_item", item_identifier, int(workshop_items_snapshot[item_identifier]))
			else:
				return false
	
	items.clear()
	return true

func _try_pay_service_fee(player_inventory: Node, service_fee_shekel: int) -> bool:
	if service_fee_shekel <= 0:
		return true
	
	if not player_inventory.has_method("has_item"):
		return false
	
	if not bool(player_inventory.call("has_item", fee_currency_item_id, service_fee_shekel)):
		return false
	
	if not player_inventory.has_method("remove_item"):
		return false
	
	return bool(player_inventory.call("remove_item", fee_currency_item_id, service_fee_shekel))

func _register_unpaid_fee(entry: Dictionary) -> void:
	var day_now: int = _get_current_day()
	unpaid_claims_ledger.append(
		{
			"worker_identifier": str(entry.get("worker_identifier", "")),
			"service_fee_shekel": max(int(entry.get("service_fee_shekel", 0)), 0),
			"final_fee_shekel": max(int(entry.get("service_fee_shekel", 0)), 0),
			"created_day": day_now,
			"due_day": day_now + max(unpaid_fee_due_days, 1),
			"completed_total_minutes": int(entry.get("completed_total_minutes", 0)),
			"last_penalty_day": day_now,
			"is_paid": false
		}
	)

func _get_current_day() -> int:
	if TimeComponentManager == null:
		return 0
	
	return(int(TimeComponentManager.get("current_day")))

func _on_day_changed(day_now: int) -> void:
	_apply_overdue_penalty(day_now)
	
func _apply_overdue_penalty(day_now: int) -> void:
	if unpaid_claims_ledger.is_empty():
		return
	
	for i in range(unpaid_claims_ledger.size()):
		var entry: Dictionary = unpaid_claims_ledger[i]
		if bool(entry.get("is_paid", false)):
			continue
		
		var due_day: int = int(entry.get("due_day", day_now + 1))
		if day_now < due_day:
			continue
		
		var last_penalty_day: int = int(entry.get("last_penalty_day", due_day))
		if day_now <= last_penalty_day:
			continue
		
		var penalty_days: int = day_now - last_penalty_day
		if penalty_days <= 0:
			continue
	
		var current_fee: int = max(int(entry.get("final_fee_shekel", entry.get("service_fee_shekel", 0))), 0)
		for _d in range(penalty_days):
			var penalty_add: int = int(ceil(float(current_fee) * float(max(overdue_penalty_percent_per_day,0)) / 100.0))
			current_fee += max(penalty_add, 0)
	
		entry["final_fee_shekel"] = current_fee
		entry["last_penalty_day"] = day_now
		entry["overdue_days"] = max(day_now - due_day, 0)
		unpaid_claims_ledger[i] = entry
	
func get_unpaid_fee_summary() -> Dictionary:
	var day_now: int = _get_current_day()
	_apply_overdue_penalty(day_now)
	
	var total_unpaid: int = 0
	var total_overdue: int = 0
	var unpaid_count: int = 0
	
	for entry in unpaid_claims_ledger:
		if bool(entry.get("is_paid", false)):
			continue
		unpaid_count += 1
		var final_fee: int = max(
			int(entry.get("final_fee_shekel", entry.get("service_fee_shekel", 0))
			), 0)
		total_unpaid += final_fee
		if day_now > int(entry.get("due_day", day_now + 1)):
			total_overdue += final_fee
		
	return {
			"unpaid_count": unpaid_count,
			"total_unpaid_shekel": total_unpaid,
			"total_overdue_shekel": total_overdue,
			"currency_item_id": fee_currency_item_id
			}

func settle_unpaid_fees(player_inventory: Node, pay_overdue_only: bool = false) -> bool:
	if player_inventory == null:
		return false
	
	var day_now: int = _get_current_day()
	_apply_overdue_penalty(day_now)
	
	var target_indices: Array[int] = []
	var total_fee: int = 0
	for i in range(unpaid_claims_ledger.size()):
		var entry: Dictionary = unpaid_claims_ledger[i]
		if bool(entry.get("is_paid", false)):
			continue
		var due_day: int = int(entry.get("due_day", day_now + 1))
		if pay_overdue_only and day_now <= due_day:
			continue
		
		target_indices.append(i)
		total_fee += max(int(entry.get("final_fee_shekel", entry.get("service_fee_shekel", 0))), 0)
		
	if total_fee <= 0:
		return false
	
	if not _try_pay_service_fee(player_inventory, total_fee):
		return false
	
	for index in target_indices:
		var paid_entry: Dictionary = unpaid_claims_ledger[index]
		paid_entry[index] = true
		paid_entry["paid_day"] = day_now
		unpaid_claims_ledger[index] = paid_entry
	
	return true
	
	
	
	
	
	
	
