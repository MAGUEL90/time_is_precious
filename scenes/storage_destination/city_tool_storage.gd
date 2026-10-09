extends Node

## Physical items in shared city supplies. Equipment stays unique for worker allocation.
signal changed
var units: Dictionary = {}
var items: Dictionary = {}
## Leftover points from opened ready-to-eat units owned by the city.
## A portion never represents a second whole item in `items`.
var food_portions: Dictionary = {}
const MAX_INT_VALUE: int = 9223372036854775807
const SUPPORTED_ITEM_IDS: Array[String] = ["cart", "basic_glove", "stone_hammer"]
# Existing finished garments mostly still use the generic Resource category.
# Keep their acceptance explicit without changing item values or equipment slots.
const CLOTHING_ITEM_IDS: Array[String] = [
	"simple_clothes", "clay_worn_wrap", "plain_linen_wrap", "plain_head_wrap",
	"simple_robe", "trimmed_robe", "reed_sandal"
]
var _unit_sequence: int = 0
var _transfer_in_progress: bool = false

## Legacy bulk raid fixture API. Production raid loot uses the ranked one-item API below.
## This compatibility entrypoint retains its original reserve semantics.
func take_raid_loot(capacity: int, reserve_per_stack: int) -> Dictionary:
	if _transfer_in_progress or capacity <= 0 or reserve_per_stack < 0 or not _has_valid_counted_stacks():
		return {}
	var next_items: Dictionary = items.duplicate(true)
	var stolen: Dictionary = {}
	var ids: Array = next_items.keys()
	ids.sort()
	var remaining: int = capacity
	for item_id: String in ids:
		if remaining == 0:
			break
		var amount: int = mini(remaining, maxi(0, int(next_items[item_id]) - reserve_per_stack))
		if amount <= 0:
			continue
		next_items[item_id] -= amount
		if int(next_items[item_id]) == 0:
			next_items.erase(item_id)
		stolen[item_id] = amount
		remaining -= amount
	if not stolen.is_empty():
		_transfer_in_progress = true
		items = next_items
		changed.emit()
		_transfer_in_progress = false
	return stolen

## Preview the highest-ranked eligible counted stack item that fits the remaining weight.
## Unique equipment units and fractional food portions are intentionally outside this API.
func peek_raid_loot(remaining_weight: float, preference: String = "balanced") -> Dictionary:
	if _transfer_in_progress or not _is_valid_raid_loot_request(remaining_weight, preference):
		return {}
	var candidates: Array[Dictionary] = _get_ranked_raid_loot_candidates(remaining_weight, preference)
	if candidates.is_empty():
		return {}
	var selected: Dictionary = candidates[0]
	return {
		"item_id": str(selected.item_id),
		"weight": float(selected.weight),
		"rarity": int(selected.rarity),
		"reason": str(selected.reason)
	}

## Remove exactly one whole counted stack item, atomically and without touching Inventory.
func take_ranked_raid_item(remaining_weight: float, preference: String = "balanced") -> Dictionary:
	if _transfer_in_progress:
		return {}
	var selected: Dictionary = peek_raid_loot(remaining_weight, preference)
	if selected.is_empty():
		return {}
	var item_id: String = str(selected.item_id)
	var quantity_value: Variant = items.get(item_id, 0)
	if not quantity_value is int or int(quantity_value) <= 0:
		return {}

	var next_items: Dictionary = items.duplicate(true)
	var remaining_quantity: int = int(next_items[item_id]) - 1
	if remaining_quantity > 0:
		next_items[item_id] = remaining_quantity
	else:
		next_items.erase(item_id)

	_transfer_in_progress = true
	items = next_items
	changed.emit()
	_transfer_in_progress = false

	var receipt: Dictionary = selected.duplicate(true)
	receipt["quantity"] = 1
	return receipt

func get_food_supply_points() -> int:
	var state: Dictionary = _validated_food_state()
	if not bool(state.ok):
		return 0
	return int(state.whole_points) + int(state.portion_points)

