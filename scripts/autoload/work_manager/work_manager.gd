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
	output_item_store: Node = null, _service_fee_shekel: int = 0) -> String:
	# tambah argumen storage agar bisa pakai WorkshopStorage
	
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
	order.end_time_total_minutes = start_total + max(job.base_duration_minutes, 1)
	
	order.inputs_snapshot = job.inputs.duplicate(true)
	order.outputs_snapshot = job.outputs.duplicate(true)
	order.current_status = WorkOrder.Status.RUNNING
	
	active_orders[order.order_id] = order
	# simpan mapping storage per order agar finalize konsisten 
	# penting untuk workshop escrow
	source_item_store_by_order_id[order.order_id] = source_item_store # storage sumber
	output_item_store_by_order_id[order.order_id] = output_item_store # storage tujuan 
	service_fee_by_order[order.order_id] = max(_service_fee_shekel, 0) # biaya jasa per order
	
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
	var is_player_worker: bool = (order.worker_kind == WorkOrder.Worker_Type.PLAYER)
	
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
	else:
		# NPC: escrow murni -> claimable saja
		if output_store != null and output_store.has_method("add_claimable_output"):
			output_store.call(
				"add_claimable_output",
				job_outputs.duplicate(true),
				fee,
				order.worker_id,
				now_total_minutes,
				-1
			)
		else:
			# fallback aman: kalau output_store tidak punya claimable, baru kita masukkan langsung
			for item_id in job_outputs.keys():
				if output_store != null and output_store.has_method("add_item"):
					output_store.call("add_item", item_id, int(job_outputs[item_id]))
				else:
					Inventory.add_item(item_id, int(job_outputs[item_id]))
					
	order.current_status = WorkOrder.Status.DONE
	active_orders.erase(order_id)

	# cleanup mapping agar tidak numpuk # penting untuk runtime panjang
	source_item_store_by_order_id.erase(order_id) # hapus sumber
	output_item_store_by_order_id.erase(order_id) # hapus tujuan
	service_fee_by_order.erase(order_id) # hapus fee
