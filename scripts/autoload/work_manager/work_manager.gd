extends Node

# simpan storage sumber per order agar finalize konsisten
var source_item_store_by_order_id: Dictionary[String, Node] = {}
# simpan storage tujuan per order agar output masuk workshop (bukan selalu inventory player)
var output_item_store_by_order_id: Dictionary[String, Node] = {}
# simpan biaya jasa untuk escrow output NPC
var service_fee_by_order: Dictionary[String, int] = {}
var service_fee_currency_by_order: Dictionary[String, String] = {}

var active_orders: Dictionary[String, WorkOrder] = {}
var _last_total_minutes: int = -1
var last_start_job_error: String = ""

func _get_source_item_quantity(source_item_store: Node, item_id: String) -> int:
	if source_item_store == null or item_id.is_empty():
		return 0
	if source_item_store.has_method("get_free_item_quantity"):
		return maxi(
			int(source_item_store.call("get_free_item_quantity", item_id)),
			0
		)

	var source_items: Dictionary = source_item_store.get("items")
	return maxi(int(source_items.get(item_id, 0)), 0)

func on_time_changed(day: int, hour: int, minute: int) -> void:
	var now_total: int = (day * 24 * 60) + (hour * 60) + minute
	if _last_total_minutes < 0:
		_last_total_minutes = now_total
		return

	var delta: int = now_total - _last_total_minutes
	_last_total_minutes = now_total

	if delta <= 0:
		return

	_tick(now_total)

func start_job(
	job: JobData, worker_kind: int, worker_id: String,
	tool: ToolInstance = null, source_item_store: Node = Inventory,
	output_item_store: Node = null, service_fee_amount: int = 0, worker_slot_capacity: int = 1) -> String:
	# tambah argumen storage agar bisa pakai WorkshopStorage

	last_start_job_error = ""

	# fallback aman bila caller lupa mengirim storage
	if source_item_store == null:
		source_item_store = Inventory
	if output_item_store == null:
		# default output diarahkan ke workshop bila ada (sesuai konsep terbaru)
		# output tidak langsung ke Inventory player
		if has_node("/root/WorkShopStorage"):
			output_item_store = get_node("/root/WorkShopStorage") # pakai workshop sebagai tujuan output
		else:
			output_item_store = Inventory # fallback kalau workshop belum ada

	if (
		output_item_store != null and output_item_store.has_method("has_blocking_pending_output")
		and bool(output_item_store.call("has_blocking_pending_output")
			)
		):
			last_start_job_error = ("Workshop blocked: pending output needs storage space.")
			return ""

	var resolved_worker_id: String = _resolve_worker_id(worker_kind, worker_id, job)
	var worker_data: WorkerData = null

	if worker_kind == WorkOrder.Worker_Type.NPC and resolved_worker_id == "":
		if last_start_job_error.is_empty():
			last_start_job_error = "No matching idle worker available."
		return ""

	if worker_kind == WorkOrder.Worker_Type.NPC:
		worker_data = WorkerDatabase.get_worker_data(resolved_worker_id)
		if worker_data == null:
			return ""
		if worker_data.is_working():
			return ""

	for item_identifier in job.inputs.keys():
		var required_quantity: int = int(job.inputs[item_identifier])
		if (
			_get_source_item_quantity(
				source_item_store,
				str(item_identifier)
			)
			< required_quantity
		):
			last_start_job_error = "Not enough %s." % item_identifier
			return ""

	var consumed_inputs: Dictionary[String, int] = {}
	for item_identifier in job.inputs.keys():
		var required_quantity: int = int(job.inputs[item_identifier])
		var removed: bool = bool(
			source_item_store.call(
				"remove_item",
				item_identifier,
				required_quantity
			)
		)
		if not removed:
			for consumed_item_id in consumed_inputs.keys():
				if source_item_store.has_method("add_item"):
					source_item_store.call(
						"add_item",
						consumed_item_id,
						consumed_inputs[consumed_item_id]
					)
			last_start_job_error = "Could not consume %s." % item_identifier
			return ""
		consumed_inputs[str(item_identifier)] = required_quantity

	# 2) tool durability (kalau ada)
	if tool != null and job.required_tool_id != "":
		# validasi id tool cocok(opsional)
		tool.consume(job.tool_durability_loss)

	# 3) buat order
	var order: WorkOrder = WorkOrder.new()
	order.order_id = str(Time.get_ticks_usec())
	order.job_id = job.job_id
	order.job_display_name = job.display_name
	order.job_icon = job.icon
	if worker_data != null:
		worker_data.start_work(order.order_id, job.job_id)

	order.worker_kind = worker_kind
	order.worker_id = resolved_worker_id
	order.worker_slot_capacity = maxi(worker_slot_capacity, 1)

	var start_total: int = _last_total_minutes if _last_total_minutes >= 0 else 0
	order.start_time_total_minutes = start_total
	order.end_time_total_minutes = start_total + max(job.base_duration_minutes, 1)

	order.inputs_snapshot = job.inputs.duplicate(true)
	order.outputs_snapshot = job.outputs.duplicate(true)
	order.current_status = WorkOrder.Status.RUNNING

	active_orders[order.order_id] = order
	# simpan mapping storage per order agar finalize konsisten
	# penting untuk workshop escrow
	source_item_store_by_order_id[order.order_id] = source_item_store # storage sumber
	output_item_store_by_order_id[order.order_id] = output_item_store # storage tujuan
	service_fee_by_order[order.order_id] = max(service_fee_amount, 0)
	service_fee_currency_by_order[order.order_id] = (
		job.workshop_fee_currency_item_id.strip_edges()
	)

	return order.order_id

