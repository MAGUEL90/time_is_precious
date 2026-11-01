extends Node

signal transaction_finished

const SHAPING_JOB_ID: String = "mudbrick_make"
const SHAPING_SHIFT_START: int = 7 * 60
const SHAPING_SHIFT_END: int = 15 * 60
const MINUTES_PER_DAY: int = 24 * 60
const PLOT_PRESENCE_PATH: String = "res://scenes/workshop_plot/workshop_worker_presence.gd"

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
var _transaction_busy: bool = false

func is_transaction_busy() -> bool:
	return _transaction_busy

func _finish_transaction() -> void:
	_transaction_busy = false
	transaction_finished.emit()

func _ready() -> void:
	_bind_payroll.call_deferred()

func _bind_payroll() -> void:
	if not WorkerDatabase.payroll_settling.is_connected(_flush_payroll_boundary):
		WorkerDatabase.payroll_settling.connect(_flush_payroll_boundary)

func _flush_payroll_boundary() -> void:
	on_time_changed(TimeComponentManager.current_day, TimeComponentManager.current_hour, TimeComponentManager.current_minute)

func settle_resignation_boundary() -> void:
	# Call before applying the Satisfaction change so work ending at this instant
	# is completed with the worker's previous entitlement and Satisfaction.
	_flush_payroll_boundary()

func pause_orders_for_worker(worker_id: String) -> Array[String]:
	if _transaction_busy:
		return []
	# A payroll/needs boundary may already have finished an order. Recheck after
	# the flush and leave completed output and its fee alone.
	settle_resignation_boundary()
	if _transaction_busy:
		return []
	var has_running_order: bool = false
	for order: WorkOrder in active_orders.values():
		if order.worker_kind == WorkOrder.Worker_Type.NPC and order.current_status == WorkOrder.Status.RUNNING and order.worker_id == worker_id:
			has_running_order = true
			break
	if not has_running_order:
		return []
	_transaction_busy = true
	var paused: Array[String] = []
	for order: WorkOrder in active_orders.values():
		if order.worker_kind != WorkOrder.Worker_Type.NPC or order.current_status != WorkOrder.Status.RUNNING or order.worker_id != worker_id:
			continue
		order.current_status = WorkOrder.Status.QUEUED
		order.worker_id = ""
		var worker: WorkerData = WorkerDatabase.get_worker_data(worker_id)
		if worker != null:
			worker.finish_work(order.order_id)
		paused.append(order.order_id)
	_finish_transaction()
	return paused

func resume_paused_order(order_id: String, worker_id: String, job: JobData, plot_id: String, bind_approach: Callable = Callable()) -> bool:
	if _transaction_busy:
		last_start_job_error = "Another work transaction is in progress."
		return false
	last_start_job_error = ""
	settle_resignation_boundary()
	if _transaction_busy:
		last_start_job_error = "Another work transaction is in progress."
		return false
	_transaction_busy = true
	var resumed: bool = _resume_paused_order(order_id, worker_id, job, plot_id, bind_approach)
	_finish_transaction()
	return resumed

func _resume_paused_order(order_id: String, worker_id: String, job: JobData, plot_id: String, bind_approach: Callable) -> bool:
	var order: WorkOrder = active_orders.get(order_id)
	if order == null or order.current_status != WorkOrder.Status.QUEUED or order.worker_kind != WorkOrder.Worker_Type.NPC or not order.worker_id.is_empty():
		last_start_job_error = "This work is no longer waiting for a worker."
		return false
	var previous_plot: String = str(order.get_meta("visual_plot_id", ""))
	if (not previous_plot.is_empty() and previous_plot != plot_id) or (previous_plot.is_empty() and (plot_id.is_empty() or not bind_approach.is_valid())) or job == null or order.job_id != job.job_id:
		last_start_job_error = "This work belongs to another workshop."
		return false
	var worker: WorkerData = WorkerDatabase.get_worker_data(worker_id)
	if worker == null or worker.is_reserved() or worker.current_work_status != WorkerData.WorkStatus.IDLE:
		last_start_job_error = "Worker unavailable."
		return false
	if worker.is_payroll_blocked():
		last_start_job_error = worker.get_onboarding_status()
		return false
	if worker.resignation_pending or worker.get_resolved_satisfaction() <= 0.0 or not _worker_matches_job(worker, job):
		last_start_job_error = "Choose an eligible worker with the required profession."
		return false
	if not WorkerDatabase.assign_worker(worker_id):
		last_start_job_error = "Worker unavailable."
		return false
	# Keep the original order, source, output destination, snapshots and fee.
	order.worker_id = worker_id
	worker.start_work(order.order_id, order.job_id)
	order.current_status = WorkOrder.Status.RUNNING
	if bind_approach.is_valid():
		bind_approach.call(order_id, worker_id)
	return true

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

