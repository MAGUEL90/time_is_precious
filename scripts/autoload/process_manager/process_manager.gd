extends Node

# station registry: station_id -> StationState
var stations: Dictionary[String, StationState] = {}

# process registry: process_id -> ProcessData (biar bisa auto-pull dari inventory)
var processes: Dictionary[String, ProcessData] = {}

# weather key disimpan disini (string), supaya ProcessManager tidak tergantung pada TimeComponentManager
var current_weather_key: String = "clear"

# untuk hitung delta waktu dari time_changed (day/hour/minute)
var _last_total_minutes: int = -1

# Auto-pull config: process_id -> batch_size
var _auto_pull_batch_size: Dictionary[String, int] = {}

# storage sumber & tujuan proses (default Inventory) # supaya bisa pakai WorkshopStorage
var source_item_store: Node = Inventory # tempat ambil input auto-pull
var output_item_store: Node = Inventory # tempat taruh output proses

func set_source_item_store(store: Node) -> void:
	source_item_store = store if store != null else Inventory # fallback aman

func set_output_item_store(store: Node) -> void:
	output_item_store = store if store != null else Inventory

func _has_blocking_pending_output() -> bool:
	if output_item_store == null:
		return false

	if not output_item_store.has_method("has_blocking_pending_output"):
		return false

	return bool(output_item_store.call("has_blocking_pending_output"))

func _get_processable_source_quantity(item_id: String) -> int:
	if source_item_store == null or item_id.is_empty():
		return 0

	# Workshop Storage hanya mengizinkan Free Stock.
	if source_item_store.has_method("get_free_item_quantity"):
		return maxi(
			int(
				source_item_store.call(
					"get_free_item_quantity",
					item_id
				)
			),
			0
		)

	# Inventory biasa tidak memiliki Held Output.
	var store_items: Dictionary = source_item_store.get("items")
	return maxi(
		int(store_items.get(item_id, 0)),
		0
	)

func set_weather_key(weather_key: String) -> void:
	current_weather_key = weather_key

func register_station(station_id: String, slots_total: int) -> bool:
	return configure_station(station_id, slots_total)

func configure_station(station_id: String, slots_total: int) -> bool:
	var safe_station_id: String = station_id.strip_edges()
	if safe_station_id.is_empty() or slots_total < 0:
		return false

	var station_state: StationState = (
		stations.get(safe_station_id, null) as StationState
	)
	if slots_total == 0:
		if station_state == null:
			return true
		if not station_state.resize_slots(0):
			return false
		stations.erase(safe_station_id)
		return true

	if station_state == null:
		station_state = StationState.new()
		station_state.setup(safe_station_id, slots_total)
		stations[safe_station_id] = station_state
		return true

	return station_state.resize_slots(slots_total)

func register_process(process_data: ProcessData, auto_pull_from_inventory: bool = false, batch_size: int = 20) -> void:
	processes[process_data.process_id] = process_data
	if auto_pull_from_inventory:
		_auto_pull_batch_size[process_data.process_id] = max(batch_size, 1)

