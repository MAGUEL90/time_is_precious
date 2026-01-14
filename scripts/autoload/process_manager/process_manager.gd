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

func set_weather_key(weather_key: String) -> void:
	current_weather_key = weather_key

func register_station(station_id: String, slots_total: int) -> void:
	var st := StationState.new()
	st.setup(station_id, slots_total)
	stations[station_id] = st

func register_process(process_data: ProcessData, auto_pull_from_inventory: bool = false, batch_size: int = 20) -> void:
	processes[process_data.process_id] = process_data
	if auto_pull_from_inventory:
		_auto_pull_batch_size[process_data.process_id] = max(batch_size, 1)

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

func _tick(delta_minutes: float) -> void:
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

func _try_auto_pull() -> void:
	# Auto-pull hanya untuk proses yang kamu set register_process(..., auto_pull = true)
	for process_id in _auto_pull_batch_size.keys():
		var process_dt: ProcessData = processes.get(process_id, null)
		if process_dt == null:
			continue
		
		var station_st: StationState = stations.get(process_dt.required_station_id, null)
		if station_st == null:
			continue
		
		var free_slot := station_st.find_free_slot()
		if free_slot == -1:
			continue
		
		var batch_size: int = _auto_pull_batch_size[process_id]
		var available: int = Inventory.items.get(process_dt.input_item_id, 0)
		if available <= 0:
			continue
			
		var take_qty: int = min(batch_size, available)
		if Inventory.remove_item(process_dt.input_item_id, take_qty):
			_start_batch(process_dt, station_st, free_slot)

func _start_batch(process_dt: ProcessData, station_st: StationState, slot_idx: int) -> void:
	pass 

func _finalize_batch(st: StationState, slot_idx: int, batch: ProcessBatch) -> void:
	pass
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
