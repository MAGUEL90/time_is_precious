class_name CitySaveValues
extends RefCounted

const CitizenDataScript: Script = preload("res://resources/citizen_data/citizen_data.gd")
const WorkerDataScript: Script = preload("res://resources/worker_data/worker_data.gd")
const VisualProfileScript: Script = preload("res://resources/visual_profile/visual_profile.gd")
const WorkOrderScript: Script = preload("res://scripts/class/work_order/work_order.gd")
const StationStateScript: Script = preload("res://scripts/class/station_state/station_state.gd")
const ProcessBatchScript: Script = preload("res://scripts/class/process_batch/process_batch.gd")

const TAG_KEY: String = "$type"
const MAX_DEPTH: int = 32
const MAX_COLLECTION_SIZE: int = 10000
const MAX_INTEGER_TEXT_LENGTH: int = 20

const OBJECT_FIELDS: Dictionary = {
	"CitizenData": [
		"citizen_id", "display_name", "satisfaction", "reliability",
		"food_fulfilled", "clothing_fulfilled", "shelter_fulfilled", "experience",
		"visual_profile", "population_status", "employment_status", "profession",
	],
	"WorkerData": [
		"worker_id", "display_name", "profession", "profession_xp", "current_order_id",
		"current_job_id", "current_work_status", "profession_star", "efficiency",
		"payroll_start_day", "payroll_paid_from_day", "payroll_paid_until_day", "payroll_period_rate", "payroll_last_attempt_day",
		"reliability", "wage_shekel_per_day", "food_fulfilled", "clothing_fulfilled",
		"shelter_fulfilled", "satisfaction",
	],
	"VisualProfile": ["skin_tone", "expression", "hair_style", "clothes_id", "accessory"],
	"WorkOrder": [
		"worker_kind", "current_status", "order_id", "job_id", "job_display_name",
		"worker_id", "worker_slot_capacity", "start_time_total_minutes",
		"end_time_total_minutes", "inputs_snapshot", "outputs_snapshot", "tool_used_instance_id",
	],
	"StationState": ["station_id", "slots_total", "slots"],
	"ProcessBatch": [
		"batch_id", "process_id", "input_item_id", "output_item_id", "quantity",
		"start_total_time_minutes", "duration_minutes", "slot_index", "progress_minutes",
		"status", "fee_ids",
	],
}

const PAYROLL_FIELDS: Array[String] = ["payroll_start_day", "payroll_paid_from_day", "payroll_paid_until_day", "payroll_period_rate", "payroll_last_attempt_day"]
var allow_legacy_worker_fields: bool = false
var error: String = ""


func encode(value: Variant) -> Variant:
	error = ""
	return _encode_value(value, 0)


func decode(data: Variant) -> Variant:
	error = ""
	return _decode_value(data, 0)


func _encode_value(value: Variant, depth: int) -> Variant:
	if depth > MAX_DEPTH:
		_fail("Value nesting exceeds %d levels." % MAX_DEPTH)
		return null

	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return value
		TYPE_INT:
			return _tagged("int", {"value": str(value)})
		TYPE_FLOAT:
			if not is_finite(value):
				_fail("Non-finite floats cannot be saved.")
				return null
			return value
		TYPE_STRING_NAME:
			return _tagged("string_name", {"value": str(value)})
		TYPE_NODE_PATH:
			return _tagged("node_path", {"value": str(value)})
		TYPE_VECTOR2:
			if not is_finite(value.x) or not is_finite(value.y):
				_fail("Vector2 values must be finite.")
				return null
			return _tagged("vector2", {"x": value.x, "y": value.y})
		TYPE_ARRAY:
			return _encode_array(value, depth)
		TYPE_DICTIONARY:
			return _encode_dictionary(value, depth)
		TYPE_OBJECT:
			return _encode_object(value, depth)
		_:
			_fail("Unsupported value type: %s." % type_string(typeof(value)))
			return null


func _encode_array(value: Array, depth: int) -> Variant:
	if value.size() > MAX_COLLECTION_SIZE:
		_fail("Array exceeds the %d item limit." % MAX_COLLECTION_SIZE)
		return null

	var items: Array = []
	for item: Variant in value:
		var encoded_item: Variant = _encode_value(item, depth + 1)
		if not error.is_empty():
			return null
		items.append(encoded_item)
	return _tagged("array", {"items": items})