func get_process_availability(process_id: String) -> Dictionary:
	var result: Dictionary = {
		"registered": false,
		"station_ready": false,
		"input_item_id": "",
		"output_item_id": "",
		"available_quantity": 0,
		"free_slots": 0,
		"total_slots": 0,
		"batch_size": 0,
		"startable_quantity": 0,
		"can_start": false,
		"required_batches": 0,
		"station_fee_currency_item_id": "",
		"station_fee_amount": 0,
		"process_display_name": "",
		"required_station_id": "",
		"duration_minutes": 0,
		"blocked_by_pending_output": false
	}

	var process_data: ProcessData = (
		processes.get(process_id, null) as ProcessData
	)
	if process_data == null:
		return result

	result["registered"] = true
	result["process_display_name"] = process_data.display_name
	result["required_station_id"] = process_data.required_station_id
	result["duration_minutes"] = _calc_duration(process_data)
	result["input_item_id"] = process_data.input_item_id
	result["output_item_id"] = process_data.output_item_id
	result["station_fee_currency_item_id"] = (process_data.station_fee_currency_item_id)

	var station_state: StationState = (
		stations.get(
			process_data.required_station_id,
			null
		) as StationState
	)
	if station_state == null:
		return result

	result["station_ready"] = true
	result["total_slots"] = station_state.slots.size()

	var free_slots: int = 0
	for batch_value in station_state.slots:
		if batch_value == null:
			free_slots += 1

	var available_quantity: int = (
		_get_processable_source_quantity(
			process_data.input_item_id
		)
	)
	var safe_batch_size: int = maxi(process_data.batch_size, 1)
	var maximum_startable_quantity: int = mini(
		available_quantity,
		free_slots * safe_batch_size
	)
	var startable_quantity: int = maximum_startable_quantity
	if process_data.requires_full_batch:
		startable_quantity = (
			floori(
				float(maximum_startable_quantity)
				/ float(safe_batch_size)
			)
			* safe_batch_size
		)
	var required_batches: int = 0
	if startable_quantity > 0:
		required_batches = ceili(float(startable_quantity) / float(safe_batch_size))

	var station_fee_amount: int = (required_batches * maxi(process_data.station_fee_per_batch, 0))
	var blocked_by_pending_output: bool = _has_blocking_pending_output()

	result["available_quantity"] = available_quantity
	result["free_slots"] = free_slots
	result["batch_size"] = safe_batch_size
	result["startable_quantity"] = startable_quantity
	result["blocked_by_pending_output"] = blocked_by_pending_output
	result["can_start"] = (startable_quantity > 0 and not blocked_by_pending_output)
	result["required_batches"] = required_batches
	result["station_fee_amount"] = station_fee_amount

	return result

func get_active_progress_entries() -> Array[Dictionary]:
	var grouped_entries: Dictionary = {}

	for station_value in stations.values():
		var station_state: StationState = (station_value as StationState)
		if station_state == null:
			continue

		for batch_value in station_state.slots:
			var batch: ProcessBatch = (batch_value as ProcessBatch)
			if batch == null:
				continue
			if batch.status != ProcessBatch.BatchStatus.RUNNING:
				continue
			var process_data: ProcessData = (processes.get(batch.process_id, null) as ProcessData)
			if process_data == null:
				continue

			var group_key: String = "%s::%s" % [station_state.station_id, batch.process_id]
			var batch_duration_minutes: int = maxi(batch.duration_minutes, 1)
			var batch_elapsed_minutes: int = clampi(batch.progress_minutes, 0, batch_duration_minutes)
			var batch_progress_ratio: float = (float(batch_elapsed_minutes) / float(batch_duration_minutes))
			var batch_remaining_minutes: int = maxi(batch_duration_minutes - batch_elapsed_minutes, 0)

			if not grouped_entries.has(group_key):
				var process_title: String = (process_data.display_name)
				if process_title.is_empty():
					process_title = (batch.process_id.capitalize())
				var process_icon: Texture2D = process_data.icon
				if process_icon == null:
					var output_item_data: ItemData = (
						ItemDatabase.get_item_data(batch.output_item_id)
					)
					if output_item_data != null:
						process_icon = output_item_data.icon

				grouped_entries[group_key] = {
					"source": "process",
					"id": group_key,
					"title": process_title,
					"job_icon": process_icon,
					"status_text": "Processing",
					"station_id": station_state.station_id,
					"active_process_slot_count": 0,
					"process_slot_capacity": station_state.slots.size(),
					"total_quantity": 0,
					"weighted_progress_total": 0.0,
					"remaining_minutes": 0,
					"duration_minutes": 1,
					"input_item_id": batch.input_item_id,
					"output_item_id": batch.output_item_id
				}

			var entry: Dictionary = grouped_entries[group_key]
			entry["active_process_slot_count"] = (
				int(entry["active_process_slot_count"]) + 1
			)
			entry["total_quantity"] = (
				int(entry["total_quantity"]) + batch.quantity
			)
			entry["weighted_progress_total"] = (
				float(entry["weighted_progress_total"])
				+ (
					batch_progress_ratio
					* float(batch.quantity)
				)
			)
			entry["remaining_minutes"] = maxi(
				int(entry["remaining_minutes"]),
				batch_remaining_minutes
			)
			entry["duration_minutes"] = maxi(
				int(entry["duration_minutes"]),
				batch_duration_minutes
			)

			grouped_entries[group_key] = entry

	var progress_entries: Array[Dictionary] = []
	for entry_value in grouped_entries.values():
		var group_entry: Dictionary = entry_value
		var group_total_quantity: int = maxi(int(group_entry["total_quantity"]), 1)
		var group_progress_ratio: float = clampf(float(group_entry["weighted_progress_total"]) / float(group_total_quantity), 0.0, 1.0)
		var group_duration_minutes: int = maxi(int(group_entry["duration_minutes"]), 1)
		group_entry["progress_ratio"] = group_progress_ratio
		group_entry["elapsed_minutes"] = clampi(roundi(group_progress_ratio * float(group_duration_minutes)), 0, group_duration_minutes)
		var input_snapshot: Dictionary = {}
		var input_item_id: String = str(group_entry["input_item_id"])
		if not input_item_id.is_empty():
			input_snapshot[input_item_id] = (group_total_quantity)
		var output_snapshot: Dictionary = {}
		var output_item_id: String = str(group_entry["output_item_id"])
		if not output_item_id.is_empty():
			output_snapshot[output_item_id] = (group_total_quantity)

		group_entry["inputs"] = input_snapshot
		group_entry["outputs"] = output_snapshot
		group_entry.erase("weighted_progress_total")
		group_entry.erase("input_item_id")
		group_entry.erase("output_item_id")

		progress_entries.append(group_entry)

	return progress_entries

