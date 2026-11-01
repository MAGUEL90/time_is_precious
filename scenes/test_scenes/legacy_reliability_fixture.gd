extends RefCounted

## Construct historical schemas without restoring retired runtime properties.
static func encode_city(codec: RefCounted, raw: Dictionary) -> Variant:
	var legacy: Dictionary = raw.duplicate(true)
	for result: Dictionary in legacy.needs.last_needs_results.values():
		result["reliability"] = 0.5
		result["reliability_delta"] = -0.05
	var encoded: Variant = codec.encode(legacy)
	add_city_object_fields(encoded)
	return encoded

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
