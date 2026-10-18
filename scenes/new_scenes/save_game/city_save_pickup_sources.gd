extends RefCounted

## Registered source ledgers survive map unloading, so home saves use the same owners.
const CITY_PATH: String = "res://scenes/content_scene/content_scene.tscn"
const STATE = preload("res://scenes/pickup_item/pickup_source_state.gd")

func nodes() -> Dictionary:
	var result: Dictionary = {}
	for state: Node in WorkStateRuntime.get_tree().get_nodes_in_group("pickup_source_states"):
		if state.get_parent() == WorkStateRuntime and state.source_scene == CITY_PATH:
			result[str(state.name)] = state
	return result

func capture() -> Dictionary:
	var result: Dictionary = {}
	var states: Dictionary = nodes()
	for id: String in states:
		var state: Node = states[id]
		if state == null or not is_instance_of(state, STATE):
			return {}
		result[id] = {"available": state.available.duplicate(),
			"remaining_minutes": state.remaining_minutes,
			"rng": {"seed": state._rng.seed, "state": state._rng.state},
			"config": state.source_config.duplicate()}
	return result

func validate(data: Variant) -> bool:
	var expected: Dictionary = nodes()
	if not data is Dictionary or data.size() != expected.size():
		return false
	for id: String in expected:
		var state: Node = expected[id]
		var record: Variant = data.get(id)
		if state == null or not is_instance_of(state, STATE) or not record is Dictionary or record.size() != 4:
			return false
		if record.get("config") != state.source_config:
			return false
		for key: String in state.source_config:
			if typeof(record.config[key]) != typeof(state.source_config[key]):
				return false
		if not record.get("available") is Array or record.available.size() != state.available.size():
			return false
		for slot: Variant in record.available:
			if not slot is bool:
				return false
		if not record.get("remaining_minutes") is int:
			return false
		var remaining: int = record.remaining_minutes
		if remaining < 0 or remaining > state.source_config.refill_max_hours * TimeComponentManager.minute_per_hour:
			return false
		if not state.source_config.refill_enabled:
			if remaining != 0:
				return false
		elif (remaining == 0) != (not record.available.has(false)):
			return false
		var rng: Variant = record.get("rng")
		if not rng is Dictionary or rng.size() != 2 or not rng.get("seed") is int or not rng.get("state") is int:
			return false
	return true

func restore(data: Dictionary) -> void:
	# Missing records are staged only by legacy migration, never by the v4 reader.
	# Reset on application, never during validation/slot observation.
	var states: Dictionary = nodes()
	for id: String in states:
		var state: Node = states[id]
		if not data.has(id):
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