func is_shaping_order(order: WorkOrder) -> bool:
	return order != null and order.worker_kind == WorkOrder.Worker_Type.NPC and order.job_id == SHAPING_JOB_ID

func is_shaping_shift(order: WorkOrder, total_minutes: int) -> bool:
	if not is_shaping_order(order):
		return false
	var minute: int = total_minutes % MINUTES_PER_DAY
	return minute >= SHAPING_SHIFT_START and minute < SHAPING_SHIFT_END

func _end_shaping_shift(worker: WorkerData, order: WorkOrder) -> void:
	# Load at runtime: the presence script itself observes WorkManager orders.
	var presence: Script = load(PLOT_PRESENCE_PATH)
	if presence != null and presence.has_method("end_shift_for_worker"):
		presence.call("end_shift_for_worker", worker, "plot", order.order_id, str(order.get_meta("visual_plot_id", "")))

func _shift_minutes_before(total_minutes: int) -> int:
	var day: int = total_minutes / MINUTES_PER_DAY
	var minute: int = total_minutes % MINUTES_PER_DAY
	return day * (SHAPING_SHIFT_END - SHAPING_SHIFT_START) + clampi(minute - SHAPING_SHIFT_START, 0, SHAPING_SHIFT_END - SHAPING_SHIFT_START)

func _shift_completion_time(start: int, work_minutes: int) -> int:
	var day: int = start / MINUTES_PER_DAY
	var minute: int = start % MINUTES_PER_DAY
	if minute < SHAPING_SHIFT_START:
		minute = SHAPING_SHIFT_START
	elif minute >= SHAPING_SHIFT_END:
		day += 1
		minute = SHAPING_SHIFT_START
	var left_today: int = SHAPING_SHIFT_END - minute
	if work_minutes <= left_today:
		return day * MINUTES_PER_DAY + minute + work_minutes
	var after_today: int = work_minutes - left_today - 1
	var full_day: int = SHAPING_SHIFT_END - SHAPING_SHIFT_START
	return (day + 1 + after_today / full_day) * MINUTES_PER_DAY + SHAPING_SHIFT_START + (after_today % full_day) + 1

