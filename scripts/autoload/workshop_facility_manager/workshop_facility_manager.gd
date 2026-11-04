extends Node

const DRYING_YARD_ICON: Texture2D = preload(
	"res://assets/items/sun_dried_mudbrick.png"
)
const MAX_INT_VALUE: int = 9223372036854775807

signal facility_level_changed(
	facility_id: String,
	level: int,
	station_slots: int
)
signal transaction_finished()

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
var facility_contributions: Dictionary[String, Dictionary] = {}
var _transaction_busy: bool = false


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

func is_transaction_busy() -> bool:
	return _transaction_busy

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
	_material_store: Node = null
) -> Dictionary:
	return _get_facility_upgrade_preview(facility_id, false)

func _get_facility_upgrade_preview(
	facility_id: String,
	ignore_facility_transaction: bool
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
	var contributed_items: Dictionary[String, int] = {}
	var refund_plan: Dictionary[String, int] = {}
	var remaining_requirements: Dictionary[String, int] = {}
	var contribution_plan: Dictionary[String, int] = {}
	var missing_items: Dictionary[String, int] = {}
	var contribution_entry: Dictionary = facility_contributions.get(
		facility_id,
		{}
	)
	var stored_target_level: int = int(
		contribution_entry.get("target_level", -1)
	)
	var stored_items: Dictionary = {}
	var raw_stored_items: Variant = contribution_entry.get("items", {})
	if raw_stored_items is Dictionary:
		stored_items = raw_stored_items
	for item_id in requirements.keys():
		var available_quantity: int = maxi(
			int(Inventory.items.get(item_id, 0)),
			0
		)
		available_items[item_id] = available_quantity
		var required_quantity: int = requirements[item_id]
		var contributed_quantity: int = 0
		if stored_target_level == target_level:
			contributed_quantity = clampi(
				int(stored_items.get(item_id, 0)),
				0,
				required_quantity
			)
		if contributed_quantity > 0:
			contributed_items[item_id] = contributed_quantity
		var remaining_quantity: int = required_quantity - contributed_quantity
		if remaining_quantity > 0:
			remaining_requirements[item_id] = remaining_quantity
		var missing_quantity: int = maxi(
			remaining_quantity - available_quantity,
			0
		)
		if missing_quantity > 0:
			missing_items[item_id] = missing_quantity
		var contribution_quantity: int = mini(
			remaining_quantity,
			available_quantity
		)
		if contribution_quantity > 0:
			contribution_plan[item_id] = contribution_quantity

	refund_plan = _get_facility_refund_plan(contributed_items)
	var refund_remaining: Dictionary[String, int] = _subtract_item_counts(
		contributed_items,
		refund_plan
	)

	var transaction_busy: bool = (
		(_transaction_busy and not ignore_facility_transaction)
		or Inventory._bulk_transaction_in_progress
	)
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
		"contributed_items": contributed_items,
		"refund_plan": refund_plan,
		"refund_remaining": refund_remaining,
		"refund_capacity": Inventory.get_remaining_capacity(),
		"remaining_requirements": remaining_requirements,
		"contribution_plan": contribution_plan,
		"missing_items": missing_items,
		"transaction_busy": transaction_busy,
		"can_contribute": (
			not at_max_level
			and not contribution_plan.is_empty()
			and not transaction_busy
		),
		"can_refund": (
			not refund_plan.is_empty()
			and not transaction_busy
		),
		"can_upgrade": (
			not at_max_level
			and not requirements.is_empty()
			and missing_items.is_empty()
			and not transaction_busy
		),
		"message": (
			"Maximum level reached."
			if at_max_level
			else "A transaction is in progress."
			if transaction_busy
			else ""
		)
	}

