extends Node

# simpan storage sumber per order agar finalize konsisten
var source_item_store_by_order_id: Dictionary[String, Node] = {} 
# simpan storage tujuan per order agar output masuk workshop (bukan selalu inventory player)
var output_item_store_by_order_id: Dictionary[String, Node] = {}
# simpan biaya jasa untuk escrow output NPC
var service_fee_by_order: Dictionary[String, int] = {}

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

func start_job(
	job: JobData, worker_kind: int, worker_id: String, 
	tool: ToolInstance = null, source_item_store: Node = Inventory,
	output_item_store: Node = Inventory, _service_fee_shekel: int = 0) -> String:
	# tambah argumen storage agar bisa pakai WorkshopStorage
	
	# fallback aman bila caller lupa mengirim storage
	if source_item_store == null:
		source_item_store = Inventory 
	if output_item_store == null:
		output_item_store = Inventory
	
	for item_identifier in job.inputs.keys(): # ganti nama variabel agar lebih jelas
		if not bool(source_item_store.call("has_item", item_identifier, int(job.inputs[item_identifier]))): # cek input di storage sumber (workshop atau inventory)
			return "" # batal start bila input tidak cukup di storage sumber
	
	for item_identifier in job.inputs.keys(): # ganti nama variabel agar lebih jelas
		source_item_store.call("remove_item", item_identifier, int(job.inputs[item_identifier])) # consume input dari storage sumber (workshop atau inventory)
	
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
