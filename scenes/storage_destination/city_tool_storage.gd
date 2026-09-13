extends Node

## Unique physical tool units in shared city supplies. UI never owns the tools.
signal changed
var units: Dictionary = {}

func add_tool_unit(unit_id: String, tool_id: String, display_name: String) -> bool:
	if unit_id.is_empty() or tool_id.is_empty() or units.has(unit_id):
		return false
	units[unit_id] = {"tool_id": tool_id, "name": display_name, "worker_id": ""}
	changed.emit()
	return true

func allocate(unit_id: String, worker_id: String) -> bool:
	if worker_id.is_empty() or not units.has(unit_id) or not str(units[unit_id].worker_id).is_empty():
		return false
	units[unit_id].worker_id = worker_id
	changed.emit()
	return true

func release(unit_id: String, worker_id: String) -> bool:
	if not units.has(unit_id) or units[unit_id].worker_id != worker_id:
		return false
	units[unit_id].worker_id = ""
	changed.emit()
	return true

func has_equipped(worker_id: String, tool_id: String) -> bool:
	for unit: Dictionary in units.values():
		if unit.worker_id == worker_id and unit.tool_id == tool_id:
			return true
	return false
