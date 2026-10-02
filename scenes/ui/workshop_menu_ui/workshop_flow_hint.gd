extends RefCounted

static func get_hint(storage_state: Dictionary, drying: Dictionary) -> String:
	var pending_count: int = maxi(int(storage_state.get("pending_count", 0)), 0)
	if pending_count > 0:
		return "Manage Storage: free space for Pending Delivery."

	var held_lots: Array = storage_state.get("held_lots", [])
	if not held_lots.is_empty():
		return "Manage Storage: pay Held Output fees to release goods."

	var free_items: Dictionary = storage_state.get("free_items", {})
	var free_wet_mudbrick: int = maxi(
		int(free_items.get("wet_mudbrick", 0)),
		0
	)
	var free_sun_dried_mudbrick: int = maxi(
		int(free_items.get("sun_dried_mudbrick", 0)),
		0
	)
	var final_ready_hint: String = (
		"Sun-dried mudbricks ready in Free Stock. Manage Storage."
	)
	if free_wet_mudbrick > 0:
		if bool(drying.get("can_start", false)):
			return "Assign Work: dry wet mudbricks."
		if free_sun_dried_mudbrick > 0:
			return final_ready_hint
		if not bool(drying.get("registered", false)):
			return "Drying unavailable. Check Build & Upgrade."
		if not bool(drying.get("station_ready", false)):
			return "Build & Upgrade: build Drying Yard."
		if int(drying.get("free_slots", 0)) <= 0:
			return "Drying station busy. Check Work Progress."

		var batch_size: int = maxi(int(drying.get("batch_size", 0)), 1)
		return "Drying batch needs %d wet mudbricks; Free Stock: %d/%d." % [
			batch_size,
			free_wet_mudbrick,
			batch_size
		]

	var active_processes: Array = storage_state.get("active_processes", [])
	for process_value in active_processes:
		var process_entry: Dictionary = process_value
		var input_item_id: String = str(process_entry.get("input_item_id", ""))
		var inputs: Dictionary = process_entry.get("inputs", {})
		if input_item_id == "wet_mudbrick" or int(inputs.get("wet_mudbrick", 0)) > 0:
			return "Drying in progress. Check Work Progress."

	if free_sun_dried_mudbrick > 0:
		return final_ready_hint

	return "Deposit materials via Manage Storage, then Assign Work."