func _get_facility_refund_plan(
	escrow_items: Dictionary
) -> Dictionary[String, int]:
	var refund_plan: Dictionary[String, int] = {}
	var max_load: float = Inventory.max_load
	if not is_finite(max_load) or max_load < 0.0:
		return refund_plan

	var projected_items: Dictionary = Inventory.items.duplicate(true)
	var current_weight: float = _inventory_items_weight(projected_items)
	if not is_finite(current_weight) or current_weight > max_load:
		return refund_plan
	var remaining_weight: float = max_load - current_weight
	var item_ids: Array[String] = []
	for item_id_value: Variant in escrow_items.keys():
		if not item_id_value is String or item_id_value.is_empty():
			return {}
		var quantity: Variant = escrow_items[item_id_value]
		if not quantity is int or quantity <= 0:
			return {}
		var escrow_item_data: ItemData = Inventory.get_item_data(item_id_value)
		if escrow_item_data == null or not is_finite(escrow_item_data.weight) or escrow_item_data.weight < 0.0:
			return {}
		item_ids.append(item_id_value)
	item_ids.sort()

	for item_id: String in item_ids:
		var inventory_quantity_value: Variant = Inventory.items.get(item_id, 0)
		if not inventory_quantity_value is int or inventory_quantity_value < 0:
			return {}
		var inventory_quantity: int = int(inventory_quantity_value)
		var integer_capacity: int = MAX_INT_VALUE - inventory_quantity
		if integer_capacity <= 0:
			continue
		var inventory_item_data: ItemData = Inventory.get_item_data(item_id)
		var quantity_to_return: int = mini(
			int(escrow_items[item_id]),
			integer_capacity
		)
		if inventory_item_data.weight > 0.0:
			if remaining_weight <= 0.0:
				continue
			var weight_capacity: float = remaining_weight / inventory_item_data.weight
			if is_finite(weight_capacity) and weight_capacity < float(quantity_to_return):
				quantity_to_return = floori(weight_capacity)
		if quantity_to_return <= 0:
			continue
		refund_plan[item_id] = quantity_to_return
		projected_items[item_id] = inventory_quantity + quantity_to_return
		remaining_weight -= inventory_item_data.weight * quantity_to_return

	if refund_plan.is_empty():
		return refund_plan
	var projected_weight: float = _inventory_items_weight(projected_items)
	if not is_finite(projected_weight) or projected_weight > max_load:
		# Match Inventory's strict projected-weight check at floating-point
		# boundaries while preserving as much of the final batch as can fit.
		for index: int in range(item_ids.size() - 1, -1, -1):
			var item_id: String = item_ids[index]
			if not refund_plan.has(item_id):
				continue
			var fallback_inventory_quantity: int = int(Inventory.items.get(item_id, 0))
			var originally_planned: int = refund_plan[item_id]
			if fallback_inventory_quantity == 0:
				projected_items.erase(item_id)
			else:
				projected_items[item_id] = fallback_inventory_quantity
			var weight_without_batch: float = _inventory_items_weight(projected_items)
			if not is_finite(weight_without_batch):
				refund_plan.erase(item_id)
				continue
			var fallback_item_data: ItemData = Inventory.get_item_data(item_id)
			if fallback_item_data.weight == 0.0:
				projected_items[item_id] = fallback_inventory_quantity + originally_planned
				continue
			var safe_quantity: int = 0
			if weight_without_batch < max_load:
				var remaining_for_item: float = max_load - weight_without_batch
				var item_capacity: float = remaining_for_item / fallback_item_data.weight
				if not is_finite(item_capacity) or item_capacity >= float(originally_planned):
					safe_quantity = originally_planned
				elif item_capacity > 0.0:
					safe_quantity = floori(item_capacity)
			if safe_quantity > 0:
				refund_plan[item_id] = safe_quantity
				projected_items[item_id] = fallback_inventory_quantity + safe_quantity
			else:
				refund_plan.erase(item_id)
			projected_weight = _inventory_items_weight(projected_items)
			if (
				(
					not is_finite(projected_weight)
					or projected_weight > max_load
				)
				and safe_quantity > 0
			):
				safe_quantity -= 1
				if safe_quantity > 0:
					refund_plan[item_id] = safe_quantity
					projected_items[item_id] = fallback_inventory_quantity + safe_quantity
				else:
					refund_plan.erase(item_id)
					if fallback_inventory_quantity == 0:
						projected_items.erase(item_id)
					else:
						projected_items[item_id] = fallback_inventory_quantity
				projected_weight = _inventory_items_weight(projected_items)
			if is_finite(projected_weight) and projected_weight <= max_load:
				return refund_plan
		return {}
	return refund_plan

func _inventory_items_weight(value: Dictionary) -> float:
	var total_weight: float = 0.0
	for item_id_value: Variant in value.keys():
		if not item_id_value is String:
			return INF
		var quantity: Variant = value[item_id_value]
		if not quantity is int or quantity < 0:
			return INF
		var item_data: ItemData = Inventory.get_item_data(item_id_value)
		if item_data == null or not is_finite(item_data.weight) or item_data.weight < 0.0:
			return INF
		total_weight += item_data.weight * int(quantity)
		if not is_finite(total_weight):
			return INF
	return total_weight

func _subtract_item_counts(
	items_to_subtract: Dictionary,
	items_to_remove: Dictionary
) -> Dictionary[String, int]:
	var remaining: Dictionary[String, int] = {}
	for item_id_value: Variant in items_to_subtract.keys():
		var item_id: String = str(item_id_value)
		var quantity: int = int(items_to_subtract[item_id_value]) - int(
			items_to_remove.get(item_id, 0)
		)
		if quantity > 0:
			remaining[item_id] = quantity
	return remaining