func get_food_portion_points() -> int:
	var state: Dictionary = _validated_food_state()
	if not bool(state.ok):
		return 0
	return int(state.portion_points)

func get_clothing_item_count() -> int:
	var state: Dictionary = _validated_clothing_state()
	if not bool(state.ok):
		return 0
	return int(state.count)

func take_clothing_items(maximum: int) -> Array[String]:
	if _transfer_in_progress or maximum <= 0:
		return []
	var state: Dictionary = _validated_clothing_state()
	if not bool(state.ok) or int(state.count) <= 0:
		return []

	var next_items: Dictionary = items.duplicate(true)
	var taken: Array[String] = []
	var remaining: int = mini(maximum, int(state.count))
	var clothing_ids: Array[String] = []
	for clothing_id: String in CLOTHING_ITEM_IDS:
		clothing_ids.append(clothing_id)
	clothing_ids.sort()
	for item_id: String in clothing_ids:
		if remaining <= 0:
			break
		var quantity: int = int(next_items.get(item_id, 0))
		var units_to_take: int = mini(quantity, remaining)
		for _index: int in range(units_to_take):
			taken.append(item_id)
		remaining -= units_to_take
		quantity -= units_to_take
		if quantity > 0:
			next_items[item_id] = quantity
		else:
			next_items.erase(item_id)

	if taken.is_empty():
		return []
	_commit_clothing_consumption(next_items)
	return taken

func consume_food_points(amount: int) -> bool:
	if _transfer_in_progress or amount <= 0:
		return false
	var state: Dictionary = _validated_food_state()
	if not bool(state.ok) or int(state.total_points) < amount:
		return false

	var remaining: int = amount
	var next_items: Dictionary = items.duplicate(true)
	var next_portions: Dictionary = food_portions.duplicate(true)

	# Use retained portions before opening any whole unit. Sort by source id so
	# repeated requests are deterministic when several portion sources exist.
	var portion_ids: Array[String] = []
	for item_id_value: Variant in next_portions.keys():
		portion_ids.append(str(item_id_value))
	portion_ids.sort()
	for item_id: String in portion_ids:
		if remaining <= 0:
			break
		var available_points: int = int(next_portions[item_id])
		var used_points: int = mini(available_points, remaining)
		remaining -= used_points
		available_points -= used_points
		if available_points > 0:
			next_portions[item_id] = available_points
		else:
			next_portions.erase(item_id)

	# Open the smallest-value ready food units first. A final opened unit can
	# leave a positive remainder, retained under that unit's source item id.
	var food_ids: Array[String] = []
	for item_id_value: Variant in next_items.keys():
		var item_id: String = str(item_id_value)
		var item_data: ItemData = ItemDatabase.get_item_data(item_id)
		if _is_ready_food(item_data) and int(next_items[item_id]) > 0:
			food_ids.append(item_id)
	food_ids.sort_custom(func(a: String, b: String):
		var a_data: ItemData = ItemDatabase.get_item_data(a)
		var b_data: ItemData = ItemDatabase.get_item_data(b)
		if a_data.food_supply_value != b_data.food_supply_value:
			return a_data.food_supply_value < b_data.food_supply_value
		return a < b
	)
	for item_id: String in food_ids:
		if remaining <= 0:
			break
		var item_data: ItemData = ItemDatabase.get_item_data(item_id)
		var unit_value: int = item_data.food_supply_value
		var available_units: int = int(next_items[item_id])
		var division: Dictionary = _divide_nonnegative(remaining, unit_value)
		if not bool(division.ok):
			return false
		var units_to_open: int = int(division.quotient)
		if int(division.remainder) > 0:
			units_to_open += 1
		units_to_open = mini(available_units, units_to_open)
		var opened_points_result: Dictionary = _safe_nonnegative_product(units_to_open, unit_value)
		if not bool(opened_points_result.ok):
			return false
		var opened_points: int = int(opened_points_result.value)
		next_items[item_id] = available_units - units_to_open
		if int(next_items[item_id]) <= 0:
			next_items.erase(item_id)
		var used_points: int = mini(opened_points, remaining)
		remaining -= used_points
		var leftover_points: int = opened_points - used_points
		if leftover_points > 0:
			var next_portion_result: Dictionary = _safe_nonnegative_add(
				int(next_portions.get(item_id, 0)), leftover_points
			)
			if not bool(next_portion_result.ok):
				return false
			next_portions[item_id] = int(next_portion_result.value)

	if remaining != 0:
		return false
	_commit_food_consumption(next_items, next_portions)
	return true

