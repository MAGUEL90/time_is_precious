class_name StationState extends Node

var station_id: String = ""
var slots_total: int = 0
var slots: Array = []

func setup(p_station_id: String, p_slots_total: int) -> void:
	station_id = p_station_id
	slots_total = max(p_slots_total, 0)
	slots.resize(slots_total)
	for i in range(slots_total):
		slots[i] = null # slot kosong

func find_free_slot() -> int:
	for i in range(slots.size()):
		if slots[i] == null:
			return i
	return -1

func set_slot(idx: int, batch: ProcessBatch) -> void:
	if idx < 0 or idx >= slots.size():
		return
	slots[idx] = batch

func clear_slot(idx: int) -> void:
	if idx < 0 or idx >= slots.size():
		return
	
	slots[idx] = null







	