func _shaping_window(worker: WorkerData, order: WorkOrder, previous: int, now_total: int) -> Dictionary:
	if str(order.get_meta("visual_plot_id", "")).is_empty() and worker.physical_approach.is_empty():
		# An old unlocated order has no route to invalidate. Preserve its prior
		# inside interpretation while counting only paid daily shift intervals.
		var paid_from: int = previous
		var paid_to: int = now_total
		if worker.payroll_start_day >= 0:
			if worker.payroll_paid_from_day < 0:
				return {"worked": 0, "start": previous, "unlocated": true}
			paid_from = maxi(paid_from, worker.get_paid_start_minute())
			paid_to = mini(paid_to, worker.get_paid_end_minute())
		var worked: int = maxi(0, _shift_minutes_before(paid_to) - _shift_minutes_before(paid_from)) if paid_to > paid_from else 0
		return {"worked": worked, "start": paid_from, "unlocated": true}
	# One physical arrival can grant work only through the end of its first
	# shift. A later shift needs a fresh arrival even after a large clock jump.
	var eligible_from: int = previous
	if not worker.physical_approach.is_empty():
		if not worker.matches_physical_approach("plot", order.order_id, str(order.get_meta("visual_plot_id", ""))) or not worker.physical_approach.arrived:
			return {"worked": 0, "start": previous}
		eligible_from = maxi(eligible_from, int(worker.physical_approach.arrival_minute))
	var day_start: int = (eligible_from / MINUTES_PER_DAY) * MINUTES_PER_DAY
	var shift_start: int = day_start + SHAPING_SHIFT_START
	var shift_end: int = day_start + SHAPING_SHIFT_END
	if eligible_from >= shift_end:
		shift_start += MINUTES_PER_DAY
		shift_end += MINUTES_PER_DAY
	var work_from: int = maxi(eligible_from, shift_start)
	var work_to: int = mini(now_total, shift_end)
	if work_to <= work_from:
		return {"worked": 0, "start": work_from}
	var paid_from: int = work_from
	if worker.payroll_start_day >= 0 and worker.payroll_paid_from_day >= 0:
		paid_from = maxi(paid_from, worker.get_paid_start_minute())
	return {"worked": worker.get_arrived_paid_minutes(work_from, work_to, "plot", order.order_id, str(order.get_meta("visual_plot_id", ""))), "start": paid_from}

func on_time_changed(day: int, hour: int, minute: int) -> void:
	if _transaction_busy:
		return
	var now_total: int = (day * 24 * 60) + (hour * 60) + minute
	if _last_total_minutes < 0:
		_last_total_minutes = now_total
		return

	var delta: int = now_total - _last_total_minutes
	var previous: int = _last_total_minutes
	_last_total_minutes = now_total

	if delta <= 0:
		return

	var completed_at: Dictionary = {}
	var shifts_ended: Array[Dictionary] = []
	for order: WorkOrder in active_orders.values():
		if order.worker_kind != WorkOrder.Worker_Type.NPC:
			continue
		if order.current_status == WorkOrder.Status.QUEUED and order.worker_id.is_empty():
			order.start_time_total_minutes += delta
			order.end_time_total_minutes += delta
			continue
		if order.current_status != WorkOrder.Status.RUNNING:
			continue
		var worker: WorkerData = WorkerDatabase.get_worker_data(order.worker_id)
		if worker == null or worker.current_order_id != order.order_id:
			# A missing or reassigned worker must never advance an orphan order.
			order.start_time_total_minutes += delta
			order.end_time_total_minutes += delta
			continue
		if worker.resignation_pending or worker.get_resolved_satisfaction() <= 0.0:
			# A transaction may have queued resignation for the next safe callback.
			# Do not credit the worker while that callback is waiting.
			order.start_time_total_minutes += delta
			order.end_time_total_minutes += delta
			continue
		var owner: String = str(order.get_meta("visual_plot_id", ""))
		var worked: int = 0
		if is_shaping_order(order):
			# A newly started or old loaded order may first be observed after shift.
			# Invalidate an earlier arrival before allowing the next morning's work.
			if not is_shaping_shift(order, previous) and (worker.physical_approach.is_empty() or (worker.physical_approach.get("arrived", false) and int(worker.physical_approach.get("arrival_minute", -1)) <= previous)):
				_end_shaping_shift(worker, order)
			var window: Dictionary = _shaping_window(worker, order, previous, now_total)
			worked = int(window.worked)
			var remaining: int = maxi(order.end_time_total_minutes - previous, 1)
			if worked >= remaining:
				completed_at[order.order_id] = _shift_completion_time(int(window.start), remaining) if bool(window.get("unlocated", false)) else int(window.start) + remaining
			var shift_end: int = (previous / MINUTES_PER_DAY) * MINUTES_PER_DAY + SHAPING_SHIFT_END
			if previous >= shift_end:
				shift_end += MINUTES_PER_DAY
			if now_total >= shift_end:
				shifts_ended.append({"order": order, "worker": worker})
			# Old direct orders have no authored plot or route. Preserve their
			# historical inside-plot interpretation while reflecting the shift.
			if owner.is_empty() and worker.physical_approach.is_empty():
				worker.current_work_status = WorkerData.WorkStatus.WORKING if is_shaping_shift(order, now_total) and not worker.is_payroll_blocked() else WorkerData.WorkStatus.RESTING
		else:
			worked = worker.get_arrived_paid_minutes(previous, now_total, "plot", order.order_id, owner)
		var unpaid: int = delta - worked
		# Shift both endpoints: remaining work and progress ratio stay unchanged.
		order.start_time_total_minutes += unpaid
		order.end_time_total_minutes += unpaid
	_tick(now_total, completed_at)
	for entry: Dictionary in shifts_ended:
		var order: WorkOrder = entry.order
		var worker: WorkerData = entry.worker
		if active_orders.get(order.order_id) == order and order.current_status == WorkOrder.Status.RUNNING and WorkerDatabase.get_worker_data(order.worker_id) == worker:
			_end_shaping_shift(worker, order)