## Check a counted-material requirement batch without changing City Storage.
## Empty requirements are a valid no-op.
func can_consume_materials(requirements: Dictionary) -> bool:
	var plan: Dictionary = _material_requirement_plan(requirements)
	if not bool(plan.ok):
		return false
	if plan.item_ids.is_empty():
		return true
	if not _has_valid_counted_stacks():
		return false
	for item_id: String in plan.item_ids:
		if int(items.get(item_id, 0)) < int(plan.quantities[item_id]):
			return false
	return true

## Consume a counted-material requirement batch atomically from City Storage.
## Unique equipment, food portions, and player Inventory are not affected.
func consume_materials(requirements: Dictionary) -> bool:
	if _transfer_in_progress:
		return false
	var plan: Dictionary = _material_requirement_plan(requirements)
	if not bool(plan.ok):
		return false
	var item_ids: Array[String] = plan.item_ids
	if item_ids.is_empty():
		return true
	if not _has_valid_counted_stacks():
		return false
	for item_id: String in item_ids:
		if int(items.get(item_id, 0)) < int(plan.quantities[item_id]):
			return false

	var next_items: Dictionary = items.duplicate(true)
	for item_id: String in item_ids:
		var remaining: int = int(next_items[item_id]) - int(plan.quantities[item_id])
		if remaining > 0:
			next_items[item_id] = remaining
		else:
			next_items.erase(item_id)

	_transfer_in_progress = true
	items = next_items
	changed.emit()
	_transfer_in_progress = false
	return true

## Return a paid material requirement batch atomically to City Storage.
## Overflow or invalid stock rejects the full refund without changing state.
func refund_materials(requirements: Dictionary) -> bool:
	if _transfer_in_progress:
		return false
	var plan: Dictionary = _material_requirement_plan(requirements)
	if not bool(plan.ok):
		return false
	var item_ids: Array[String] = plan.item_ids
	if item_ids.is_empty():
		return true
	if not _has_valid_counted_stacks():
		return false

	var next_items: Dictionary = items.duplicate(true)
	for item_id: String in item_ids:
		var current_quantity: int = int(next_items.get(item_id, 0))
		var next_quantity: Dictionary = _safe_nonnegative_add(
			current_quantity, int(plan.quantities[item_id])
		)
		if not bool(next_quantity.ok):
			return false
		next_items[item_id] = int(next_quantity.value)

	_transfer_in_progress = true
	items = next_items
	changed.emit()
	_transfer_in_progress = false
	return true

## Shared eligibility for personal deposits and incoming Hauler cargo.
## Existing stock is not filtered or removed when this policy changes.
func accepts_item(item_id: String) -> bool:
	var item_data: ItemData = ItemDatabase.get_item_data(item_id)
	return item_data != null and (
		_is_ready_food(item_data) or CLOTHING_ITEM_IDS.has(item_id)
		or item_id == "shekel" or SUPPORTED_ITEM_IDS.has(item_id)
		or item_id == "stone" or item_id == "wood_log"
	)

func get_depositable_items() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for item_id: String in _get_registered_item_ids():
		var item_data: ItemData = ItemDatabase.get_item_data(item_id)
		if not accepts_item(item_id):
			continue
		var quantity_value: Variant = Inventory.items.get(item_id, 0)
		if not quantity_value is int or int(quantity_value) <= 0:
			continue
		rows.append({
			"item_id": item_id,
			"name": item_data.display_name,
			"quantity": int(quantity_value)
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary):
		var name_order: int = str(a.name).naturalnocasecmp_to(str(b.name))
		if name_order != 0:
			return name_order < 0
		return str(a.item_id) < str(b.item_id)
	)
	return rows