func contribute_facility_materials(facility_id: String) -> Dictionary:
	if _transaction_busy:
		return _facility_action_result(
			facility_id,
			false,
			"A facility transaction is already in progress."
		)
	var preview: Dictionary = get_facility_upgrade_preview(facility_id)
	if not bool(preview.get("valid", false)):
		return preview
	if not bool(preview.get("can_contribute", false)):
		return _facility_action_result(
			facility_id,
			false,
			"No remaining upgrade materials are available in Inventory."
		)

	_transaction_busy = true
	var result: Dictionary = _contribute_facility_materials_transaction(
		facility_id
	)
	_transaction_busy = false
	transaction_finished.emit()
	return result

func _contribute_facility_materials_transaction(facility_id: String) -> Dictionary:
	var preview: Dictionary = _get_facility_upgrade_preview(facility_id, true)
	var target_level: int = int(preview.get("target_level", 0))
	var plan: Dictionary = preview.get("contribution_plan", {})
	if plan.is_empty() or not Inventory.can_consume_bulk_items(plan):
		return _facility_action_result(
			facility_id,
			false,
			"Inventory materials changed before they could be contributed."
		)

	var previous_entry: Dictionary = facility_contributions.get(
		facility_id,
		{}
	).duplicate(true)
	var next_items: Dictionary = previous_entry.get("items", {}).duplicate(true)
	for item_id_value: Variant in plan.keys():
		var item_id: String = str(item_id_value)
		next_items[item_id] = int(next_items.get(item_id, 0)) + int(plan[item_id_value])
	facility_contributions[facility_id] = {
		"target_level": target_level,
		"items": next_items
	}
	if not Inventory.consume_bulk_items(plan):
		if previous_entry.is_empty():
			facility_contributions.erase(facility_id)
		else:
			facility_contributions[facility_id] = previous_entry
		return _facility_action_result(
			facility_id,
			false,
			"Could not contribute materials from Inventory."
		)

	var result: Dictionary = _facility_action_result(
		facility_id,
		true,
		"Materials contributed to the level %d upgrade." % target_level
	)
	result["contributed_this_batch"] = plan
	return result

func refund_facility_contributions(facility_id: String) -> Dictionary:
	if _transaction_busy:
		return _facility_action_result(
			facility_id,
			false,
			"A facility transaction is already in progress."
		)
	var preview: Dictionary = get_facility_upgrade_preview(facility_id)
	if not bool(preview.get("valid", false)):
		return preview
	if not bool(preview.get("can_refund", false)):
		return _facility_action_result(
			facility_id,
			false,
			(
				"There are no contributed materials to refund."
				if preview.get("contributed_items", {}).is_empty()
				else "No safe refund batch fits the current Inventory capacity."
			)
		)

	_transaction_busy = true
	var result: Dictionary = _refund_facility_contributions_transaction(
		facility_id
	)
	_transaction_busy = false
	transaction_finished.emit()
	return result

func _refund_facility_contributions_transaction(
	facility_id: String
) -> Dictionary:
	var preview: Dictionary = _get_facility_upgrade_preview(facility_id, true)
	var refund_plan: Dictionary = preview.get("refund_plan", {})
	var entry: Dictionary = facility_contributions.get(facility_id, {})
	var contributed_items: Dictionary = entry.get("items", {})
	if refund_plan.is_empty():
		return _facility_action_result(
			facility_id,
			false,
			"Inventory capacity or materials changed before the refund could start."
		)

	var saved_entry: Dictionary = entry.duplicate(true)
	var remaining_items: Dictionary[String, int] = _subtract_item_counts(
		contributed_items,
		refund_plan
	)
	if remaining_items.is_empty():
		facility_contributions.erase(facility_id)
	else:
		facility_contributions[facility_id] = {
			"target_level": int(entry.get("target_level", preview.get("target_level", 0))),
			"items": remaining_items
		}
	if not Inventory.refund_bulk_items(refund_plan):
		facility_contributions[facility_id] = saved_entry
		return _facility_action_result(
			facility_id,
			false,
			"Inventory capacity changed before the refund could commit."
		)

	var result: Dictionary = _facility_action_result(
		facility_id,
		true,
		"Refunded this material batch to Inventory. %s" % [
			(
				"The remaining materials stay committed."
				if not remaining_items.is_empty()
				else "All committed materials were returned."
			)
		]
	)
	result["refunded_this_batch"] = refund_plan
	result["remaining_contributed_items"] = remaining_items
	return result

