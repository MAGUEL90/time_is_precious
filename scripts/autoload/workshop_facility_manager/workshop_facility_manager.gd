extends Node

const DRYING_YARD_ICON: Texture2D = preload(
	"res://assets/items/sun_dried_mudbrick.png"
)

signal facility_level_changed(
	facility_id: String,
	level: int,
	station_slots: int
)

const FACILITY_DEFINITIONS: Dictionary = {
	"drying_yard": {
		"display_name": "Drying Yard",
		"icon": DRYING_YARD_ICON,
		"max_level": 3,
		"station_slots_by_level": [0, 1, 2, 3],
		"upgrade_requirements": {
			1: {
				"wood_log": 2,
				"reed_bundle": 4,
				"clay_lump": 4
			},
			2: {
				"wood_log": 4,
				"reed_bundle": 6,
				"sun_dried_mudbrick": 10
			},
			3: {
				"wood_log": 6,
				"reed_bundle": 10,
				"sun_dried_mudbrick": 20
			}
		}
	}
}

var facility_levels: Dictionary[String, int] = {
	"drying_yard": 0
}


func _ready() -> void:
	sync_process_stations()

func has_facility(facility_id: String) -> bool:
	return FACILITY_DEFINITIONS.has(facility_id)

func get_facility_ids() -> Array[String]:
	var facility_ids: Array[String] = []
	for facility_id_value in FACILITY_DEFINITIONS.keys():
		facility_ids.append(str(facility_id_value))
	facility_ids.sort()
	return facility_ids

func get_facility_level(facility_id: String) -> int:
	return maxi(int(facility_levels.get(facility_id, 0)), 0)

func get_facility_max_level(facility_id: String) -> int:
	var definition: Dictionary = FACILITY_DEFINITIONS.get(
		facility_id,
		{}
	)
	return maxi(int(definition.get("max_level", 0)), 0)

func is_facility_built(facility_id: String) -> bool:
	return get_facility_level(facility_id) > 0

func get_facility_slot_capacity(
	facility_id: String,
	level: int = -1
) -> int:
	var definition: Dictionary = FACILITY_DEFINITIONS.get(
		facility_id,
		{}
	)
	if definition.is_empty():
		return 0

	var slots_by_level: Array = definition.get(
		"station_slots_by_level",
		[]
	)
	var target_level: int = (
		get_facility_level(facility_id)
		if level < 0
		else level
	)
	if target_level < 0 or target_level >= slots_by_level.size():
		return 0

	return maxi(int(slots_by_level[target_level]), 0)

func get_facility_state(facility_id: String) -> Dictionary:
	if not has_facility(facility_id):
		return {
			"valid": false,
			"facility_id": facility_id
		}

	var definition: Dictionary = FACILITY_DEFINITIONS[facility_id]
	var level: int = get_facility_level(facility_id)
	return {
		"valid": true,
		"facility_id": facility_id,
		"display_name": str(definition.get("display_name", facility_id)),
		"icon": definition.get("icon"),
		"level": level,
		"max_level": get_facility_max_level(facility_id),
		"is_built": level > 0,
		"station_slots": get_facility_slot_capacity(facility_id, level)
	}

func get_facility_upgrade_requirements(
	facility_id: String,
	target_level: int = -1
) -> Dictionary[String, int]:
	var requirements: Dictionary[String, int] = {}
	if not has_facility(facility_id):
		return requirements

	var level: int = (
		get_facility_level(facility_id) + 1
		if target_level < 0
		else target_level
	)
	var definition: Dictionary = FACILITY_DEFINITIONS[facility_id]
	var requirements_by_level: Dictionary = definition.get(
		"upgrade_requirements",
		{}
	)
	var raw_requirements: Dictionary = requirements_by_level.get(
		level,
		{}
	)
	for item_id_value in raw_requirements.keys():
		var item_id: String = str(item_id_value)
		var quantity: int = maxi(
			int(raw_requirements[item_id_value]),
			0
		)
		if not item_id.is_empty() and quantity > 0:
			requirements[item_id] = quantity

	return requirements