# Panggil ini dari TimeComponentManager.time_changed (atau dari tempat lain) dengan total minute sekarang

func on_time_changed(day: int, hour: int, minute: int) -> void:
	var now_total: int = (day * 24 * 60) + (hour * 60) + minute
	if _last_total_minutes < 0:
		_last_total_minutes = now_total
		return

	var delta: int = now_total - _last_total_minutes
	_last_total_minutes = now_total

	if delta <= 0:
		return

	_tick(delta)


func _tick(delta_minutes: int) -> void:

	# 1) Progress semua batch yang sedang Running
	for station_id in stations.keys():
		var st: StationState = stations[station_id]
		for i in range(st.slots.size()):
			var batch: ProcessBatch = st.slots[i]
			if batch == null:
				continue
			if batch.status != ProcessBatch.BatchStatus.RUNNING:
				continue

			batch.progress_minutes += delta_minutes

			if batch.progress_minutes >= batch.duration_minutes:
				_finalize_batch(st, i, batch)

	# 2) Auto-pull dari inventory kalau ada slot kosong
	_try_auto_pull()

# Dipanggil dari WorkShopStorage saat player pilih "lanjut proses"
func request_auto_pull() -> void:
	_try_auto_pull()

func can_start_registered_process(
	process_id: String,
	quantity: int,
	batch_size: int = 20) -> bool:
	if quantity <= 0:
		return false

	if _has_blocking_pending_output():
		return false

	var process_data: ProcessData = (
		processes.get(process_id, null) as ProcessData
	)
	if process_data == null:
		return false
	if process_data.requires_full_batch and quantity % maxi(process_data.batch_size, 1) != 0:
		return false
	if _get_processable_source_quantity(process_data.input_item_id) < quantity:
		return false

	var station_state: StationState = (
		stations.get(process_data.required_station_id, null) as StationState
		)
	if station_state == null:
		return false

	var safe_batch_size: int = maxi(batch_size, 1)
	var required_slots: int = ceili(
		float(quantity) / float(safe_batch_size)
	)
	var available_slots: int = 0
	for batch_value in station_state.slots:
		if batch_value == null:
			available_slots += 1

	return available_slots >= required_slots

func _consume_source_item_for_process(item_id: String, quantity: int) -> Dictionary:
	var inherited_fee_ids: Array[String] = []
	var result: Dictionary = {"success": false, "fee_ids": inherited_fee_ids}

	if source_item_store == null or quantity <= 0:
		return result

	if source_item_store.has_method("consume_item_for_process"):
		var storage_result: Dictionary = source_item_store.call(
			"consume_item_for_process",
			item_id,
			quantity
		)
		if not bool(storage_result.get("success", false)):
			return result

		for fee_id_value in storage_result.get("fee_ids", []):
			var fee_id: String = str(fee_id_value).strip_edges()
			if (not fee_id.is_empty() and not inherited_fee_ids.has(fee_id)):
				inherited_fee_ids.append(fee_id)

		result["success"] = true
		result["fee_ids"] = inherited_fee_ids
		return result

	if not source_item_store.has_method("remove_item"):
		return result

	result["success"] = bool(
		source_item_store.call(
			"remove_item", item_id, quantity
		)
	)

	return result