func start_job(
	job: JobData, worker_kind: int, worker_id: String,
	tool: ToolInstance = null, source_item_store: Node = Inventory,
	output_item_store: Node = null, service_fee_amount: int = 0, worker_slot_capacity: int = 1,
	bind_approach: Callable = Callable()) -> String:
	if _transaction_busy:
		last_start_job_error = "Another work transaction is in progress."
		return ""
	_transaction_busy = true
	var order_id: String = _start_job_transaction(job, worker_kind, worker_id, tool, source_item_store, output_item_store, service_fee_amount, worker_slot_capacity, bind_approach)
	_finish_transaction()
	return order_id

func _start_job_transaction(
	job: JobData, worker_kind: int, worker_id: String, tool: ToolInstance,
	source_item_store: Node, output_item_store: Node, service_fee_amount: int,
	worker_slot_capacity: int, bind_approach: Callable) -> String:
	# tambah argumen storage agar bisa pakai WorkshopStorage

	last_start_job_error = ""
	if job == null:
		last_start_job_error = "No job selected."
		return ""

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
		if worker_data.is_reserved():
			return ""

	var input_snapshot: Dictionary = job.inputs.duplicate(true)
	for item_identifier in input_snapshot.keys():
		var required_quantity: int = int(input_snapshot[item_identifier])
		if (
			_get_source_item_quantity(
				source_item_store,
				str(item_identifier)
			)
			< required_quantity
		):
			last_start_job_error = "Not enough %s." % item_identifier
			return ""

	var atomic_source: bool = source_item_store == Inventory or source_item_store == WorkShopStorage
	if not atomic_source and (not source_item_store.has_method("remove_item") or not source_item_store.has_method("add_item")):
		last_start_job_error = "Work storage cannot return interrupted inputs."
		return ""
	var order: WorkOrder = WorkOrder.new()
	order.order_id = str(Time.get_ticks_usec())
	order.job_id = job.job_id
	order.job_display_name = job.display_name
	order.job_icon = job.icon
	if worker_data != null:
		worker_data.start_work(order.order_id, order.job_id)
	var consumed_inputs: Dictionary[String, int] = {}
	for item_identifier in input_snapshot.keys():
		var required_quantity: int = int(input_snapshot[item_identifier])
		var removed: bool = true
		if atomic_source:
			# The two native stores have ordinary item dictionaries. Commit all
			# removals before emitting Inventory's one change notification.
			if required_quantity > 0:
				var items: Dictionary = source_item_store.get("items")
				var remaining: int = int(items.get(item_identifier, 0)) - required_quantity
				if remaining <= 0:
					items.erase(item_identifier)
				else:
					items[item_identifier] = remaining
		else:
			removed = bool(source_item_store.call("remove_item", item_identifier, required_quantity))
		if removed and required_quantity > 0:
			consumed_inputs[str(item_identifier)] = required_quantity
		if not removed or not _start_worker_still_eligible(worker_data, resolved_worker_id, order.order_id, job):
			_restore_start_inputs(source_item_store, consumed_inputs, atomic_source)
			if worker_data != null:
				worker_data.finish_work(order.order_id)
			last_start_job_error = "Worker or materials changed; work was not started."
			return ""

	# 2) tool durability (kalau ada)
	if tool != null and job.required_tool_id != "":
		# validasi id tool cocok(opsional)
		tool.consume(job.tool_durability_loss)

	order.worker_kind = worker_kind
	order.worker_id = resolved_worker_id
	order.worker_slot_capacity = maxi(worker_slot_capacity, 1)

	var start_total: int = _last_total_minutes if _last_total_minutes >= 0 else 0
	order.start_time_total_minutes = start_total
	order.end_time_total_minutes = start_total + max(job.base_duration_minutes, 1)

	order.inputs_snapshot = input_snapshot
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
	if bind_approach.is_valid():
		bind_approach.call(order.order_id, resolved_worker_id)
	if worker_data != null and is_shaping_order(order) and str(order.get_meta("visual_plot_id", "")).is_empty() and worker_data.physical_approach.is_empty() and not is_shaping_shift(order, start_total):
		worker_data.current_work_status = WorkerData.WorkStatus.RESTING
	# A native inventory observer sees a fully published order, never a partial
	# removal. WorkManager and save/clock callers remain guarded during callbacks.
	if source_item_store == Inventory and not consumed_inputs.is_empty():
		Inventory.items_changed.emit()
	last_start_job_error = ""

	return order.order_id