func get_available_items() -> Dictionary:
	var quantities: Dictionary = {}
	for item_id: String in _get_registered_item_ids():
		if ItemDatabase.get_item_data(item_id) == null:
			continue
		var quantity: int = _get_available_quantity(item_id)
		if quantity > 0:
			quantities[item_id] = quantity
	return quantities

func deposit_from_inventory(item_id: String, quantity: int = 1) -> Dictionary:
	var result: Dictionary = deposit_items_from_inventory({item_id: quantity})
	if bool(result.ok):
		var item_data: ItemData = ItemDatabase.get_item_data(item_id)
		if item_data != null:
			result.message = "Stored %d %s." % [quantity, item_data.display_name]
	return result

func deposit_items_from_inventory(selected_items: Dictionary) -> Dictionary:
	if _transfer_in_progress:
		return _transfer_result(false, "A City Storage transfer is already in progress.")
	var selection: Dictionary = _validate_selection(selected_items)
	if not bool(selection.ok):
		return _transfer_result(false, str(selection.message))
	var quantities: Dictionary = selection.quantities
	var item_ids: Array[String] = selection.item_ids
	for item_id: String in item_ids:
		var inventory_quantity: Variant = Inventory.items.get(item_id, 0)
		if not inventory_quantity is int:
			return _transfer_result(false, "Inventory quantity is invalid.")
		if int(inventory_quantity) < int(quantities[item_id]):
			return _transfer_result(false, "Inventory does not contain enough of this item.")

	var next_inventory: Dictionary = Inventory.items.duplicate(true)
	var next_units: Dictionary = units.duplicate(true)
	var next_items: Dictionary = items.duplicate(true)
	var next_sequence: int = _unit_sequence
	var unit_ids: Array[String] = []
	for item_id: String in item_ids:
		var quantity: int = int(quantities[item_id])
		var inventory_quantity: int = int(next_inventory.get(item_id, 0)) - quantity
		if inventory_quantity <= 0:
			next_inventory.erase(item_id)
		else:
			next_inventory[item_id] = inventory_quantity
		var item_data: ItemData = ItemDatabase.get_item_data(item_id)
		if not SUPPORTED_ITEM_IDS.has(item_id):
			var stored_quantity: Variant = next_items.get(item_id, 0)
			if not stored_quantity is int or int(stored_quantity) < 0:
				return _transfer_result(false, "City Storage stack quantity is invalid.")
			var next_quantity: Dictionary = _safe_nonnegative_add(int(stored_quantity), quantity)
			if not bool(next_quantity.ok):
				return _transfer_result(false, "City Storage stack quantity would overflow.")
			next_items[item_id] = int(next_quantity.value)
			continue
		for _index: int in range(quantity):
			var generated: Dictionary = _next_unit_id_in_units(item_id, next_units, next_sequence)
			next_sequence = int(generated.sequence)
			var unit_id: String = str(generated.unit_id)
			next_units[unit_id] = {"tool_id": item_id, "name": item_data.display_name, "worker_id": ""}
			unit_ids.append(unit_id)
	_commit_transfer(next_inventory, next_units, next_items, next_sequence)
	return _transfer_result(true, _format_transfer_message("Deposited", quantities, item_ids), unit_ids)

func withdraw_items_to_inventory(_selected_items: Dictionary) -> Dictionary:
	# Keep the old entrypoint for compatibility, but City Storage stock is permanent city property.
	return _transfer_result(false, "City Storage stock belongs to the city and cannot be withdrawn.")

## StorageDestination contract for Hauler cargo. City stock is intentionally unbounded
## until capacity and balance rules are approved; validation remains atomic.
func has_capacity_for(item_id: String, quantity: int) -> bool:
	return _can_receive_item(item_id, quantity)

