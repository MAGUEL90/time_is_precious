extends Node

const STORAGE_SCRIPT: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")
const MAX_INT_VALUE: int = 9223372036854775807

var failures: int = 0
var storage_changed_count: int = 0
var inventory_changed_count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var storage: Node = STORAGE_SCRIPT.new()
	add_child(storage)
	storage.changed.connect(_on_storage_changed)
	Inventory.items_changed.connect(_on_inventory_changed)

	_test_overflowing_deposit(storage)
	_test_exact_max_deposit(storage)
	_test_batch_deposit_atomicity(storage)
	_test_cargo_receipt(storage)
	_test_malformed_stack_validation(storage)
	_test_invalid_deposit_quantities(storage)

	Inventory.items_changed.disconnect(_on_inventory_changed)
	print("CityStorageOverflowTest %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)


func _test_overflowing_deposit(storage: Node) -> void:
	_reset(storage, {"barley_bread": MAX_INT_VALUE - 1}, {"barley_bread": 2})
	var items_before: Dictionary = storage.items.duplicate(true)
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	var units_before: Dictionary = storage.units.duplicate(true)
	var portions_before: Dictionary = storage.food_portions.duplicate(true)
	var sequence_before: int = int(storage._unit_sequence)
	var result: Dictionary = storage.deposit_items_from_inventory({"barley_bread": 2})
	_expect(not bool(result.ok), "Deposit rejects a counted stack addition above INT64_MAX.")
	_expect(storage.items == items_before and Inventory.items == inventory_before
		and storage.units == units_before and storage.food_portions == portions_before
		and int(storage._unit_sequence) == sequence_before,
		"Overflowing deposit preserves all City Storage and Inventory state.")
	_expect(storage_changed_count == 0 and inventory_changed_count == 0,
		"Overflowing deposit emits neither storage nor inventory notifications.")


func _test_exact_max_deposit(storage: Node) -> void:
	_reset(storage, {"barley_bread": MAX_INT_VALUE - 1}, {"barley_bread": 1})
	var result: Dictionary = storage.deposit_items_from_inventory({"barley_bread": 1})
	_expect(bool(result.ok) and int(storage.items.get("barley_bread", 0)) == MAX_INT_VALUE,
		"Deposit accepts a counted stack that reaches INT64_MAX exactly.")
	_expect(Inventory.items.is_empty(), "Successful exact-maximum deposit removes the selected inventory item.")
	_expect(storage_changed_count == 1 and inventory_changed_count == 1,
		"Successful exact-maximum deposit emits one notification from each owner.")


func _test_batch_deposit_atomicity(storage: Node) -> void:
	_reset(storage,
		{"barley_bread": MAX_INT_VALUE - 1, "simple_clothes": 7},
		{"barley_bread": 2, "simple_clothes": 3}
	)
	var items_before: Dictionary = storage.items.duplicate(true)
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	var result: Dictionary = storage.deposit_items_from_inventory({
		"barley_bread": 2,
		"simple_clothes": 2
	})
	_expect(not bool(result.ok), "Mixed batch deposit rejects when one counted stack would overflow.")
	_expect(storage.items == items_before and Inventory.items == inventory_before
		and storage.units.is_empty() and storage.food_portions.is_empty()
		and int(storage._unit_sequence) == 0,
		"Overflow in one batch entry leaves every selected item unchanged.")
	_expect(storage_changed_count == 0 and inventory_changed_count == 0,
		"Rejected mixed batch emits no notifications.")


func _test_cargo_receipt(storage: Node) -> void:
	_reset(storage, {"barley_bread": MAX_INT_VALUE - 1}, {"barley_bread": 9})
	var items_before: Dictionary = storage.items.duplicate(true)
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	_expect(not storage.has_capacity_for("barley_bread", 2),
		"Cargo capacity preflight rejects a counted stack overflow.")
	_expect(not storage.try_add_item("barley_bread", 2),
		"Cargo receipt rejects a counted stack overflow.")
	_expect(storage.items == items_before and Inventory.items == inventory_before
		and storage.units.is_empty() and int(storage._unit_sequence) == 0,
		"Rejected cargo receipt preserves City Storage and Inventory state.")
	_expect(storage_changed_count == 0 and inventory_changed_count == 0,
		"Rejected cargo receipt emits no notifications.")
	_expect(storage.has_capacity_for("barley_bread", 1),
		"Cargo preflight accepts a counted stack addition reaching INT64_MAX.")
	_expect(storage.try_add_item("barley_bread", 1)
		and int(storage.items.get("barley_bread", 0)) == MAX_INT_VALUE,
		"Cargo receipt accepts a counted stack addition reaching INT64_MAX exactly.")
	_expect(Inventory.items == inventory_before and storage_changed_count == 1
		and inventory_changed_count == 0,
		"Successful cargo receipt changes City Storage only and emits one storage notification.")


func _test_malformed_stack_validation(storage: Node) -> void:
	_reset(storage, {"barley_bread": "malformed"}, {"barley_bread": 1})
	var items_before: Dictionary = storage.items.duplicate(true)
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	_expect(not storage.has_capacity_for("barley_bread", 1)
		and not storage.try_add_item("barley_bread", 1),
		"Cargo validation continues to reject a malformed counted stack.")
	var result: Dictionary = storage.deposit_items_from_inventory({"barley_bread": 1})
	_expect(not bool(result.ok), "Deposit validation continues to reject a malformed counted stack.")
	_expect(storage.items == items_before and Inventory.items == inventory_before
		and storage_changed_count == 0 and inventory_changed_count == 0,
		"Malformed stack rejection preserves state and emits no notifications.")


func _test_invalid_deposit_quantities(storage: Node) -> void:
	_reset(storage, {}, {"barley_bread": 2})
	var items_before: Dictionary = storage.items.duplicate(true)
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	var zero_result: Dictionary = storage.deposit_items_from_inventory({"barley_bread": 0})
	var non_integer_result: Dictionary = storage.deposit_items_from_inventory({"barley_bread": "1"})
	_expect(not bool(zero_result.ok) and not bool(non_integer_result.ok),
		"Deposit continues to reject zero and non-integer selected quantities.")
	_expect(storage.items == items_before and Inventory.items == inventory_before
		and storage_changed_count == 0 and inventory_changed_count == 0,
		"Invalid selected quantities preserve state and emit no notifications.")


func _reset(storage: Node, city_items: Dictionary, inventory_items: Dictionary) -> void:
	storage.units.clear()
	storage.items = city_items.duplicate(true)
	storage.food_portions.clear()
	storage._unit_sequence = 0
	Inventory.items.clear()
	Inventory.items.assign(inventory_items)
	storage_changed_count = 0
	inventory_changed_count = 0


func _on_storage_changed() -> void:
	storage_changed_count += 1


func _on_inventory_changed() -> void:
	inventory_changed_count += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