func start_registered_process(
	process_id: String,
	quantity: int
) -> bool:
	if quantity <= 0:
		return false

	if _has_blocking_pending_output():
		print("Process blocked: Workshop has pending output.")
		return false

	var process_data: ProcessData = (
		processes.get(process_id, null) as ProcessData
	)
	if process_data == null:
		print("Process not Registered: ", process_id)
		return false

	var station_state: StationState = (
		stations.get(process_data.required_station_id, null) as StationState
	)
	if station_state == null:
		print("Required station not registered: ", process_data.required_station_id)
		return false

	var safe_batch_size: int = maxi(process_data.batch_size, 1)
	if (
		process_data.requires_full_batch
		and quantity % safe_batch_size != 0
	):
		print(
			"Process requires full batches of ",
			safe_batch_size,
			": ",
			process_data.process_id
		)
		return false

	var required_slots: int = ceili(
		float(quantity) / float(safe_batch_size)
	)
	var free_slot_indices: Array[int] = []
	for slot_index in range(station_state.slots.size()):
		if station_state.slots[slot_index] == null:
			free_slot_indices.append(slot_index)

	if free_slot_indices.size() < required_slots:
		print(
			"Not enough station slot for process",
			required_slots,
			", available: ",
			free_slot_indices.size()
		)
		return false

	if source_item_store == null:
		print("Process source storage unavailable.")
		return false

	if (not source_item_store.has_method("consume_item_for_process")
		and not source_item_store.has_method("remove_item")):

		print("Process source storage cannot consume items.")
		return false

	var available_input_quantity: int = (
		_get_processable_source_quantity(
			process_data.input_item_id
		)
	)

	if available_input_quantity < quantity:
		print("Not enough process input: ", process_data.input_item_id, " x", quantity)
		return false

	var remaining_quantity: int = quantity

	for slot_index in free_slot_indices:
		if remaining_quantity <= 0:
			break

		var batch_quantity: int = mini(
			safe_batch_size,
			remaining_quantity
		)
		var consume_result: Dictionary = (
			_consume_source_item_for_process(process_data.input_item_id, batch_quantity)
		)
		if not bool(consume_result.get("success", false)):
			push_error("Process input failed while creating batch: %s x%d"
			% [process_data.input_item_id, batch_quantity])
			return false

		var inherited_fee_ids: Array[String] = []
		for fee_id_value in consume_result.get("fee_ids", []):
			var fee_id: String = str(fee_id_value).strip_edges()
			if(not fee_id.is_empty() and not inherited_fee_ids.has(fee_id)):
				inherited_fee_ids.append(fee_id)

		var batch_started: bool = _start_batch(
			process_data,
			batch_quantity,
			station_state,
			slot_index,
			inherited_fee_ids
		)
		if not batch_started:
			if source_item_store.has_method("add_item"):
				source_item_store.call(
					"add_item",
					process_data.input_item_id,
					batch_quantity
				)
			return false
		remaining_quantity -= batch_quantity

	return remaining_quantity == 0


func _try_auto_pull() -> void:

	if _has_blocking_pending_output():
		return

	# Auto-pull hanya untuk proses yang kamu set register_process(..., auto_pull = true)
	for process_id in _auto_pull_batch_size.keys():
		var process_dt: ProcessData = processes.get(process_id, null)
		if process_dt == null:
			continue

		var station_st: StationState = stations.get(process_dt.required_station_id, null)
		if station_st == null:
			continue

		var configured_batch_size: int = maxi(
			int(_auto_pull_batch_size[process_id]),
			1
		)
		var batch_size: int = configured_batch_size
		if process_dt.requires_full_batch:
			batch_size = maxi(process_dt.batch_size, 1)

		while true:
			var free_slot: int = station_st.find_free_slot()
			if free_slot == -1:
				break

			var available: int = _get_processable_source_quantity(
				process_dt.input_item_id
			)

			if available <= 0:
				break
			if process_dt.requires_full_batch and available < batch_size:
				break

			var take_qty: int = mini(batch_size, available)
			var consume_result: Dictionary = _consume_source_item_for_process(
				process_dt.input_item_id,
				take_qty
			)
			if not bool(consume_result.get("success", false)):
				break

			if not _start_batch(process_dt, take_qty, station_st, free_slot):
				if source_item_store.has_method("add_item"):
					source_item_store.call(
						"add_item",
						process_dt.input_item_id,
						take_qty
					)
				break