func try_add_item(item_id: String, quantity: int) -> bool:
	if not has_capacity_for(item_id, quantity):
		return false
	var next_units: Dictionary = units.duplicate(true)
	var next_items: Dictionary = items.duplicate(true)
	var next_sequence: int = _unit_sequence
	var item_data: ItemData = ItemDatabase.get_item_data(item_id)
	if SUPPORTED_ITEM_IDS.has(item_id):
		for _index: int in range(quantity):
			var generated: Dictionary = _next_unit_id_in_units(item_id, next_units, next_sequence)
			next_sequence = int(generated.sequence)
			var unit_id: String = str(generated.unit_id)
			next_units[unit_id] = {"tool_id": item_id, "name": item_data.display_name, "worker_id": ""}
	else:
		var stored_quantity: Variant = next_items.get(item_id, 0)
		# has_capacity_for already rejected invalid current state; keep this guard
		# beside the write so the receipt remains all-or-nothing if state changes.
		if not stored_quantity is int or int(stored_quantity) < 0:
			return false
		var next_quantity: Dictionary = _safe_nonnegative_add(int(stored_quantity), quantity)
		if not bool(next_quantity.ok):
			return false
		next_items[item_id] = int(next_quantity.value)
	_commit_city_receipt(next_units, next_items, next_sequence)
	return true

func add_tool_unit(unit_id: String, tool_id: String, display_name: String) -> bool:
	if _transfer_in_progress or unit_id.is_empty() or tool_id.is_empty() or units.has(unit_id):
		return false
	if not SUPPORTED_ITEM_IDS.has(tool_id) or not accepts_item(tool_id):
		return false
	units[unit_id] = {"tool_id": tool_id, "name": display_name, "worker_id": ""}
	changed.emit()
	return true

func allocate(unit_id: String, worker_id: String) -> bool:
	if _transfer_in_progress or worker_id.is_empty() or not units.has(unit_id) or not str(units[unit_id].worker_id).is_empty():
		return false
	units[unit_id].worker_id = worker_id
	changed.emit()
	return true

func release(unit_id: String, worker_id: String) -> bool:
	if _transfer_in_progress or not units.has(unit_id) or units[unit_id].worker_id != worker_id:
		return false
	units[unit_id].worker_id = ""
	changed.emit()
	return true

func has_equipped(worker_id: String, tool_id: String) -> bool:
	for unit: Dictionary in units.values():
		if unit.worker_id == worker_id and unit.tool_id == tool_id:
			return true
	return false

func _validate_selection(selected_items: Dictionary) -> Dictionary:
	if selected_items.is_empty():
		return {"ok": false, "message": "Select at least one item."}
	var quantities: Dictionary = {}
	var item_ids: Array[String] = []
	for item_id_value in selected_items.keys():
		if not item_id_value is String:
			return {"ok": false, "message": "Item identifiers must be strings."}
		var item_id: String = item_id_value
		if ItemDatabase.get_item_data(item_id) == null:
			return {"ok": false, "message": "This item is not registered."}
		if not accepts_item(item_id):
			return {"ok": false, "message": "City Storage does not accept %s." % ItemDatabase.get_item_data(item_id).display_name}
		var quantity_value: Variant = selected_items[item_id_value]
		if not quantity_value is int or int(quantity_value) <= 0:
			return {"ok": false, "message": "Item quantities must be positive integers."}
		quantities[item_id] = int(quantity_value)
		item_ids.append(item_id)
	item_ids.sort()
	return {"ok": true, "message": "", "quantities": quantities, "item_ids": item_ids}

func _material_requirement_plan(requirements: Dictionary) -> Dictionary:
	if _transfer_in_progress:
		return {"ok": false}
	var quantities: Dictionary = {}
	var item_ids: Array[String] = []
	for item_id_value: Variant in requirements.keys():
		if not item_id_value is String:
			return {"ok": false}
		var item_id: String = item_id_value
		var item_data: ItemData = ItemDatabase.get_item_data(item_id)
		if not _is_counted_material(item_id, item_data):
			return {"ok": false}
		var quantity_value: Variant = requirements[item_id_value]
		if not quantity_value is int or int(quantity_value) <= 0:
			return {"ok": false}
		quantities[item_id] = int(quantity_value)
		item_ids.append(item_id)
	item_ids.sort()
	return {"ok": true, "quantities": quantities, "item_ids": item_ids}