func get_facility_upgrade_preview(
	facility_id: String,
	material_store: Node
) -> Dictionary:
	var state: Dictionary = get_facility_state(facility_id)
	if not bool(state.get("valid", false)):
		return {
			"valid": false,
			"can_upgrade": false,
			"message": "Unknown workshop facility."
		}

	var current_level: int = int(state.get("level", 0))
	var maximum_level: int = int(state.get("max_level", 0))
	var target_level: int = current_level + 1
	var at_max_level: bool = current_level >= maximum_level
	var requirements: Dictionary[String, int] = {}
	if not at_max_level:
		requirements = get_facility_upgrade_requirements(
			facility_id,
			target_level
		)

	var available_items: Dictionary[String, int] = {}
	var missing_items: Dictionary[String, int] = {}
	for item_id in requirements.keys():
		var available_quantity: int = _get_material_quantity(
			material_store,
			item_id
		)
		available_items[item_id] = available_quantity
		var required_quantity: int = requirements[item_id]
		if available_quantity < required_quantity:
			missing_items[item_id] = required_quantity - available_quantity

	return {
		"valid": true,
		"facility_id": facility_id,
		"display_name": str(state.get("display_name", facility_id)),
		"current_level": current_level,
		"target_level": target_level,
		"max_level": maximum_level,
		"current_slots": int(state.get("station_slots", 0)),
		"target_slots": (
			int(state.get("station_slots", 0))
			if at_max_level
			else get_facility_slot_capacity(facility_id, target_level)
		),
		"at_max_level": at_max_level,
		"requirements": requirements,
		"available_items": available_items,
		"missing_items": missing_items,
		"can_upgrade": (
			not at_max_level
			and not requirements.is_empty()
			and missing_items.is_empty()
		),
		"message": (
			"Maximum level reached."
			if at_max_level
			else ""
		)
	}

func upgrade_facility(
	facility_id: String,
	material_store: Node
) -> Dictionary:
	var preview: Dictionary = get_facility_upgrade_preview(
		facility_id,
		material_store
	)
	if not bool(preview.get("valid", false)):
		return preview
	if bool(preview.get("at_max_level", false)):
		preview["success"] = false
		return preview
	if not bool(preview.get("can_upgrade", false)):
		preview["success"] = false
		preview["message"] = "Missing materials in Workshop Free Stock."
		return preview
	if material_store == null or not material_store.has_method(
		"remove_free_items"
	):
		preview["success"] = false
		preview["message"] = "Workshop Free Stock is unavailable."
		return preview

	var previous_level: int = int(preview.get("current_level", 0))
	var target_level: int = int(preview.get("target_level", 0))
	if not set_facility_level(facility_id, target_level):
		preview["success"] = false
		preview["message"] = "Facility cannot be upgraded right now."
		return preview

	var requirements: Dictionary = preview.get("requirements", {})
	if not bool(material_store.call("remove_free_items", requirements)):
		set_facility_level(facility_id, previous_level)
		preview["success"] = false
		preview["message"] = "Could not consume upgrade materials."
		return preview

	preview["success"] = true
	preview["message"] = "%s reached level %d." % [
		str(preview.get("display_name", facility_id)),
		target_level
	]
	preview["state"] = get_facility_state(facility_id)
	return preview

func set_facility_level(facility_id: String, level: int) -> bool:
	if not has_facility(facility_id):
		return false

	var maximum_level: int = get_facility_max_level(facility_id)
	if level < 0 or level > maximum_level:
		return false

	var station_slots: int = get_facility_slot_capacity(
		facility_id,
		level
	)
	if not ProcessManager.configure_station(
		facility_id,
		station_slots
	):
		return false

	if get_facility_level(facility_id) == level:
		return true

	facility_levels[facility_id] = level
	facility_level_changed.emit(
		facility_id,
		level,
		station_slots
	)
	return true

func sync_process_stations() -> bool:
	for facility_id_value in FACILITY_DEFINITIONS.keys():
		var facility_id: String = str(facility_id_value)
		if not ProcessManager.configure_station(
			facility_id,
			get_facility_slot_capacity(facility_id)
		):
			return false

	return true

func reset_facilities() -> bool:
	for facility_id_value in FACILITY_DEFINITIONS.keys():
		var facility_id: String = str(facility_id_value)
		if not set_facility_level(facility_id, 0):
			return false

	return true

func _get_material_quantity(material_store: Node, item_id: String) -> int:
	if material_store == null or item_id.is_empty():
		return 0

	if material_store.has_method("get_free_item_quantity"):
		return maxi(
			int(
				material_store.call(
					"get_free_item_quantity",
					item_id
				)
			),
			0
		)

	var store_items: Variant = material_store.get("items")
	if store_items is Dictionary:
		return maxi(int((store_items as Dictionary).get(item_id, 0)), 0)

	return 0