func _start_batch(
	process_dt: ProcessData,
	qty: int,
	station_st: StationState,
	slot_idx: int,
	inherited_fee_ids: Array[String] = []
) -> bool:
	if slot_idx < 0 or slot_idx >= station_st.slots.size():
		return false
	if station_st.slots[slot_idx] != null:
		return false

	var batch: ProcessBatch = ProcessBatch.new()
	batch.batch_id = str(Time.get_ticks_usec())
	batch.process_id = process_dt.process_id
	batch.input_item_id = process_dt.input_item_id
	batch.output_item_id = process_dt.output_item_id
	batch.quantity = qty
	batch.start_total_time_minutes = _last_total_minutes
	batch.duration_minutes = _calc_duration(process_dt)
	batch.progress_minutes = 0
	batch.slot_index = slot_idx
	batch.status = ProcessBatch.BatchStatus.RUNNING
	batch.fee_ids = inherited_fee_ids.duplicate()

	var station_fee_amount: int = maxi(
		process_dt.station_fee_per_batch,
		0
	)
	if station_fee_amount > 0:
		var station_fee_id: String = ""
		if (
			output_item_store != null
			and output_item_store.has_method(
				"register_process_station_fee"
			)
		):
			station_fee_id = str(
				output_item_store.call(
					"register_process_station_fee",
					process_dt.process_id,
					station_fee_amount,
					process_dt.station_fee_currency_item_id
				)
			)

		if station_fee_id.is_empty():
			push_error(
				"Process batch rejected: station fee was not registered: %s"
				% process_dt.process_id
			)
			return false
		if not batch.fee_ids.has(station_fee_id):
			batch.fee_ids.append(station_fee_id)

	station_st.set_slot(slot_idx, batch)

	print("Start_Batch qty = ", qty, ", slot = ", slot_idx, ", Batch_Status =  ", batch.status)
	return true

func _calc_duration(process_dt: ProcessData) -> int:
	var base: int = max(process_dt.base_duration_minutes, 1)
	var multiplier: float = 1.0

	if process_dt.weather_speed_multiplier.has(current_weather_key):
		multiplier = float(process_dt.weather_speed_multiplier[current_weather_key])  # 1.0 = normal, 1.4 = lebih lama, dst

	return int(ceil(base * multiplier)) # mult > 1 berarti lebih lama

func _finalize_batch(station_st: StationState, slot_idx: int, batch: ProcessBatch) -> void:
	# failure chance (opsional)
	var failed: bool = false
	var process_dt: ProcessData = processes.get(batch.process_id, null)
	if process_dt != null and process_dt.failure_chance_by_weather.has(current_weather_key):
		var chance: float = float(process_dt.failure_chance_by_weather[current_weather_key])
		if chance > 0.0 and randf() < chance:
			failed = true

	if failed:
		batch.status = ProcessBatch.BatchStatus.FAILED
		if (
			output_item_store != null
			and output_item_store.has_method("cancel_inactive_fees")
		):
			output_item_store.call(
				"cancel_inactive_fees",
				batch.fee_ids
			)
		# Untuk MVP: kalau gagal, input dianggap hilang (sudah di-consume).
		# Kamu bisa ubah nanti: sebagian kembali, atau jadi item "cracked_brick".
	else:
		batch.status = ProcessBatch.BatchStatus.DONE
		var completed_outputs: Dictionary[String, int] = {}
		completed_outputs[batch.output_item_id] = batch.quantity

		if (
			output_item_store != null
			and output_item_store.has_method(
				"receive_completed_process_output"
			)
		):
			output_item_store.call(
				"receive_completed_process_output",
				completed_outputs,
				batch.fee_ids,
				batch.process_id,
				maxi(_last_total_minutes, 0)
			)
		elif output_item_store != null and output_item_store.has_method("add_item"):
			output_item_store.call(
				"add_item",
				batch.output_item_id,
				batch.quantity
			)
		else:
			Inventory.add_item(
				batch.output_item_id,
				batch.quantity
			)


	station_st.clear_slot(slot_idx)
