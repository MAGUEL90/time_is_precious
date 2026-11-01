extends RefCounted

## Construct historical schemas without restoring retired runtime properties.
static func encode_city(codec: RefCounted, raw: Dictionary) -> Variant:
	var legacy: Dictionary = raw.duplicate(true)
	for result: Dictionary in legacy.needs.last_needs_results.values():
		result["reliability"] = 0.5
		result["reliability_delta"] = -0.05
	var encoded: Variant = encode_v10(codec, legacy)
	add_city_object_fields(encoded)
	return encoded

## Version 10 predates the construction team and deferred-resignation fields.
static func encode_v10(codec: RefCounted, raw: Dictionary) -> Variant:
	var legacy: Dictionary = raw.duplicate(true)
	for plot: Dictionary in legacy.plots.values():
		plot.erase("worker_capacity")
		plot.erase("work_total_units")
	legacy.worksites.schema_version = 1
	legacy.worksites.erase("pending_output")
	legacy.worksites.erase("pending_progress")
	for route: Dictionary in legacy.worksites.routes.values():
		route.erase("resigning")
	var encoded: Variant = codec.encode(legacy)
	_remove_resignation_fields(encoded)
	return encoded

static func _remove_resignation_fields(value: Variant) -> void:
	if value is Dictionary:
		if value.get("$type") == "object" and value.get("class") == "WorkerData":
			value.fields.erase("resignation_pending")
		for child: Variant in value.values():
			_remove_resignation_fields(child)
	elif value is Array:
		for child: Variant in value:
			_remove_resignation_fields(child)

static func add_city_object_fields(value: Variant) -> void:
	if value is Dictionary:
		if value.get("$type") == "object" and value.get("class") in ["CitizenData", "WorkerData"]:
			value.fields["reliability"] = 0.5
		for child: Variant in value.values():
			add_city_object_fields(child)
	elif value is Array:
		for child: Variant in value:
			add_city_object_fields(child)

static func city_objects(value: Variant, class_name_value: String) -> Array:
	var found: Array = []
	if value is Dictionary:
		if value.get("$type") == "object" and value.get("class") == class_name_value:
			found.append(value)
		for child: Variant in value.values():
			found.append_array(city_objects(child, class_name_value))
	elif value is Array:
		for child: Variant in value:
			found.append_array(city_objects(child, class_name_value))
	return found