func _encode_dictionary(value: Dictionary, depth: int) -> Variant:
	if value.size() > MAX_COLLECTION_SIZE:
		_fail("Dictionary exceeds the %d item limit." % MAX_COLLECTION_SIZE)
		return null

	var entries: Array = []
	for key: Variant in value:
		if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME and typeof(key) != TYPE_INT:
			_fail("Dictionary keys must be String, StringName, or int values.")
			return null
		var encoded_key: Variant = _encode_value(key, depth + 1)
		if not error.is_empty():
			return null
		var encoded_value: Variant = _encode_value(value[key], depth + 1)
		if not error.is_empty():
			return null
		entries.append([encoded_key, encoded_value])
	return _tagged("dictionary", {"entries": entries})


func _encode_object(value: Object, depth: int) -> Variant:
	if value is Node:
		_fail("Nodes cannot be saved as values.")
		return null
	if not (value is RefCounted or value is Resource):
		_fail("Only approved RefCounted and Resource objects can be saved.")
		return null

	var approved_name: String = _approved_class_name(value)
	if approved_name.is_empty():
		_fail("Object script is not on the save whitelist.")
		return null

	var field_names: Array = OBJECT_FIELDS[approved_name]
	var fields: Dictionary = {}
	for field_name: String in field_names:
		var field_value: Variant = value.get(field_name)
		if approved_name == "WorkOrder" and field_name == "tool_used_instance_id":
			if field_value != null and typeof(field_value) != TYPE_STRING:
				_fail("WorkOrder.tool_used_instance_id must be null or String.")
				return null
		var encoded_field: Variant = _encode_value(field_value, depth + 1)
		if not error.is_empty():
			return null
		fields[field_name] = encoded_field
	return _tagged("object", {"class": approved_name, "fields": fields})


func _decode_value(data: Variant, depth: int) -> Variant:
	if depth > MAX_DEPTH:
		_fail("Value nesting exceeds %d levels." % MAX_DEPTH)
		return null

	match typeof(data):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return data
		TYPE_FLOAT:
			if not is_finite(data):
				_fail("Non-finite floats are not valid save data.")
				return null
			return data
		TYPE_DICTIONARY:
			return _decode_tagged_dictionary(data, depth)
		_:
			_fail("Save data contains an untagged or unsupported %s value." % type_string(typeof(data)))
			return null


func _decode_tagged_dictionary(data: Dictionary, depth: int) -> Variant:
	if not data.has(TAG_KEY) or typeof(data[TAG_KEY]) != TYPE_STRING:
		_fail("Save dictionaries must have a recognized type tag.")
		return null

	var tag: String = data[TAG_KEY]
	match tag:
		"int":
			if not _has_exact_string_keys(data, [TAG_KEY, "value"]):
				_fail("Malformed integer tag.")
				return null
			return _decode_integer(data["value"])
		"string_name":
			if not _has_exact_string_keys(data, [TAG_KEY, "value"]) or typeof(data["value"]) != TYPE_STRING:
				_fail("Malformed StringName tag.")
				return null
			return StringName(data["value"])
		"node_path":
			if not _has_exact_string_keys(data, [TAG_KEY, "value"]) or typeof(data["value"]) != TYPE_STRING:
				_fail("Malformed NodePath tag.")
				return null
			return NodePath(data["value"])
		"vector2":
			if not _has_exact_string_keys(data, [TAG_KEY, "x", "y"]):
				_fail("Malformed Vector2 tag.")
				return null
			if typeof(data["x"]) != TYPE_FLOAT or typeof(data["y"]) != TYPE_FLOAT:
				_fail("Vector2 coordinates must be floats.")
				return null
			if not is_finite(data["x"]) or not is_finite(data["y"]):
				_fail("Vector2 coordinates must be finite.")
				return null
			return Vector2(data["x"], data["y"])
		"array":
			return _decode_array(data, depth)
		"dictionary":
			return _decode_dictionary(data, depth)
		"object":
			return _decode_object(data, depth)
		_:
			_fail("Unknown save type tag: %s." % tag)
			return null


func _decode_integer(value: Variant) -> Variant:
	if typeof(value) != TYPE_STRING or value.length() > MAX_INTEGER_TEXT_LENGTH or not value.is_valid_int():
		_fail("Integer tag must contain a valid signed 64-bit decimal string.")
		return null
	var parsed: int = int(value)
	if str(parsed) != value:
		_fail("Integer tag is not in canonical signed 64-bit form.")
		return null
	return parsed


