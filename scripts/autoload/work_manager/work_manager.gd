extends Node


var active_orders: Dictionary[String, WorkOrder] = {}
var _last_total_minutes: int = -1

func on_time_changed(day: int, hour: int, minute: int) -> void:
	var now_total: int = (day * 24 * 60) + (hour * 60) + minute
	if _last_total_minutes <= 0:
		_last_total_minutes = now_total
		return
		
	var delta: int = now_total - _last_total_minutes
	_last_total_minutes = now_total
		
	if delta <= 0:
		return
		
	_tick(now_total)

func start_job(job: JobData, worker_kind: int, worker_id: String, tool: ToolInstance = null) -> String:
	
	# 1) cek & consume inputs
	for item_id in job.inputs.keys():
		var need: int = int(job.inputs[item_id])
		if not Inventory.has_item(item_id, need):
			return "" # Input Kurang
	
	for item_id in job.inputs.keys():
		var need: int = int(job.inputs[item_id])
		Inventory.remove_item(item_id, need)
	
	# 2) tool durability (kalau ada)
	if tool != null and job.required_tool_id != "":
		# validasi id tool cocok(opsional)
		tool.consume(job.tool_durability_loss)
	
	# 3) buat order
	var order: WorkOrder = WorkOrder.new()
	order.order_id = str(Time.get_ticks_usec())
	order.job_id = job.job_id
	order.worker_kind = worker_kind
	order.worker_id = worker_id
	
	var start_total: int = _last_total_minutes if _last_total_minutes >= 0 else 0
	order.start_time_total_minutes = start_total
	order.end_time_total_minutes = start_total + max (job.base_duration_minutes, 1)
	
	order.inputs_snapshot = job.inputs.duplicate(true)
	order.outputs_snapshot = job.outputs.duplicate(true)
	order.current_status = WorkOrder.Status.RUNNING
	
	active_orders[order.order_id] = order
	return order.order_id

func _tick(now_total_minutes: int) -> void:
	for order_id in active_orders.keys():
		var order: WorkOrder = active_orders[order_id]
		if order.current_status != WorkOrder.Status.RUNNING:
			continue
		
		if now_total_minutes >= order.end_time_total_minutes:
			_finalize_order(order_id, order)

func _finalize_order(order_id: String, order: WorkOrder) -> void:
	# Untuk MVP: output langsung masuk inventory
	# Waste rate: output dikurangi (opsional)
	var job_outputs: Dictionary = order.outputs_snapshot
	for item_id in job_outputs.keys():
		var qty: int = int(job_outputs[item_id])
		
		# waste rate kalau kamu mau pakai (butuh ambil JobData lagi dari DB)
		Inventory.add_item(item_id, qty)
	
	order.current_status = WorkOrder.Status.DONE
	active_orders.erase(order_id)

# INI HINT, BARIS KE BERAPA AKU ?