func _is_counted_material(item_id: String, item_data: ItemData) -> bool:
	return item_data != null \
		and item_data.category == ItemEnums.ItemCategory.RESOURCE \
		and item_data.food_supply_value <= 0 \
		and item_data.clothing_supply_value <= 0 \
		and item_id != "shekel" \
		and not CLOTHING_ITEM_IDS.has(item_id) \
		and not SUPPORTED_ITEM_IDS.has(item_id)

func _is_valid_raid_loot_request(remaining_weight: float, preference: String) -> bool:
	return is_finite(remaining_weight) and remaining_weight >= 0.0 \
		and ["balanced", "food", "valuables"].has(preference)

func _get_ranked_raid_loot_candidates(remaining_weight: float, preference: String) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if not _has_valid_counted_stacks():
		return candidates

	for item_id_value: Variant in items.keys():
		var item_id: String = item_id_value
		var quantity: int = int(items[item_id_value])
		if quantity <= 0 or SUPPORTED_ITEM_IDS.has(item_id):
			continue
		var item_data: ItemData = ItemDatabase.get_item_data(item_id)
		if not _is_valid_raid_loot_metadata(item_id, item_data):
			continue
		var item_weight: float = item_data.weight
		if item_weight > 0.0 and item_weight > remaining_weight + 0.000001:
			continue
		var divisor: float = item_weight if item_weight > 0.0 else 1.0
		var value_score: float = _raid_loot_value_score(item_data, divisor, preference)
		if not is_finite(value_score):
			continue
		candidates.append({
			"item_id": item_id,
			"weight": item_weight,
			"rarity": int(item_data.rarity),
			"food_priority": item_data.food_supply_value > 0,
			"score": value_score,
			"reason": _raid_loot_reason(item_data, preference)
		})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if preference == "food" and bool(a.food_priority) != bool(b.food_priority):
			return bool(a.food_priority)
		if float(a.score) != float(b.score):
			return float(a.score) > float(b.score)
		if int(a.rarity) != int(b.rarity):
			return int(a.rarity) > int(b.rarity)
		return str(a.item_id) < str(b.item_id)
	)
	return candidates

func _is_valid_raid_loot_metadata(item_id: String, item_data: ItemData) -> bool:
	return item_data != null \
		and item_data.id == item_id \
		and is_finite(item_data.weight) \
		and item_data.weight >= 0.0 \
		and item_data.base_value_shekel >= 0 \
		and item_data.food_supply_value >= 0 \
		and item_data.rarity >= ItemEnums.Rarity.COMMON \
		and item_data.rarity <= ItemEnums.Rarity.MYTHIC \
		and item_data.category >= ItemEnums.ItemCategory.RESOURCE \
		and item_data.category <= ItemEnums.ItemCategory.KEY_ITEM

func _raid_loot_value_score(item_data: ItemData, divisor: float, preference: String) -> float:
	if preference == "valuables":
		return float(item_data.base_value_shekel)
	if preference == "food":
		return float(item_data.base_value_shekel) / divisor
	return float(maxi(item_data.base_value_shekel, item_data.food_supply_value)) / divisor

func _raid_loot_reason(item_data: ItemData, preference: String) -> String:
	if preference == "food" and item_data.food_supply_value > 0:
		return "food supply"
	if preference == "valuables":
		return "base value"
	return "value per weight"

func _get_registered_item_ids() -> Array[String]:
	var item_ids: Array[String] = []
	for item_value in ItemDatabase.get_all_items():
		if not item_value is ItemData:
			continue
		var item_data: ItemData = item_value
		if not item_data.id.is_empty():
			item_ids.append(item_data.id)
	item_ids.sort()
	return item_ids