func _start_worker_still_eligible(worker: WorkerData, worker_id: String, order_id: String, job: JobData) -> bool:
	if worker == null:
		return true # Player work has no WorkerData.
	return WorkerDatabase.get_worker_data(worker_id) == worker and worker.current_order_id == order_id and not worker.resignation_pending and worker.get_resolved_satisfaction() > 0.0 and not worker.is_payroll_blocked() and _worker_matches_job(worker, job)

func _restore_start_inputs(source: Node, consumed: Dictionary[String, int], atomic_source: bool) -> void:
	for item_id: String in consumed:
		if atomic_source:
			var items: Dictionary = source.get("items")
			items[item_id] = int(items.get(item_id, 0)) + int(consumed[item_id])
		else:
			source.call("add_item", item_id, int(consumed[item_id]))

func _tick(now_total_minutes: int, completed_at: Dictionary = {}) -> void:
	for order_id in active_orders.keys():
		var order: WorkOrder = active_orders.get(order_id)
		if order == null or order.current_status != WorkOrder.Status.RUNNING:
			continue
		if order.worker_kind == WorkOrder.Worker_Type.NPC:
			var worker: WorkerData = WorkerDatabase.get_worker_data(order.worker_id)
			if worker == null or worker.current_order_id != order.order_id or worker.resignation_pending or worker.get_resolved_satisfaction() <= 0.0:
				continue
		if is_shaping_order(order) and not completed_at.has(order_id):
			continue

		if now_total_minutes >= order.end_time_total_minutes:
			_finalize_order(order_id, order, int(completed_at.get(order_id, now_total_minutes)))

func _finalize_order(order_id: String, order: WorkOrder, now_total_minutes: int) -> void:
	if _transaction_busy or active_orders.get(order_id) != order or order.current_status != WorkOrder.Status.RUNNING:
		return
	_transaction_busy = true
	_finalize_order_transaction(order_id, order, now_total_minutes)
	_finish_transaction()

