extends Node

var items: Dictionary[String, int] = {} # stok item milik workshop (bukan inventory player)
var claimable_outputs: Array[Dictionary] = [] # output tertunda karena storage penuh
var unpaid_claims_ledger: Array[Dictionary] = [] # catatan claim yang belum bayar fee
var player_is_in_claim_area: bool = false # true jika player sedang berada di area workshop untuk claim
var max_load: float = 50.0
var _next_fee_sequence: int = 1
var _next_output_lot_sequence: int = 1
var output_lots: Array[Dictionary] = []

@export var fee_currency_item_id: String = "shekel"
@export var unpaid_fee_due_days: int = 3
@export var overdue_penalty_percent_per_day: int = 10
@export_range(1.0, 10.0, 0.1) var overdue_fee_max_multiplier: float = 2.0

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

func get_held_item_quantity(item_identifier: String) -> int:
	if item_identifier.is_empty():
		return 0

	var held_quantity: int = 0
	for lot in output_lots:
		var lot_items: Dictionary = lot.get("items", {})
		held_quantity += maxi(
			int(lot_items.get(item_identifier, 0)),
			0
		)

	return held_quantity

func get_free_item_quantity(item_identifier: String) -> int:
	if item_identifier.is_empty():
		return 0

	var total_quantity: int = maxi(
		int(items.get(item_identifier, 0)),
		0
	)
	var held_quantity: int = get_held_item_quantity(
		item_identifier
	)

	return maxi(total_quantity - held_quantity, 0)

func get_free_items_snapshot() -> Dictionary[String, int]:
	var free_items: Dictionary[String, int] = {}
	for item_id_value in items.keys():
		var item_id: String = str(item_id_value)
		var free_quantity: int = get_free_item_quantity(item_id)
		if free_quantity > 0:
			free_items[item_id] = free_quantity

	return free_items

func get_held_output_lot_summaries() -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	for lot in output_lots:
		var summary: Dictionary = lot.duplicate(true)
		var lot_fee_ids: Array[String] = _to_string_array(
			lot.get("fee_ids", [])
		)
		summary["fee_totals"] = _get_unpaid_fee_totals(
			lot_fee_ids
		)
		summaries.append(summary)

	return summaries

func get_held_output_fee_totals() -> Dictionary[String, int]:
	var held_fee_ids: Array[String] = []
	for lot in output_lots:
		for fee_id in _to_string_array(lot.get("fee_ids", [])):
			if not held_fee_ids.has(fee_id):
				held_fee_ids.append(fee_id)

	return _get_unpaid_fee_totals(held_fee_ids)

func get_storage_state() -> Dictionary:
	try_deliver_pending_outputs()
	return {
		"free_items": get_free_items_snapshot(),
		"held_lots": get_held_output_lot_summaries(),
		"held_fee_totals": get_held_output_fee_totals(),
		"pending_count": get_pending_output_count(),
		"used_capacity": get_total_storage_weight(),
		"remaining_capacity": get_remaining_capacity(),
		"max_capacity": max_load
	}

func consume_item_for_process(
	item_identifier: String,
	quantity: int
) -> Dictionary:
	var empty_fee_ids: Array[String] = []
	var result: Dictionary = {
		"success": false,
		"fee_ids": empty_fee_ids
	}

	if item_identifier.is_empty() or quantity <= 0:
		return result

	var free_quantity: int = get_free_item_quantity(
		item_identifier
	)
	if free_quantity < quantity:
		print(
			"Process input blocked by Held Output: ",
			item_identifier,
			" | Free ",
			free_quantity,
			" | Required ",
			quantity
		)
		return result

	result["success"] = remove_item(
		item_identifier,
		quantity
	)
	return result

func remove_free_items(items_to_remove: Dictionary) -> bool:
	if items_to_remove.is_empty():
		return false

	for item_id_value in items_to_remove.keys():
		var item_id: String = str(item_id_value)
		var quantity: int = int(items_to_remove[item_id_value])
		if quantity <= 0:
			return false
		if get_free_item_quantity(item_id) < quantity:
			return false

	for item_id_value in items_to_remove.keys():
		var item_id: String = str(item_id_value)
		remove_item(item_id, int(items_to_remove[item_id_value]))

	try_deliver_pending_outputs()
	return true

