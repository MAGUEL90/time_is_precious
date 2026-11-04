extends RefCounted

## Construct historical schemas without restoring retired runtime properties.
const LEGACY_STOCKPILES = preload("res://scenes/content_scene/worksites/legacy_stockpile_layout.gd")

## Old city checkpoints have neither the annex nor a payment-source marker.
static func strip_v16_owners(raw: Dictionary) -> void:
	raw.erase("annex_storage")
	raw.erase("transport")
	if raw.get("raid") is Dictionary:
		raw.raid.erase("_work_paid_source")
		raw.raid.erase("_refund_pending")
	if raw.get("facilities") is Dictionary:
		raw.facilities.erase("facility_contributions")
	if raw.get("merchant") is Dictionary:
		for field: String in ["_offers", "_stock", "_demand"]:
			if raw.merchant.get(field) is Dictionary:
				raw.merchant[field].erase("stone")

static func _add_old_empty_stockpiles(worksites: Dictionary, retained: Dictionary = {}) -> void:
	for endpoint_id: String in LEGACY_STOCKPILES.STOCKPILES:
		if retained.has(endpoint_id):
			worksites.storages[endpoint_id] = retained[endpoint_id].duplicate(true)
		else:
			worksites.storages[endpoint_id] = {"shared": false, "quantity": 0, "capacity": 96, "accepting": true}

static func encode_city(codec: RefCounted, raw: Dictionary, retained_stockpiles: Dictionary = {}) -> Variant:
	var legacy: Dictionary = raw.duplicate(true)
	for result: Dictionary in legacy.needs.last_needs_results.values():
		result["reliability"] = 0.5
		result["reliability_delta"] = -0.05
	var encoded: Variant = encode_v10(codec, legacy, retained_stockpiles)
	add_city_object_fields(encoded)
	return encoded

## Version 10 predates the construction team and deferred-resignation fields.
static func encode_v10(codec: RefCounted, raw: Dictionary, retained_stockpiles: Dictionary = {}) -> Variant:
	var legacy: Dictionary = raw.duplicate(true)
	strip_v16_owners(legacy)
	# Versions through 11 predate the authored citizen-house plot.
	legacy.plots.erase("WorkshopConstruction_" + "citizen_house_1".sha256_text())
	for plot: Dictionary in legacy.plots.values():
		plot.erase("worker_capacity")
		plot.erase("work_total_units")
	legacy.worksites.schema_version = 1
	_add_old_empty_stockpiles(legacy.worksites, retained_stockpiles)
	legacy.worksites.erase("pending_output")
	legacy.worksites.erase("pending_progress")
	legacy.worksites.erase("legacy_ground")
	for route: Dictionary in legacy.worksites.routes.values():
		route.erase("resigning")
		route.erase("legacy_final")
	for pile: Dictionary in legacy.worksites.ground:
		pile.erase("legacy_stockpile")
	var encoded: Variant = codec.encode(legacy)
	_remove_resignation_fields(encoded)
	return encoded

## Version 11 has the prior worker/worksite fields, but no house plot.
static func encode_v11(codec: RefCounted, raw: Dictionary) -> Variant:
	var legacy: Dictionary = raw.duplicate(true)
	strip_v16_owners(legacy)
	legacy.plots.erase("WorkshopConstruction_" + "citizen_house_1".sha256_text())
	legacy.worksites.schema_version = 2
	_add_old_empty_stockpiles(legacy.worksites)
	legacy.worksites.erase("legacy_ground")
	for route: Dictionary in legacy.worksites.routes.values():
		route.erase("legacy_final")
	for pile: Dictionary in legacy.worksites.ground:
		pile.erase("legacy_stockpile")
	return codec.encode(legacy)

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