func _get_available_quantity(item_id: String) -> int:
	if SUPPORTED_ITEM_IDS.has(item_id):
		var quantity: int = 0
		for unit_value in units.values():
			if not unit_value is Dictionary:
				continue
			var unit: Dictionary = unit_value
			if str(unit.get("tool_id", "")) != item_id:
				continue
			if not str(unit.get("worker_id", "")).is_empty():
				continue
			quantity += 1
		return quantity
	var stored_quantity: Variant = items.get(item_id, 0)
	if not stored_quantity is int or int(stored_quantity) <= 0:
		return 0
	return int(stored_quantity)

func _can_receive_item(item_id: String, quantity: int) -> bool:
	if _transfer_in_progress or item_id.is_empty() or quantity <= 0:
		return false
	if not accepts_item(item_id):
		return false
	if not _has_valid_counted_stacks():
		return false
	if SUPPORTED_ITEM_IDS.has(item_id):
		return true
	var stored_quantity: Variant = items.get(item_id, 0)
	if not stored_quantity is int or int(stored_quantity) < 0:
		return false
	var next_quantity: Dictionary = _safe_nonnegative_add(int(stored_quantity), quantity)
	return bool(next_quantity.ok)

func _has_valid_counted_stacks() -> bool:
	for item_id_value in items.keys():
		if not item_id_value is String:
			return false
		var item_id: String = item_id_value
		if ItemDatabase.get_item_data(item_id) == null:
			return false
		var stored_quantity: Variant = items[item_id_value]
		if not stored_quantity is int or int(stored_quantity) < 0:
			return false
	return true

func _get_available_unit_ids(item_id: String, source_units: Dictionary) -> Array[String]:
	var available_unit_ids: Array[String] = []
	for unit_id_value in source_units.keys():
		var unit_id: String = str(unit_id_value)
		var unit_value: Variant = source_units[unit_id_value]
		if not unit_value is Dictionary:
			continue
		var unit: Dictionary = unit_value
		if str(unit.get("tool_id", "")) != item_id:
			continue
		if not str(unit.get("worker_id", "")).is_empty():
			continue
		available_unit_ids.append(unit_id)
	available_unit_ids.sort()
	return available_unit_ids

func _next_unit_id_in_units(item_id: String, target_units: Dictionary, starting_sequence: int) -> Dictionary:
	var sequence: int = starting_sequence
	var candidate: String = ""
	while target_units.has(candidate) or candidate.is_empty():
		sequence += 1
		candidate = "city_tool_%s_%d" % [item_id, sequence]
	return {"unit_id": candidate, "sequence": sequence}

func _commit_transfer(next_inventory: Dictionary, next_units: Dictionary, next_items: Dictionary, next_sequence: int) -> void:
	_transfer_in_progress = true
	units = next_units
	items = next_items
	_unit_sequence = next_sequence
	Inventory.items.assign(next_inventory)
	Inventory.items_changed.emit()
	changed.emit()
	_transfer_in_progress = false

func _commit_city_receipt(next_units: Dictionary, next_items: Dictionary, next_sequence: int) -> void:
	_transfer_in_progress = true
	units = next_units
	items = next_items
	_unit_sequence = next_sequence
	changed.emit()
	_transfer_in_progress = false

func _commit_food_consumption(next_items: Dictionary, next_portions: Dictionary) -> void:
	_transfer_in_progress = true
	items = next_items
	food_portions = next_portions
	changed.emit()
	_transfer_in_progress = false

func _commit_clothing_consumption(next_items: Dictionary) -> void:
	_transfer_in_progress = true
	items = next_items
	changed.emit()
	_transfer_in_progress = false

func _is_ready_food(item_data: ItemData) -> bool:
	return item_data != null \
		and item_data.category == ItemEnums.ItemCategory.CONSUMABLE \
		and item_data.food_supply_value > 0