func add_claimable_output(
	items_ready: Dictionary[String, int],
	service_fee_shekel: int,
	worker_identifier: String,
	completed_total_minutes: int,
	expires_total_minutes: int = -1,
	fee_ids: Array[String] = [],
	source_type: String = "",
	source_id: String = ""
	) -> void:
	var safe_fee_ids: Array[String] = []

	for fee_id_value in fee_ids:
		var fee_id: String = fee_id_value.strip_edges()
		if fee_id.is_empty() or safe_fee_ids.has(fee_id):
			continue

		safe_fee_ids.append(fee_id)

	claimable_outputs.append(
		{
			"items": items_ready.duplicate(true), # output yang siap diambil
			"service_fee_shekel": max(service_fee_shekel, 0), # biaya jasa minimal 0
			"worker_identifier": worker_identifier, # siapa pekerjanya (NPC id)
			"completed_total_minutes": completed_total_minutes, # kapan selesai
			"expires_total_minutes": expires_total_minutes, # -1 = tidak kadaluarsa dulu
			"fee_ids": safe_fee_ids,
			"source_type": source_type,
			"source_id": source_id,
			"status": "pending_space"
		}
	)

func has_blocking_pending_output() -> bool:
	return not claimable_outputs.is_empty()

func get_pending_output_count() -> int:
	return claimable_outputs.size()

func register_completed_job_fee(
	service_fee_shekel: int,
	worker_identifier: String,
	completed_total_minutes: int,
	job_id: String = "",
	currency_item_id: String = ""
) -> String:
	var safe_fee: int = maxi(service_fee_shekel, 0)
	if safe_fee <= 0:
		return ""

	var fee_source_id: String = job_id.strip_edges()
	if fee_source_id.is_empty():
		fee_source_id = worker_identifier

	var safe_currency_id: String = currency_item_id.strip_edges()
	if safe_currency_id.is_empty():
		safe_currency_id = fee_currency_item_id

	return _register_unpaid_fee({
		"service_fee_shekel": safe_fee,
		"currency_item_id": safe_currency_id,
		"is_active": false,
		"fee_source_type": "job",
		"fee_source_id": fee_source_id,
		"worker_identifier": worker_identifier,
		"completed_total_minutes": completed_total_minutes
		})

func register_process_station_fee(
	process_id: String,
	fee_amount: int,
	currency_item_id: String) -> String:

	var safe_fee: int = maxi(fee_amount, 0)
	if safe_fee <= 0:
		return ""

	var safe_currency_id: String = currency_item_id.strip_edges()
	if safe_currency_id.is_empty():
		safe_currency_id = fee_currency_item_id

	return _register_unpaid_fee({
		"service_fee_shekel": safe_fee,
		"currency_item_id": safe_currency_id,
		"is_active": false,
		"fee_source_type": "process",
		"fee_source_id": process_id,
		"worker_identifier": "",
		"completed_total_minutes": _get_current_total_minutes()
	})

func try_store_completed_output(
	items_ready: Dictionary[String, int]
) -> bool:
	if items_ready.is_empty():
		return false
	if not has_capacity_for_bulk(items_ready):
		return false

	add_bulk_item(items_ready)
	return true

func receive_completed_output(
	items_ready: Dictionary[String, int],
	service_fee_shekel: int,
	worker_identifier: String,
	completed_total_minutes: int,
	job_id: String = "",
	currency_item_id: String = ""
) -> bool:
	var fee_id: String = register_completed_job_fee(
		service_fee_shekel,
		worker_identifier,
		completed_total_minutes,
		job_id,
		currency_item_id
	)

	if try_store_completed_output(items_ready):
		if not fee_id.is_empty():
			var fee_ids: Array[String] = []
			fee_ids.append(fee_id)

			_create_output_lot(
				items_ready,
				fee_ids,
				"job",
				job_id,
				completed_total_minutes
			)

		return true

	var pending_fee_ids: Array[String] = []
	if not fee_id.is_empty():
		pending_fee_ids.append(fee_id)

	add_claimable_output(
		items_ready,
		0,
		worker_identifier,
		completed_total_minutes,
		-1,
		pending_fee_ids,
		"job",
		job_id
	)
	return false