func _finalize_order_transaction(order_id: String, order: WorkOrder, now_total_minutes: int) -> void:
	# Output receipt can notify other systems. Mark the order first so a
	# synchronous callback cannot finish or pause this batch a second time.
	order.current_status = WorkOrder.Status.DONE
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

		worker_data = WorkerDatabase.get_worker_data(order.worker_id)

		if worker_data:
			multiplier = worker_data.get_satisfaction_work_multiplier()

		var final_outputs: Dictionary[String, int] = {}

		for item_id in job_outputs.keys():
			var item_id_string: String = str(item_id)
			var base_amount: int = int(job_outputs[item_id_string])
			var final_amount: int = roundi(base_amount * multiplier)
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

	if is_npc_worker:
		worker_data = WorkerDatabase.get_worker_data(order.worker_id)
		if worker_data != null and worker_data.current_order_id == order.order_id:
			worker_data.finish_work(order.order_id)
			# Workshop selections belong to the live scene and are not saved. If
			# its owner disappeared during travel/Continue, do not leave a phantom
			# ASSIGNED citizen after the reservation has ended.
			if not _has_live_workshop_selection(order.worker_id):
				WorkerDatabase.unassign_worker(order.worker_id)

	active_orders.erase(order_id)

	# cleanup mapping agar tidak numpuk # penting untuk runtime panjang
	source_item_store_by_order_id.erase(order_id) # hapus sumber
	output_item_store_by_order_id.erase(order_id) # hapus tujuan
	service_fee_by_order.erase(order_id) # hapus fee
	service_fee_currency_by_order.erase(order_id)

func _has_live_workshop_selection(worker_id: String) -> bool:
	var pending: Array[Node] = [get_tree().root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.is_queued_for_deletion():
			continue
		if node is WorkShop and (node as WorkShop).assigned_worker_ids.has(worker_id):
			return true
		pending.append_array(node.get_children())
	return false

func _resolve_worker_id(worker_kind: int, requested_worker_id: String, job: JobData) -> String:
	if worker_kind == WorkOrder.Worker_Type.PLAYER:
		return requested_worker_id

	if worker_kind == WorkOrder.Worker_Type.NPC:
		if WorkerDatabase.has_worker_data(requested_worker_id):
			var worker_data: WorkerData = WorkerDatabase.get_worker_data(requested_worker_id)
			if worker_data.resignation_pending or worker_data.get_resolved_satisfaction() <= 0.0:
				last_start_job_error = "Worker unavailable."
				return ""
			if worker_data.is_payroll_blocked():
				last_start_job_error = worker_data.get_onboarding_status()
				return ""
			if not _worker_matches_job(worker_data, job):
				last_start_job_error = "Worker Profession doesn't match"
				return ""
			if worker_data.is_reserved():
				last_start_job_error = "Worker is already working"
				return ""

			return requested_worker_id
		if not WorkerDatabase.has_worker_data(requested_worker_id):
			for worker in WorkerDatabase.get_all_workers():
				if not (worker is WorkerData):
					continue
				var worker_data: WorkerData = worker as WorkerData
				if worker_data.is_reserved() or worker_data.is_payroll_blocked() or worker_data.resignation_pending or worker_data.get_resolved_satisfaction() <= 0.0:
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
		var waiting_for_worker: bool = order.current_status == WorkOrder.Status.QUEUED and order.worker_kind == WorkOrder.Worker_Type.NPC and order.worker_id.is_empty()
		if order.current_status != WorkOrder.Status.RUNNING and not waiting_for_worker:
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

		var worker: WorkerData = WorkerDatabase.get_worker_data(order.worker_id) if order.worker_kind == WorkOrder.Worker_Type.NPC else null
		var payroll_paused: bool = worker != null and worker.is_payroll_blocked()
		var leaving: bool = worker != null and (worker.resignation_pending or worker.get_resolved_satisfaction() <= 0.0)
		var travelling: bool = worker != null and not worker.physical_approach.is_empty() and not worker.physical_approach.get("arrived", false)
		var off_shift: bool = is_shaping_order(order) and not is_shaping_shift(order, now_total_minutes)
		entries.append({
			"source": "work",
			"id": order.order_id,
			"title": order.job_display_name,
			"job_icon": order.job_icon,
			"status_text": "Waiting for worker" if waiting_for_worker else ("Leaving" if leaving else ("Waiting for city payment" if payroll_paused else ("Resting until 07:00" if off_shift else ("Travelling" if travelling else "Working")))),
			"worker_id": order.worker_id,
			"active_worker_count": 0 if waiting_for_worker or leaving or payroll_paused or off_shift or travelling else 1,
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
