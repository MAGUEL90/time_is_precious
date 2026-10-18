extends RefCounted

## Legacy v3 migration only. New checkpoints use registered pickup sources.
## Renaming their scene/node paths requires an explicit save migration.
const CITY_PATH: String = "res://scenes/content_scene/content_scene.tscn"
const STATE = preload("res://scenes/pickup_item/date_palm_state.gd")

func nodes() -> Dictionary:
	var result: Dictionary = {}
	for index: int in range(1, 7):
		var path: String = "YSortWorld/DatePalmTree" + ("" if index == 1 else str(index))
		var id: String = "DatePalm_" + (CITY_PATH + ":" + path).sha256_text()
		result[id] = WorkStateRuntime.get_node_or_null(id)
	return result

func capture() -> Dictionary:
	var result: Dictionary = {}
	var states: Dictionary = nodes()
	for id: String in states:
		var state: Node = states[id]
		if state == null or state.get_script() != STATE:
			return {}
		result[id] = {"available": state.available.duplicate(),
			"remaining_minutes": state.remaining_minutes,
			"rng": {"seed": state._rng.seed, "state": state._rng.state}}
	return result

func validate(data: Variant) -> bool:
	var expected: Dictionary = nodes()
	if not data is Dictionary or data.size() != expected.size():
		return false
	for id: String in expected:
		var state: Node = expected[id]
		var record: Variant = data.get(id)
		if state == null or state.get_script() != STATE or not record is Dictionary or record.size() != 3:
			return false
		if not record.get("available") is Array or record.available.size() != state.available.size():
			return false
		for slot: Variant in record.available:
			if not slot is bool:
				return false
		if not record.get("remaining_minutes") is int:
			return false
		var remaining: int = record.remaining_minutes
		if remaining < 0 or remaining > 18 * TimeComponentManager.minute_per_hour:
			return false
		if (remaining == 0) != (not record.available.has(false)):
			return false
		var rng: Variant = record.get("rng")
		if not rng is Dictionary or rng.size() != 2 or not rng.get("seed") is int or not rng.get("state") is int:
			return false
	return true

func restore(data: Dictionary) -> void:
	# Empty is only staged by the v1/v2 reader: no historical palm data existed.
	# Reset on application, never during validation/slot observation.
	var states: Dictionary = nodes()
	for id: String in states:
		var state: Node = states[id]
		if data.is_empty():
			state.available.fill(true)
			state.remaining_minutes = 0
			state._rng.randomize()
		else:
			state.available.assign(data[id].available)
			state.remaining_minutes = data[id].remaining_minutes
			state._rng.seed = data[id].rng.seed
			state._rng.state = data[id].rng.state

func refresh() -> void:
	for state: Node in nodes().values():
		state.changed.emit()