func set_player_in_claim_area(is_inside: bool) -> void:
	player_is_in_claim_area = is_inside

func transfer_all_items_to_player(player_inventory: Node) -> bool:
	if player_inventory == null:
		return false

	var free_items: Dictionary[String, int] = get_free_items_snapshot()
	if free_items.is_empty():
		return false

	if not player_inventory.has_method("get_remaining_capacity"):
		return false
	if (
		float(player_inventory.call("get_remaining_capacity"))
		< get_bulk_item_total_weight(free_items)
	):
		return false

	if player_inventory.has_method("add_bulk_item"):
		player_inventory.call("add_bulk_item", free_items)
	else:
		for item_identifier in free_items.keys():
			if player_inventory.has_method("add_item"):
				player_inventory.call(
					"add_item",
					item_identifier,
					int(free_items[item_identifier])
				)
			else:
				return false

	for item_identifier in free_items.keys():
		remove_item(item_identifier, int(free_items[item_identifier]))

	try_deliver_pending_outputs()
	return true

func _to_string_array(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if not (values is Array):
		return result

	for value in values:
		var text_value: String = str(value).strip_edges()
		if not text_value.is_empty() and not result.has(text_value):
			result.append(text_value)

	return result

func _get_fee_entry_index(fee_id: String) -> int:
	for index in range(unpaid_claims_ledger.size()):
		if str(unpaid_claims_ledger[index].get("fee_id", "")) == fee_id:
			return index

	return -1

func _get_unpaid_fee_indices(
	fee_ids: Array[String],
	pay_overdue_only: bool = false
) -> Array[int]:
	var indices: Array[int] = []
	var day_now: int = _get_current_day()
	for fee_id in fee_ids:
		var index: int = _get_fee_entry_index(fee_id)
		if index < 0:
			continue

		var entry: Dictionary = unpaid_claims_ledger[index]
		if bool(entry.get("is_paid", false)):
			continue
		if not bool(entry.get("is_active", true)):
			continue
		if (
			pay_overdue_only
			and day_now <= int(entry.get("due_day", day_now + 1))
		):
			continue
		indices.append(index)

	return indices

func _get_fee_totals_for_indices(
	fee_indices: Array[int]
) -> Dictionary[String, int]:
	var totals: Dictionary[String, int] = {}
	for index in fee_indices:
		if index < 0 or index >= unpaid_claims_ledger.size():
			continue

		var entry: Dictionary = unpaid_claims_ledger[index]
		var currency_id: String = str(
			entry.get("currency_item_id", fee_currency_item_id)
		).strip_edges()
		if currency_id.is_empty():
			currency_id = fee_currency_item_id

		var amount: int = maxi(
			int(
				entry.get(
					"final_fee_shekel",
					entry.get("service_fee_shekel", 0)
				)
			),
			0
		)
		if amount > 0:
			totals[currency_id] = totals.get(currency_id, 0) + amount

	return totals

func _get_unpaid_fee_totals(
	fee_ids: Array[String]
) -> Dictionary[String, int]:
	_apply_overdue_penalty(_get_current_day())
	return _get_fee_totals_for_indices(
		_get_unpaid_fee_indices(fee_ids)
	)

func _try_pay_currency_totals(
	player_inventory: Node,
	currency_totals: Dictionary[String, int]
) -> bool:
	if player_inventory == null:
		return false
	if (
		not player_inventory.has_method("has_item")
		or not player_inventory.has_method("remove_item")
	):
		return false

	for currency_id in currency_totals.keys():
		var amount: int = maxi(int(currency_totals[currency_id]), 0)
		if amount <= 0:
			continue
		if not bool(player_inventory.call("has_item", currency_id, amount)):
			return false

	var paid_totals: Dictionary[String, int] = {}
	for currency_id in currency_totals.keys():
		var amount: int = maxi(int(currency_totals[currency_id]), 0)
		if amount <= 0:
			continue
		if not bool(player_inventory.call("remove_item", currency_id, amount)):
			for paid_currency_id in paid_totals.keys():
				if player_inventory.has_method("add_item"):
					player_inventory.call(
						"add_item",
						paid_currency_id,
						int(paid_totals[paid_currency_id])
					)
			return false
		paid_totals[currency_id] = amount

	return true

func _mark_fee_indices_paid(fee_indices: Array[int]) -> void:
	var day_now: int = _get_current_day()
	for index in fee_indices:
		if index < 0 or index >= unpaid_claims_ledger.size():
			continue
		var paid_entry: Dictionary = unpaid_claims_ledger[index]
		paid_entry["is_paid"] = true
		paid_entry["paid_day"] = day_now
		unpaid_claims_ledger[index] = paid_entry

func _activate_fee_ids(fee_ids: Array[String]) -> void:
	var day_now: int = _get_current_day()
	var due_day: int = day_now + max(unpaid_fee_due_days, 1)
	for fee_id in fee_ids:
		var index: int = _get_fee_entry_index(fee_id)
		if index < 0:
			continue

		var entry: Dictionary = unpaid_claims_ledger[index]
		if bool(entry.get("is_paid", false)):
			continue
		if bool(entry.get("is_active", false)):
			continue

		entry["is_active"] = true
		entry["created_day"] = day_now
		entry["due_day"] = due_day
		entry["last_penalty_day"] = due_day
		unpaid_claims_ledger[index] = entry

func cancel_inactive_fees(fee_ids: Array[String]) -> void:
	for index in range(unpaid_claims_ledger.size() - 1, -1, -1):
		var entry: Dictionary = unpaid_claims_ledger[index]
		if not fee_ids.has(str(entry.get("fee_id", ""))):
			continue
		if bool(entry.get("is_active", true)):
			continue
		if bool(entry.get("is_paid", false)):
			continue
		unpaid_claims_ledger.remove_at(index)

func _lot_has_unpaid_fee(lot: Dictionary) -> bool:
	var lot_fee_ids: Array[String] = _to_string_array(
		lot.get("fee_ids", [])
	)
	return not _get_unpaid_fee_indices(lot_fee_ids).is_empty()

func _release_paid_output_lots() -> int:
	var released_count: int = 0
	for index in range(output_lots.size() - 1, -1, -1):
		if _lot_has_unpaid_fee(output_lots[index]):
			continue
		output_lots.remove_at(index)
		released_count += 1

	return released_count

func pay_output_lot(lot_id: String, player_inventory: Node) -> Dictionary:
	var result: Dictionary = {
		"success": false,
		"message": "Held Output is no longer available."
	}
	var lot_index: int = -1
	for index in range(output_lots.size()):
		if str(output_lots[index].get("lot_id", "")) == lot_id:
			lot_index = index
			break

	if lot_index < 0:
		return result

	_apply_overdue_penalty(_get_current_day())
	var lot: Dictionary = output_lots[lot_index]
	var fee_indices: Array[int] = _get_unpaid_fee_indices(
		_to_string_array(lot.get("fee_ids", []))
	)
	var fee_totals: Dictionary[String, int] = (
		_get_fee_totals_for_indices(fee_indices)
	)

	if not fee_totals.is_empty():
		if not _try_pay_currency_totals(player_inventory, fee_totals):
			result["message"] = "Not enough currency to pay this output fee."
			return result
		_mark_fee_indices_paid(fee_indices)

	output_lots.remove_at(lot_index)
	_release_paid_output_lots()
	result["success"] = true
	result["message"] = "Output unlocked and moved to Free Stock."
	return result

func _register_unpaid_fee(entry: Dictionary) -> String:
	var service_fee_shekel: int = maxi(
		int(entry.get("service_fee_shekel", 0)),
		0
	)
	if service_fee_shekel <= 0:
		return ""

	var fee_id: String = _generate_fee_id()
	var day_now: int = _get_current_day()
	var due_day: int = day_now + max(unpaid_fee_due_days, 1)

	unpaid_claims_ledger.append(
		{
			"fee_id": fee_id,
			"worker_identifier": str(entry.get("worker_identifier", "")),
			"service_fee_shekel": service_fee_shekel,
			"final_fee_shekel": service_fee_shekel,
			"created_day": day_now,
			"due_day": due_day,
			"completed_total_minutes": int(entry.get("completed_total_minutes", 0)),
			"last_penalty_day": due_day,
			"is_active": bool(entry.get("is_active", true)),
			"is_paid": false,
			"currency_item_id": str(entry.get("currency_item_id", fee_currency_item_id)),
			"fee_source_type": str(entry.get("fee_source_type", "job")),
			"fee_source_id": str(entry.get("fee_source_id", entry.get("worker_identifier", "")))
		}
	)
	print("Registered Workshop fee: ", fee_id)
	return fee_id

func _get_current_total_minutes() -> int:
	if TimeComponentManager == null:
		return 0

	return (
		int(TimeComponentManager.get("current_day")) * 24 * 60
		+ int(TimeComponentManager.get("current_hour")) * 60
		+ int(TimeComponentManager.get("current_minute"))
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
		if not bool(entry.get("is_active", true)):
			continue

		var due_day: int = int(entry.get("due_day", day_now + 1))
		if day_now <= due_day:
			continue

		var last_penalty_day: int = maxi(
			int(entry.get("last_penalty_day", due_day)),
			due_day
		)
		if day_now <= last_penalty_day:
			continue

		var penalty_days: int = day_now - last_penalty_day
		if penalty_days <= 0:
			continue

		var base_fee: int = maxi(
			int(entry.get("service_fee_shekel", 0)),
			0
		)
		var overdue_days: int = maxi(day_now - due_day, 0)
		var daily_penalty: int = ceili(
			float(base_fee)
			* float(maxi(overdue_penalty_percent_per_day, 0))
			/ 100.0
		)
		var maximum_fee: int = maxi(
			ceili(
				float(base_fee)
				* maxf(overdue_fee_max_multiplier, 1.0)
			),
			base_fee
		)
		var linear_fee: int = base_fee + daily_penalty * overdue_days

		entry["final_fee_shekel"] = mini(linear_fee, maximum_fee)
		entry["last_penalty_day"] = day_now
		entry["overdue_days"] = overdue_days
		unpaid_claims_ledger[i] = entry

func get_unpaid_fee_summary() -> Dictionary:
	var day_now: int = _get_current_day()
	_apply_overdue_penalty(day_now)

	var totals_by_currency: Dictionary[String, int] = {}
	var overdue_totals_by_currency: Dictionary[String, int] = {}
	var unpaid_count: int = 0

	for entry in unpaid_claims_ledger:
		if bool(entry.get("is_paid", false)):
			continue
		if not bool(entry.get("is_active", true)):
			continue
		unpaid_count += 1
		var currency_id: String = str(
			entry.get("currency_item_id", fee_currency_item_id)
		).strip_edges()
		if currency_id.is_empty():
			currency_id = fee_currency_item_id
		var final_fee: int = max(
			int(entry.get("final_fee_shekel", entry.get("service_fee_shekel", 0))
			), 0)
		totals_by_currency[currency_id] = (
			totals_by_currency.get(currency_id, 0) + final_fee
		)
		if day_now > int(entry.get("due_day", day_now + 1)):
			overdue_totals_by_currency[currency_id] = (
				overdue_totals_by_currency.get(currency_id, 0)
				+ final_fee
			)

	return {
			"unpaid_count": unpaid_count,
			"total_unpaid_shekel": int(
				totals_by_currency.get(fee_currency_item_id, 0)
			),
			"total_overdue_shekel": int(
				overdue_totals_by_currency.get(fee_currency_item_id, 0)
			),
			"currency_item_id": fee_currency_item_id,
			"totals_by_currency": totals_by_currency,
			"overdue_totals_by_currency": overdue_totals_by_currency
			}

func settle_unpaid_fees(player_inventory: Node, pay_overdue_only: bool = false) -> bool:
	if player_inventory == null:
		return false

	var day_now: int = _get_current_day()
	_apply_overdue_penalty(day_now)

	var target_indices: Array[int] = []
	for i in range(unpaid_claims_ledger.size()):
		var entry: Dictionary = unpaid_claims_ledger[i]
		if bool(entry.get("is_paid", false)):
			continue
		if not bool(entry.get("is_active", true)):
			continue
		var due_day: int = int(entry.get("due_day", day_now + 1))
		if pay_overdue_only and day_now <= due_day:
			continue

		target_indices.append(i)

	if target_indices.is_empty():
		return false

	var currency_totals: Dictionary[String, int] = (
		_get_fee_totals_for_indices(target_indices)
	)
	if not _try_pay_currency_totals(player_inventory, currency_totals):
		return false

	_mark_fee_indices_paid(target_indices)
	_release_paid_output_lots()

	return true

func settle_held_output_fees(player_inventory: Node) -> bool:
	if player_inventory == null or output_lots.is_empty():
		return false

	_apply_overdue_penalty(_get_current_day())

	var held_fee_ids: Array[String] = []
	for lot in output_lots:
		for fee_id in _to_string_array(lot.get("fee_ids", [])):
			if not held_fee_ids.has(fee_id):
				held_fee_ids.append(fee_id)

	var target_indices: Array[int] = _get_unpaid_fee_indices(held_fee_ids)
	if target_indices.is_empty():
		return false

	var currency_totals: Dictionary[String, int] = (
		_get_fee_totals_for_indices(target_indices)
	)
	if not _try_pay_currency_totals(player_inventory, currency_totals):
		return false

	_mark_fee_indices_paid(target_indices)
	_release_paid_output_lots()
	return true

func get_item_total_weight(item_id: String, qty: int) -> float:
	return Inventory.get_item_total_weight(item_id, qty)

func get_total_storage_weight() -> float:
	var total_weight: float = 0.0
	for item_id in items.keys():
		total_weight += get_item_total_weight(item_id, items[item_id])
	return total_weight

func get_remaining_capacity() -> float:
	return max_load - get_total_storage_weight()

func has_capacity_for(item_id: String, qty: int) -> bool:
	return get_remaining_capacity() >= get_item_total_weight(item_id, qty)

func try_add_item(item_id: String, qty: int) -> bool:

	if item_id == "" or qty <= 0:
		return false

	if not ItemDatabase.has_item_data(item_id):
		return false

	if get_item_total_weight(item_id, qty) <= 0:
		return false

	if not has_capacity_for(item_id, qty):
		return false

	add_item(item_id, qty)
	return true

func get_bulk_item_total_weight(items_to_check: Dictionary) -> float:
	var total_weight: float = 0.0
	for item_id in items_to_check.keys():
		var qty: int = int(items_to_check[item_id])
		total_weight += get_item_total_weight(item_id, qty)
	return total_weight

func has_capacity_for_bulk(items_to_check: Dictionary) -> bool:
	return get_remaining_capacity() >= get_bulk_item_total_weight(items_to_check)

func get_projected_weight_after_exchange(
	items_to_remove: Dictionary,
	items_to_add: Dictionary
) -> float:
	var projected_weight: float = get_total_storage_weight()
	projected_weight -= get_bulk_item_total_weight(items_to_remove)
	projected_weight += get_bulk_item_total_weight(items_to_add)

	return maxf(projected_weight, 0.0)

func has_capacity_after_exchange(
	items_to_remove: Dictionary,
	items_to_add: Dictionary
) -> bool:
	return (
		get_projected_weight_after_exchange(
			items_to_remove,
			items_to_add
		)
		<= max_load
	)

func _generate_fee_id() -> String:
	var fee_id: String = "fee_%d" % _next_fee_sequence
	_next_fee_sequence += 1
	return fee_id

func _generate_output_lot_id() -> String:
	var lot_id: String = "lot_%d" % _next_output_lot_sequence
	_next_output_lot_sequence += 1
	return lot_id

func _create_output_lot(
	items_ready: Dictionary,
	fee_ids: Array[String],
	source_type: String,
	source_id: String,
	created_total_minutes: int
) -> String:
	var safe_items: Dictionary[String, int] = {}
	for item_id_value in items_ready.keys():
		var item_id: String = str(item_id_value)
		var quantity: int = maxi(int(items_ready[item_id_value]), 0)
		if item_id.is_empty() or quantity <= 0:
			continue

		safe_items[item_id] = quantity

	if safe_items.is_empty():
		return ""

	var safe_fee_ids: Array[String] = []
	var candidate_fee_ids: Array[String] = _to_string_array(fee_ids)
	_activate_fee_ids(candidate_fee_ids)
	for fee_id_value in candidate_fee_ids:
		var fee_id: String = fee_id_value.strip_edges()
		if fee_id.is_empty() or safe_fee_ids.has(fee_id):
			continue
		var fee_index: int = _get_fee_entry_index(fee_id)
		if fee_index < 0:
			continue
		if bool(unpaid_claims_ledger[fee_index].get("is_paid", false)):
			continue
		safe_fee_ids.append(fee_id)

	# Output tanpa fee langsung dianggap stock bebas.
	if safe_fee_ids.is_empty():
		return ""

	var lot_id: String = _generate_output_lot_id()

	output_lots.append({
		"lot_id": lot_id,
		"items": safe_items,
		"fee_ids": safe_fee_ids,
		"source_type": source_type,
		"source_id": source_id,
		"created_total_minutes": created_total_minutes
	})
	print(
		"Created Workshop output lot: ",
		lot_id,
		" | Items: ",
		safe_items,
		" | Fees: ",
		safe_fee_ids
	)
	return lot_id

func receive_completed_process_output(
	items_ready: Dictionary[String, int],
	attached_fee_ids: Array[String],
	process_id: String,
	completed_total_minutes: int
) -> bool:
	if items_ready.is_empty():
		return false

	if try_store_completed_output(items_ready):
		_create_output_lot(
			items_ready,
			attached_fee_ids,
			"process",
			process_id,
			completed_total_minutes
		)
		return true

	add_claimable_output(
		items_ready,
		0,
		"",
		completed_total_minutes,
		-1,
		attached_fee_ids,
		"process",
		process_id
	)

	print("Process output moved to Pending Delivery: ", items_ready)
	return false

func try_deliver_pending_outputs() -> int:
	var delivered_count: int = 0
	while not claimable_outputs.is_empty():
		var entry: Dictionary = claimable_outputs[0]
		var raw_items: Dictionary = entry.get("items", {})
		var pending_items: Dictionary[String, int] = {}
		for item_id_value in raw_items.keys():
			var item_id: String = str(item_id_value)
			var quantity: int = maxi(int(raw_items[item_id_value]), 0)
			if not item_id.is_empty() and quantity > 0:
				pending_items[item_id] = quantity

		if pending_items.is_empty():
			claimable_outputs.remove_at(0)
			continue
		if not try_store_completed_output(pending_items):
			break

		var pending_fee_ids: Array[String] = _to_string_array(
			entry.get("fee_ids", [])
		)
		if (
			pending_fee_ids.is_empty()
			and int(entry.get("service_fee_shekel", 0)) > 0
		):
			var legacy_fee_id: String = _register_unpaid_fee(entry)
			if not legacy_fee_id.is_empty():
				pending_fee_ids.append(legacy_fee_id)

		_create_output_lot(
			pending_items,
			pending_fee_ids,
			str(entry.get("source_type", "")),
			str(entry.get("source_id", "")),
			int(entry.get("completed_total_minutes", 0))
		)
		claimable_outputs.remove_at(0)
		delivered_count += 1

	return delivered_count