func _decode_array(data: Dictionary, depth: int) -> Variant:
	if not _has_exact_string_keys(data, [TAG_KEY, "items"]):
		_fail("Malformed array tag.")
		return null
	if typeof(data["items"]) != TYPE_ARRAY:
		_fail("Array tag items must be an Array.")
		return null
	var source: Array = data["items"]
	if source.size() > MAX_COLLECTION_SIZE:
		_fail("Array exceeds the %d item limit." % MAX_COLLECTION_SIZE)
		return null
	var decoded: Array = []
	for item: Variant in source:
		var decoded_item: Variant = _decode_value(item, depth + 1)
		if not error.is_empty():
			return null
		decoded.append(decoded_item)
	return decoded


func _decode_dictionary(data: Dictionary, depth: int) -> Variant:
	if not _has_exact_string_keys(data, [TAG_KEY, "entries"]):
		_fail("Malformed dictionary tag.")
		return null
	if typeof(data["entries"]) != TYPE_ARRAY:
		_fail("Dictionary tag entries must be an Array.")
		return null
	var entries: Array = data["entries"]
	if entries.size() > MAX_COLLECTION_SIZE:
		_fail("Dictionary exceeds the %d item limit." % MAX_COLLECTION_SIZE)
		return null
	var decoded: Dictionary = {}
	for entry: Variant in entries:
		if typeof(entry) != TYPE_ARRAY or entry.size() != 2:
			_fail("Each dictionary entry must contain exactly a key and value.")
			return null
		var key: Variant = _decode_value(entry[0], depth + 1)
		if not error.is_empty():
			return null
		if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME and typeof(key) != TYPE_INT:
			_fail("Decoded dictionary keys must be String, StringName, or int values.")
			return null
		var decoded_value: Variant = _decode_value(entry[1], depth + 1)
		if not error.is_empty():
			return null
		if decoded.has(key):
			_fail("Dictionary contains duplicate keys after decoding.")
			return null
		decoded[key] = decoded_value
	return decoded


func _decode_object(data: Dictionary, depth: int) -> Variant:
	if not _has_exact_string_keys(data, [TAG_KEY, "class", "fields"]):
		_fail("Malformed object tag.")
		return null
	if typeof(data["class"]) != TYPE_STRING or typeof(data["fields"]) != TYPE_DICTIONARY:
		_fail("Object tag class and fields have invalid types.")
		return null
	var type_name: String = data["class"]
	if not OBJECT_FIELDS.has(type_name):
		_fail("Object class is not on the save whitelist.")
		return null
	var field_data: Dictionary = data["fields"]
	if field_data.size() > MAX_COLLECTION_SIZE:
		_fail("Object field map exceeds the %d item limit." % MAX_COLLECTION_SIZE)
		return null
	var allowed_fields: Array = OBJECT_FIELDS[type_name].duplicate()
	if allow_legacy_worker_fields and type_name == "WorkerData":
		for field: String in PAYROLL_FIELDS:
			allowed_fields.erase(field)
	if field_data.size() != allowed_fields.size():
		_fail("Object field map does not match the complete %s schema." % type_name)
		return null
	for expected_field: String in allowed_fields:
		if not field_data.has(expected_field):
			_fail("Object field map is missing %s.%s." % [type_name, expected_field])
			return null
	var instance: Object = _approved_script(type_name).new()
	for field_name: Variant in field_data:
		if typeof(field_name) != TYPE_STRING or not allowed_fields.has(field_name):
			_fail("Object field is not approved for %s." % type_name)
			return null
		var decoded_field: Variant = _decode_value(field_data[field_name], depth + 1)
		if not error.is_empty():
			return null
		var prepared_field: Variant = _prepare_object_field(instance, type_name, field_name, decoded_field)
		if not error.is_empty():
			return null
		instance.set(field_name, prepared_field)
	return instance