func _safe_nonnegative_add(left: int, right: int) -> Dictionary:
	if left < 0 or right < 0 or left > MAX_INT_VALUE - right:
		return {"ok": false}
	return {"ok": true, "value": left + right}

func _safe_nonnegative_product(left: int, right: int) -> Dictionary:
	if left < 0 or right < 0:
		return {"ok": false}
	if left == 0 or right == 0:
		return {"ok": true, "value": 0}
	# Integer floor is intentional: multiplication must fit before it is performed.
	@warning_ignore("integer_division")
	var largest_left: int = MAX_INT_VALUE / right
	if left > largest_left:
		return {"ok": false}
	return {"ok": true, "value": left * right}

func _divide_nonnegative(numerator: int, denominator: int) -> Dictionary:
	if numerator < 0 or denominator <= 0:
		return {"ok": false}
	@warning_ignore("integer_division")
	var quotient: int = numerator / denominator
	return {
		"ok": true,
		"quotient": quotient,
		"remainder": numerator % denominator
	}

func _validated_food_state() -> Dictionary:
	var whole_points: int = 0
	for item_id_value: Variant in items.keys():
		if not item_id_value is String:
			return {"ok": false}
		var item_id: String = item_id_value
		var item_data: ItemData = ItemDatabase.get_item_data(item_id)
		var quantity_value: Variant = items[item_id_value]
		if item_data == null or not quantity_value is int or int(quantity_value) < 0:
			return {"ok": false}
		if _is_ready_food(item_data):
			var item_points: Dictionary = _safe_nonnegative_product(
				int(quantity_value), item_data.food_supply_value
			)
			if not bool(item_points.ok):
				return {"ok": false}
			var next_whole_points: Dictionary = _safe_nonnegative_add(
				whole_points, int(item_points.value)
			)
			if not bool(next_whole_points.ok):
				return {"ok": false}
			whole_points = int(next_whole_points.value)

	var portion_points: int = 0
	for item_id_value: Variant in food_portions.keys():
		if not item_id_value is String:
			return {"ok": false}
		var item_id: String = item_id_value
		var item_data: ItemData = ItemDatabase.get_item_data(item_id)
		var portion_value: Variant = food_portions[item_id_value]
		if not _is_ready_food(item_data) or not portion_value is int:
			return {"ok": false}
		var portion_points_for_item: int = int(portion_value)
		if portion_points_for_item <= 0 or portion_points_for_item >= item_data.food_supply_value:
			return {"ok": false}
		var next_portion_points: Dictionary = _safe_nonnegative_add(
			portion_points, portion_points_for_item
		)
		if not bool(next_portion_points.ok):
			return {"ok": false}
		portion_points = int(next_portion_points.value)

	var total_points: Dictionary = _safe_nonnegative_add(whole_points, portion_points)
	if not bool(total_points.ok):
		return {"ok": false}

	return {
		"ok": true,
		"whole_points": whole_points,
		"portion_points": portion_points,
		"total_points": int(total_points.value)
	}

func _validated_clothing_state() -> Dictionary:
	if not _has_valid_counted_stacks():
		return {"ok": false, "count": 0}
	var count: int = 0
	for item_id: String in CLOTHING_ITEM_IDS:
		var quantity: int = int(items.get(item_id, 0))
		if quantity < 0 or count > MAX_INT_VALUE - quantity:
			return {"ok": false, "count": 0}
		count += quantity
	return {"ok": true, "count": count}

func _format_transfer_message(verb: String, quantities: Dictionary, item_ids: Array[String]) -> String:
	var item_text: PackedStringArray = []
	for item_id: String in item_ids:
		var item_data: ItemData = ItemDatabase.get_item_data(item_id)
		var display_name: String = item_id
		if item_data != null:
			display_name = item_data.display_name
		item_text.append("%d %s" % [int(quantities[item_id]), display_name])
	return "%s %s." % [verb, ", ".join(item_text)]

func _transfer_result(ok: bool, message: String, unit_ids: Array[String] = []) -> Dictionary:
	return {"ok": ok, "message": message, "unit_ids": unit_ids}