func _tick(now_total_minutes: int) -> void:
	for order_id in active_orders.keys():
		var order: WorkOrder = active_orders[order_id]
		if order.current_status != WorkOrder.Status.RUNNING:
			continue

		if now_total_minutes >= order.end_time_total_minutes:
			_finalize_order(order_id, order, now_total_minutes)

func _finalize_order(order_id: String, order: WorkOrder, now_total_minutes: int) -> void:
	var job_outputs: Dictionary = order.outputs_snapshot
	# ambil tujuan output
	var output_store: Node = output_item_store_by_order_id.get(order_id, Inventory)
	# ambil biaya jasa
	var fee: int = service_fee_by_order.get(order_id, 0)
	var fee_currency_item_id: String = service_fee_currency_by_order.get(
		order_id,
		"shekel"
	)
	var is_player_worker: bool = (order.worker_kind == WorkOrder.Worker_Type.PLAYER)
	var is_npc_worker: bool = (order.worker_kind == WorkOrder.Worker_Type.NPC)
	var worker_data: WorkerData = null

	# =============================
	# RULE BARU (2026.02.01):
	# PLAYER  -> langsung masuk inventory tujuan, tanpa claimable
	# NPC     -> escrow murni: masuk claimable saja (belum masuk inventory tujuan)
	# =============================

	if is_player_worker:
		# PLAYER: output langsung masuk inventory tujuan
		if output_store != null and output_store.has_method("add_bulk_item"):
			output_store.call("add_bulk_item", job_outputs.duplicate(true))
		else:
			for item_id in job_outputs.keys():
				if output_store != null and output_store.has_method("add_item"):
					output_store.call("add_item", item_id, int(job_outputs[item_id]))
				else:
					Inventory.add_item(item_id, int(job_outputs[item_id]))
	elif is_npc_worker:
		var multiplier: float = 1.0
		var success_chance: float = 1.0
		var reliability_roll: float = randf()
		var reliability_output_multiplier: float = 1.0

		worker_data = WorkerDatabase.get_worker_data(order.worker_id)

		if worker_data:
			multiplier = worker_data.get_satisfaction_work_multiplier()
			success_chance = worker_data.get_reliability_success_chance()

			if reliability_roll > success_chance:
				reliability_output_multiplier = 0.75
			else:
				reliability_output_multiplier = 1.0

		var final_outputs: Dictionary[String, int] = {}

		for item_id in job_outputs.keys():
			var item_id_string: String = str(item_id)
			var base_amount: int = int(job_outputs[item_id_string])
			var final_amount: int = roundi(base_amount * multiplier * reliability_output_multiplier)
			final_outputs[item_id_string] = final_amount

		if (
			output_store != null
			and output_store.has_method("receive_completed_output")
		):
			output_store.call(
				"receive_completed_output",
				final_outputs,
				fee,
				order.worker_id,
				now_total_minutes,
				order.job_id,
				fee_currency_item_id
			)
		elif (
			output_store != null
			and output_store.has_method("add_claimable_output")
		):
			output_store.call(
				"add_claimable_output",
				final_outputs,
				fee,
				order.worker_id,
				now_total_minutes,
				-1
			)
		else:
			for item_id in final_outputs.keys():
				if (
					output_store != null
					and output_store.has_method("add_item")
				):
					output_store.call(
						"add_item",
						item_id,
						int(final_outputs[item_id])
					)
				else:
					Inventory.add_item(
						item_id,
						int(final_outputs[item_id])
					)

	order.current_status = WorkOrder.Status.DONE

	if is_npc_worker:
		worker_data = WorkerDatabase.get_worker_data(order.worker_id)
		if worker_data != null:
			worker_data.finish_work(order.order_id)

	active_orders.erase(order_id)

	# cleanup mapping agar tidak numpuk # penting untuk runtime panjang
	source_item_store_by_order_id.erase(order_id) # hapus sumber
	output_item_store_by_order_id.erase(order_id) # hapus tujuan
	service_fee_by_order.erase(order_id) # hapus fee
	service_fee_currency_by_order.erase(order_id)

