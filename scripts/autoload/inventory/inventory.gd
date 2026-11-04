extends Node

signal items_changed()

var items: Dictionary[String, int] = {}
var max_load: float = 100.0
const MAX_INT_VALUE: int = 9223372036854775807
var _bulk_transaction_in_progress: bool = false

func _emit_items_changed() -> void:
	emit_signal("items_changed")

func has_item(id: String, qty: int) -> bool:
	if qty <= 0:
		return true
	return items.get(id, 0) >= qty

func get_item_data(item_id: String) -> ItemData:
	if not ItemDatabase:
		push_error("Item Database not exist")
		return null

	if item_id == "":
		return null

	return ItemDatabase.get_item_data(item_id)

func get_item_total_weight(item_id: String, qty: int) -> float:

	if item_id == "" or qty <= 0:
		return 0.0

	var item_data: ItemData = get_item_data(item_id)
	if item_data == null:
		return 0.0

	if item_data.weight <= 0.0:
		return 0.0

	return item_data.weight * qty

func get_bulk_item_total_weight(items_to_check: Dictionary) -> float:
	var total_weight: float = 0.0
	for item_id in items_to_check.keys():
		var qty: int = int(items_to_check[item_id])
		total_weight += get_item_total_weight(item_id, qty)
	return total_weight

func get_total_inventory_weight() -> float:
	var total_weight: float = 0.0

	for item in items.keys():
		total_weight += get_item_total_weight(item, items[item])

	return total_weight

func get_remaining_capacity() -> float:
	var total_weight: float = get_total_inventory_weight()

	return max_load - total_weight

func has_capacity_for(item_id: String, qty: int) -> bool:
	return get_remaining_capacity() >= get_item_total_weight(item_id, qty)

func try_add_item(item_id: String, qty: int) -> bool:
	if _bulk_transaction_in_progress:
		return false
	if item_id == "" or qty <= 0:
		return false

	if get_item_data(item_id) == null:
		return false

	if get_item_data(item_id).weight < 0.0:
		return false

	if not has_capacity_for(item_id, qty):
		return false

	add_item(item_id, qty)
	return true

func add_item(id: String, qty: int) -> void:
	if _bulk_transaction_in_progress or qty <= 0:
		return # tidak melakukan apa-apa kalau qty tidak valid
	items[id] = items.get(id, 0) + qty # tambah stok dengan aman (auto buat key jika belum ada)
	_emit_items_changed()

func add_bulk_item(items_to_add: Dictionary) -> void:
	if _bulk_transaction_in_progress:
		return
	var has_mutation: bool = false
	for item_identifier in items_to_add.keys():
		var qty: int = int(items_to_add[item_identifier])
		if qty <= 0: continue
		items[item_identifier] = items.get(item_identifier, 0) + qty
		has_mutation = true

	if has_mutation:
		_emit_items_changed()

func remove_item(id: String, qty: int) -> bool:
	if _bulk_transaction_in_progress:
		return false
	if qty <= 0:
		return true

	var current: int = items.get(id, 0)
	if current < qty:
		return false
	var new_qty: int = current - qty
	if new_qty <= 0:
		items.erase(id) # kalau habis, hapus key biar bersih
	else:
		items[id] = new_qty
	_emit_items_changed()

	return true

## Check a complete counted-item payment without changing Inventory.
func can_consume_bulk_items(requirements: Dictionary) -> bool:
	if _bulk_transaction_in_progress:
		return false
	var plan: Dictionary = _bulk_item_plan(requirements)
	if not bool(plan.ok):
		return false
	for item_id: String in plan.quantities:
		if int(items.get(item_id, 0)) < int(plan.quantities[item_id]):
			return false
	return true

## Consume a complete payment atomically and publish one items_changed signal.
func consume_bulk_items(requirements: Dictionary) -> bool:
	if _bulk_transaction_in_progress:
		return false
	var plan: Dictionary = _bulk_item_plan(requirements)
	if not bool(plan.ok):
		return false
	for item_id: String in plan.quantities:
		if int(items.get(item_id, 0)) < int(plan.quantities[item_id]):
			return false
	if plan.quantities.is_empty():
		return true
	var next_items: Dictionary[String, int] = items.duplicate(true)
	for item_id: String in plan.quantities:
		var remaining: int = int(next_items[item_id]) - int(plan.quantities[item_id])
		if remaining > 0:
			next_items[item_id] = remaining
		else:
			next_items.erase(item_id)
	_publish_bulk_items(next_items)
	return true

## Return a complete counted-item payment atomically if weight capacity permits.
func refund_bulk_items(additions: Dictionary) -> bool:
	return _add_bulk_items(additions)

## Add a complete counted-item batch atomically if weight capacity permits.
func try_add_bulk_items(additions: Dictionary) -> bool:
	return _add_bulk_items(additions)

func _add_bulk_items(additions: Dictionary) -> bool:
	if _bulk_transaction_in_progress:
		return false
	var plan: Dictionary = _bulk_item_plan(additions)
	if not bool(plan.ok):
		return false
	if plan.quantities.is_empty():
		return true
	var next_items: Dictionary[String, int] = items.duplicate(true)
	for item_id: String in plan.quantities:
		var current: int = int(next_items.get(item_id, 0))
		var next_quantity: int = int(plan.quantities[item_id])
		if current > MAX_INT_VALUE - next_quantity:
			return false
		next_items[item_id] = current + next_quantity
	var projected_weight: float = _bulk_items_weight(next_items)
	if not is_finite(projected_weight) or not is_finite(max_load) or max_load < 0.0 or projected_weight > max_load:
		return false
	_publish_bulk_items(next_items)
	return true

func _bulk_item_plan(requirements: Dictionary) -> Dictionary:
	if not requirements is Dictionary:
		return {"ok": false, "quantities": {}}
	var quantities: Dictionary[String, int] = {}
	for item_id_value: Variant in requirements:
		if not item_id_value is String or item_id_value.is_empty():
			return {"ok": false, "quantities": {}}
		var quantity: Variant = requirements[item_id_value]
		if not quantity is int or quantity <= 0:
			return {"ok": false, "quantities": {}}
		var item: ItemData = get_item_data(item_id_value)
		if item == null or not is_finite(item.weight) or item.weight < 0.0:
			return {"ok": false, "quantities": {}}
		quantities[item_id_value] = quantity
	for existing_id_value: Variant in items:
		if not existing_id_value is String or get_item_data(existing_id_value) == null:
			return {"ok": false, "quantities": {}}
		var current: Variant = items[existing_id_value]
		if not current is int or current < 0:
			return {"ok": false, "quantities": {}}
		var existing_item: ItemData = get_item_data(existing_id_value)
		if not is_finite(existing_item.weight) or existing_item.weight < 0.0:
			return {"ok": false, "quantities": {}}
	return {"ok": true, "quantities": quantities}

func _bulk_items_weight(value: Dictionary) -> float:
	var total: float = 0.0
	for item_id_value: Variant in value:
		var item: ItemData = get_item_data(str(item_id_value))
		if item == null:
			return INF
		total += item.weight * int(value[item_id_value])
		if not is_finite(total):
			return INF
	return total

func _publish_bulk_items(next_items: Dictionary[String, int]) -> void:
	_bulk_transaction_in_progress = true
	items = next_items
	_emit_items_changed()
	_bulk_transaction_in_progress = false