func _prepare_object_field(instance: Object, type_name: String, field_name: String, decoded: Variant) -> Variant:
	# This property is intentionally dynamic in WorkOrder and represents an ID.
	if type_name == "WorkOrder" and field_name == "tool_used_instance_id":
		if decoded == null or typeof(decoded) == TYPE_STRING:
			return decoded
		_fail("WorkOrder.tool_used_instance_id must be null or String.")
		return null

	var current: Variant = instance.get(field_name)
	if typeof(current) == TYPE_NIL:
		if decoded == null:
			return null
		if type_name == "CitizenData" and field_name == "visual_profile" and _approved_class_name(decoded) == "VisualProfile":
			return decoded
		_fail("Object field %s.%s has an invalid object value." % [type_name, field_name])
		return null

	if current is Array:
		if typeof(decoded) != TYPE_ARRAY:
			_fail("Object field %s.%s must be an Array." % [type_name, field_name])
			return null
		return _prepare_array_field(current, decoded, type_name, field_name)
	if current is Dictionary:
		if typeof(decoded) != TYPE_DICTIONARY:
			_fail("Object field %s.%s must be a Dictionary." % [type_name, field_name])
			return null
		return _prepare_dictionary_field(current, decoded, type_name, field_name)
	if current is Object:
		if decoded == null:
			return null
		if _approved_class_name(current) != _approved_class_name(decoded):
			_fail("Object field %s.%s has an invalid object class." % [type_name, field_name])
			return null
		return decoded
	if typeof(current) != typeof(decoded):
		_fail("Object field %s.%s has an invalid value type." % [type_name, field_name])
		return null
	return decoded


func _prepare_array_field(existing: Array, decoded: Array, type_name: String, field_name: String) -> Variant:
	if not existing.is_typed():
		return decoded
	var expected_builtin: int = existing.get_typed_builtin()
	var expected_class: StringName = existing.get_typed_class_name()
	var expected_script: Script = existing.get_typed_script()
	for item: Variant in decoded:
		if expected_builtin != TYPE_NIL and typeof(item) != expected_builtin:
			_fail("Object field %s.%s contains an item with an invalid type." % [type_name, field_name])
			return null
		if expected_builtin == TYPE_OBJECT and item != null:
			if expected_script != null and item.get_script() != expected_script:
				_fail("Object field %s.%s contains an item with an invalid script." % [type_name, field_name])
				return null
			if not expected_class.is_empty() and item.get_class() != expected_class:
				_fail("Object field %s.%s contains an item with an invalid class." % [type_name, field_name])
				return null
	var typed_copy: Array = existing.duplicate()
	typed_copy.clear()
	typed_copy.assign(decoded)
	return typed_copy


func _prepare_dictionary_field(existing: Dictionary, decoded: Dictionary, type_name: String, field_name: String) -> Variant:
	if not existing.is_typed():
		return decoded
	var key_builtin: int = existing.get_typed_key_builtin()
	var value_builtin: int = existing.get_typed_value_builtin()
	for key: Variant in decoded:
		if key_builtin != TYPE_NIL and typeof(key) != key_builtin:
			_fail("Object field %s.%s contains a key with an invalid type." % [type_name, field_name])
			return null
		if value_builtin != TYPE_NIL and typeof(decoded[key]) != value_builtin:
			_fail("Object field %s.%s contains a value with an invalid type." % [type_name, field_name])
			return null
	var typed_copy: Dictionary = existing.duplicate(true)
	typed_copy.clear()
	typed_copy.assign(decoded)
	return typed_copy


func _approved_class_name(value: Variant) -> String:
	if not value is Object:
		return ""
	var script: Script = value.get_script()
	if script == CitizenDataScript:
		return "CitizenData"
	if script == WorkerDataScript:
		return "WorkerData"
	if script == VisualProfileScript:
		return "VisualProfile"
	if script == WorkOrderScript:
		return "WorkOrder"
	if script == StationStateScript:
		return "StationState"
	if script == ProcessBatchScript:
		return "ProcessBatch"
	return ""


func _approved_script(type_name: String) -> Script:
	match type_name:
		"CitizenData":
			return CitizenDataScript
		"WorkerData":
			return WorkerDataScript
		"VisualProfile":
			return VisualProfileScript
		"WorkOrder":
			return WorkOrderScript
		"StationState":
			return StationStateScript
		"ProcessBatch":
			return ProcessBatchScript
	return null


func _tagged(tag: String, fields: Dictionary) -> Dictionary:
	var tagged: Dictionary = {TAG_KEY: tag}
	for key: String in fields:
		tagged[key] = fields[key]
	return tagged


func _has_exact_string_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or not expected.has(key):
			return false
	return true


func _fail(message: String) -> void:
	if error.is_empty():
		error = message