func _resolve_worker_id(worker_kind: int, requested_worker_id: String, job: JobData) -> String:
	if worker_kind == WorkOrder.Worker_Type.PLAYER:
		return requested_worker_id

	if worker_kind == WorkOrder.Worker_Type.NPC:
		if WorkerDatabase.has_worker_data(requested_worker_id):
			var worker_data: WorkerData = WorkerDatabase.get_worker_data(requested_worker_id)
			if not _worker_matches_job(worker_data, job):
				last_start_job_error = "Worker Profession doesn't match"
				return ""
			if worker_data.is_working():
				last_start_job_error = "Worker is already working"
				return ""

			return requested_worker_id
		if not WorkerDatabase.has_worker_data(requested_worker_id):
			for worker in WorkerDatabase.get_all_workers():
				if not (worker is WorkerData):
					continue
				var worker_data: WorkerData = worker as WorkerData
				if worker_data.is_working():
					continue
				if not _worker_matches_job(worker_data, job):
					continue

				return worker_data.worker_id

			last_start_job_error = "No matching idle worker available."
			return ""

	last_start_job_error = "Unsupported worker kind."
	return ""

func _worker_matches_job(worker_data: WorkerData, job: JobData) -> bool:
	return worker_data.profession == job.requirement_profession

func get_last_start_job_error() -> String:
	return last_start_job_error

func get_active_progress_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var now_total_minutes: int = max(_last_total_minutes, 0)

	for order_value in active_orders.values():
		var order: WorkOrder = order_value as WorkOrder
		if order == null:
			continue
		if order.current_status != WorkOrder.Status.RUNNING:
			continue

		var duration_minutes: int = max(
			order.end_time_total_minutes - order.start_time_total_minutes,
			1
		)
		var elapsed_minutes: int = clamp(
			now_total_minutes - order.start_time_total_minutes,
			0,
			duration_minutes
		)

		entries.append({
			"source": "work",
			"id": order.order_id,
			"title": order.job_display_name,
			"job_icon": order.job_icon,
			"status_text": "Working",
			"worker_id": order.worker_id,
			"active_worker_count": 1,
			"worker_slot_capacity": order.worker_slot_capacity,
			"progress_ratio": float(elapsed_minutes) / float(duration_minutes),
			"elapsed_minutes": elapsed_minutes,
			"duration_minutes": duration_minutes,
			"remaining_minutes": max(
				order.end_time_total_minutes - now_total_minutes,
				0
			),
			"inputs": order.inputs_snapshot.duplicate(true),
			"outputs": order.outputs_snapshot.duplicate(true)
			})
	return entries