func validate_facility_contributions(
	value: Variant,
	levels: Dictionary = {}
) -> bool:
	if not value is Dictionary:
		return false
	for facility_id_value: Variant in value.keys():
		if not facility_id_value is String:
			return false
		var facility_id: String = facility_id_value
		if not has_facility(facility_id):
			return false
		var entry_value: Variant = value[facility_id_value]
		if not entry_value is Dictionary:
			return false
		var entry: Dictionary = entry_value
		if entry.size() != 2 or not entry.has("target_level") or not entry.has("items"):
			return false
		var target_value: Variant = entry.get("target_level")
		var items_value: Variant = entry.get("items")
		if not target_value is int or not items_value is Dictionary:
			return false
		var current_level: int = int(
			levels.get(facility_id, get_facility_level(facility_id))
		)
		var target_level: int = int(target_value)
		if target_level != current_level + 1 or target_level > get_facility_max_level(facility_id):
			return false
		var requirements: Dictionary[String, int] = get_facility_upgrade_requirements(
			facility_id,
			target_level
		)
		var items: Dictionary = items_value
		if items.is_empty():
			return false
		for item_id_value: Variant in items.keys():
			if not item_id_value is String:
				return false
			var item_id: String = str(item_id_value)
			if not requirements.has(item_id):
				return false
			var quantity: Variant = items[item_id_value]
			if not quantity is int or int(quantity) <= 0 or int(quantity) > requirements[item_id]:
				return false
	return true
func _facility_action_result(
	facility_id: String,
	success: bool,
	message: String
) -> Dictionary:
	var result: Dictionary = _get_facility_upgrade_preview(facility_id, true)
	result["success"] = success
	result["message"] = message
	return result

func upgrade_facility(
	facility_id: String,
	_material_store: Node = null
) -> Dictionary:
	if _transaction_busy:
		var busy_preview: Dictionary = get_facility_upgrade_preview(facility_id)
		busy_preview["success"] = false
		busy_preview["message"] = "A facility transaction is already in progress."
		return busy_preview

	var preview: Dictionary = get_facility_upgrade_preview(facility_id)
	if not bool(preview.get("valid", false)):
		return preview
	if bool(preview.get("at_max_level", false)):
		preview["success"] = false
		return preview
	if not bool(preview.get("can_upgrade", false)):
		preview["success"] = false
		if not bool(preview.get("transaction_busy", false)):
			preview["message"] = "Missing materials in Inventory."
		return preview

	_transaction_busy = true
	var result: Dictionary = _upgrade_facility_transaction(facility_id)
	_transaction_busy = false
	transaction_finished.emit()
	return result

func _upgrade_facility_transaction(facility_id: String) -> Dictionary:
	# Stage level and station capacity without emitting. Inventory is charged
	# before callbacks see the completed facility, so no observer can start work
	# in an unpaid slot.
	var preview: Dictionary = _get_facility_upgrade_preview(facility_id, true)
	if not bool(preview.get("valid", false)):
		return preview
	if bool(preview.get("at_max_level", false)):
		preview["success"] = false
		return preview
	if not bool(preview.get("can_upgrade", false)):
		preview["success"] = false
		preview["message"] = "Missing materials in Inventory."
		return preview

	var previous_level: int = int(preview.get("current_level", 0))
	var target_level: int = int(preview.get("target_level", 0))
	var requirements: Dictionary = preview.get("remaining_requirements", {})
	var saved_contribution: Dictionary = facility_contributions.get(
		facility_id,
		{}
	).duplicate(true)
	if not Inventory.can_consume_bulk_items(requirements):
		preview["success"] = false
		preview["message"] = "Inventory materials changed before the upgrade could start."
		return preview

	if not _apply_facility_level(facility_id, target_level, false):
		preview["success"] = false
		preview["message"] = "Facility cannot be upgraded right now."
		return preview

	facility_contributions.erase(facility_id)
	if not Inventory.consume_bulk_items(requirements):
		if not saved_contribution.is_empty():
			facility_contributions[facility_id] = saved_contribution
		_apply_facility_level(facility_id, previous_level, false)
		var failed_preview: Dictionary = _get_facility_upgrade_preview(
			facility_id,
			true
		)
		failed_preview["success"] = false
		failed_preview["message"] = "Could not consume upgrade materials from Inventory."
		return failed_preview

	facility_level_changed.emit(
		facility_id,
		target_level,
		get_facility_slot_capacity(facility_id, target_level)
	)
	preview["success"] = true
	preview["message"] = "%s reached level %d." % [
		str(preview.get("display_name", facility_id)),
		target_level
	]
	preview["state"] = get_facility_state(facility_id)
	return preview

func set_facility_level(facility_id: String, level: int) -> bool:
	if _transaction_busy:
		return false
	if facility_contributions.has(facility_id) and level != get_facility_level(facility_id):
		return false
	return _apply_facility_level(facility_id, level, true)

func _apply_facility_level(
	facility_id: String,
	level: int,
	emit_change: bool
) -> bool:
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
	if emit_change:
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
