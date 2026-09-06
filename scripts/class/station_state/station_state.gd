class_name StationState extends RefCounted

var station_id: String = ""
var slots_total: int = 0
var slots: Array = []

func setup(p_station_id: String, p_slots_total: int) -> void:
	station_id = p_station_id
	resize_slots(p_slots_total)

func resize_slots(p_slots_total: int) -> bool:
	var safe_slots_total: int = maxi(p_slots_total, 0)
	if safe_slots_total < slots.size():
		for index: int in range(safe_slots_total, slots.size()):
			if slots[index] != null:
				return false

	var previous_size: int = slots.size()
	slots.resize(safe_slots_total)
	for index: int in range(previous_size, safe_slots_total):
		slots[index] = null

	slots_total = safe_slots_total
	return true

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







