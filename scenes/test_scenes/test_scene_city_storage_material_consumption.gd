extends Node

const STORAGE_SCRIPT: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")
const MAX_INT_VALUE: int = 9223372036854775807

var failures: int = 0
var storage_changed_count: int = 0
var inventory_before: Dictionary = {}
var storage: Node
var attempt_reentrant_changes: bool = false
var reentrant_can_consume_result: bool = true
var reentrant_consume_result: bool = true
var reentrant_refund_result: bool = true


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	storage = STORAGE_SCRIPT.new()
	add_child(storage)
	storage.changed.connect(_on_storage_changed)
	inventory_before = Inventory.items.duplicate(true)

	_test_empty_requirements()
	_test_invalid_requirements()
	_test_transfer_lock()
	_test_atomic_shortage()
	_test_invalid_stored_stack()
	_test_unique_equipment_protection()
	_test_atomic_overflowing_refund()
	_test_consume_and_refund_conservation()
	_test_inventory_deposit_then_consume()
	Inventory.items.assign(inventory_before)

	_expect(Inventory.items == inventory_before,
		"Material consumption and refunds preserve player Inventory outside the explicit deposit.")
	print("CityStorageMaterialConsumptionTest %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)


func _test_empty_requirements() -> void:
	_reset({"stone": 4, "wood_log": 3})
	var items_before: Dictionary = storage.items.duplicate(true)
	_expect(storage.can_consume_materials({}) and storage.consume_materials({})
		and storage.refund_materials({}), "Empty material requirements are successful no-ops.")
	_expect(storage.items == items_before and storage_changed_count == 0,
		"Empty material requirements do not change storage or emit a notification.")


func _test_invalid_requirements() -> void:
	_reset({"stone": 10, "wood_log": 10})
	var invalid_batches: Array[Dictionary] = [
		{"stone": 0},
		{"stone": -1},
		{"stone": 1.5},
		{"stone": "1"},
		{"missing_wall_material": 1},
		{1: 1},
		{"cart": 1}
	]
	var items_before: Dictionary = storage.items.duplicate(true)
	for requirements: Dictionary in invalid_batches:
		_expect(not storage.can_consume_materials(requirements)
			and not storage.consume_materials(requirements)
			and not storage.refund_materials(requirements),
			"Invalid material identifiers and quantities are rejected: %s." % str(requirements))
	_expect(storage.items == items_before and storage_changed_count == 0,
		"Invalid material batches preserve all storage and emit no notification.")


func _test_transfer_lock() -> void:
	_reset({"stone": 4, "wood_log": 3})
	var items_before: Dictionary = storage.items.duplicate(true)
	storage._transfer_in_progress = true
	_expect(not storage.can_consume_materials({"stone": 1})
		and not storage.consume_materials({"stone": 1})
		and not storage.refund_materials({"stone": 1}),
		"Material operations reject while a City Storage transfer is in progress.")
	storage._transfer_in_progress = false
	_expect(storage.items == items_before and storage_changed_count == 0,
		"Transfer-lock rejection preserves stock and emits no notification.")


func _test_atomic_shortage() -> void:
	_reset({"stone": 5, "wood_log": 2})
	var items_before: Dictionary = storage.items.duplicate(true)
	var units_before: Dictionary = storage.units.duplicate(true)
	var portions_before: Dictionary = storage.food_portions.duplicate(true)
	var requirements: Dictionary = {"stone": 3, "wood_log": 3}
	_expect(not storage.can_consume_materials(requirements)
		and not storage.consume_materials(requirements),
		"A multi-material batch is rejected when one stack is short.")
	_expect(storage.items == items_before and storage.units == units_before
		and storage.food_portions == portions_before and storage_changed_count == 0,
		"Shortage preserves every material stack, equipment unit, and food portion.")


func _test_invalid_stored_stack() -> void:
	_reset({"stone": "broken", "wood_log": 4})
	var items_before: Dictionary = storage.items.duplicate(true)
	_expect(not storage.can_consume_materials({"wood_log": 1})
		and not storage.consume_materials({"wood_log": 1})
		and not storage.refund_materials({"wood_log": 1}),
		"Material operations reject storage with an invalid counted stack.")
	_expect(storage.items == items_before and storage_changed_count == 0,
		"Invalid stored-stack rejection leaves all stock untouched.")


func _test_unique_equipment_protection() -> void:
	_reset({"stone": 2, "wood_log": 2, "stone_hammer": 1})
	var items_before: Dictionary = storage.items.duplicate(true)
	var units_before: Dictionary = storage.units.duplicate(true)
	_expect(not storage.can_consume_materials({"stone_hammer": 1})
		and not storage.consume_materials({"stone_hammer": 1})
		and not storage.refund_materials({"cart": 1}),
		"Supported unique equipment cannot be treated as counted material stock.")
	_expect(storage.items == items_before and storage.units == units_before
		and storage_changed_count == 0,
		"Equipment rejection preserves counted stacks and allocated equipment units.")


func _test_atomic_overflowing_refund() -> void:
	_reset({"stone": 4, "wood_log": MAX_INT_VALUE})
	var items_before: Dictionary = storage.items.duplicate(true)
	var units_before: Dictionary = storage.units.duplicate(true)
	var portions_before: Dictionary = storage.food_portions.duplicate(true)
	_expect(not storage.refund_materials({"stone": 1, "wood_log": 1}),
		"Refund rejects the whole batch when one counted stack would overflow.")
	_expect(storage.items == items_before and storage.units == units_before
		and storage.food_portions == portions_before and storage_changed_count == 0,
		"Overflowing refund preserves all storage state and emits no notification.")


func _test_consume_and_refund_conservation() -> void:
	_reset({"stone": 4, "wood_log": 3})
	var units_before: Dictionary = storage.units.duplicate(true)
	var portions_before: Dictionary = storage.food_portions.duplicate(true)
	attempt_reentrant_changes = true
	reentrant_can_consume_result = true
	reentrant_consume_result = true
	reentrant_refund_result = true
	var consumed: bool = storage.consume_materials({"stone": 2, "wood_log": 1})
	attempt_reentrant_changes = false
	_expect(consumed and storage.items == {"stone": 2, "wood_log": 2},
		"Successful multi-material consumption removes exactly the requested quantities.")
	_expect(storage_changed_count == 1 and not reentrant_can_consume_result
		and not reentrant_consume_result
		and not reentrant_refund_result,
		"Consumption emits one notification and rejects reentrant consume/refund calls.")
	_expect(storage.units == units_before and storage.food_portions == portions_before
		and Inventory.items == inventory_before,
		"Successful consumption leaves equipment, food portions, and Inventory unchanged.")

	storage_changed_count = 0
	attempt_reentrant_changes = true
	reentrant_can_consume_result = true
	reentrant_consume_result = true
	reentrant_refund_result = true
	var refunded: bool = storage.refund_materials({"stone": 2, "wood_log": 1})
	attempt_reentrant_changes = false
	_expect(refunded and storage.items == {"stone": 4, "wood_log": 3},
		"Successful refund restores the exact consumed material quantities.")
	_expect(storage_changed_count == 1 and not reentrant_can_consume_result
		and not reentrant_consume_result
		and not reentrant_refund_result,
		"Refund emits one notification and rejects reentrant consume/refund calls.")
	_expect(storage.units == units_before and storage.food_portions == portions_before
		and Inventory.items == inventory_before,
		"Successful refund leaves equipment, food portions, and Inventory unchanged.")


func _test_inventory_deposit_then_consume() -> void:
	_reset({})
	_expect(storage.accepts_item("stone") and storage.accepts_item("wood_log"),
		"City Storage accepts the two approved counted construction materials.")
	_expect(not storage.accepts_item("clay_lump") and storage.accepts_item("barley_bread")
		and storage.accepts_item("stone_hammer"),
		"The material intake exception preserves raw-resource filtering, food, and equipment acceptance.")

	var inventory_for_deposit: Dictionary = inventory_before.duplicate(true)
	inventory_for_deposit["stone"] = int(inventory_for_deposit.get("stone", 0)) + 3
	inventory_for_deposit["wood_log"] = int(inventory_for_deposit.get("wood_log", 0)) + 2
	inventory_for_deposit["clay_lump"] = int(inventory_for_deposit.get("clay_lump", 0)) + 1
	Inventory.items.assign(inventory_for_deposit)
	var units_before: Dictionary = storage.units.duplicate(true)
	var portions_before: Dictionary = storage.food_portions.duplicate(true)
	var deposit_result: Dictionary = storage.deposit_items_from_inventory({"stone": 2, "wood_log": 1})
	var inventory_after_deposit: Dictionary = inventory_for_deposit.duplicate(true)
	inventory_after_deposit["stone"] = int(inventory_after_deposit["stone"]) - 2
	inventory_after_deposit["wood_log"] = int(inventory_after_deposit["wood_log"]) - 1
	_expect(bool(deposit_result.ok) and storage.items == {"stone": 2, "wood_log": 1},
		"Public Inventory deposit stores the selected stone and wood-log quantities.")
	_expect(Inventory.items == inventory_after_deposit and storage_changed_count == 1,
		"Successful material deposit removes exactly the selected Inventory quantities and notifies once.")
	var storage_after_material_deposit: Dictionary = storage.items.duplicate(true)
	var rejected_raw_material: Dictionary = storage.deposit_items_from_inventory({"clay_lump": 1})
	_expect(not bool(rejected_raw_material.ok) and storage.items == storage_after_material_deposit
		and Inventory.items == inventory_after_deposit and storage_changed_count == 1,
		"Public Inventory deposit still rejects non-approved raw material without changing either owner.")
	_expect(storage.units == units_before and storage.food_portions == portions_before,
		"Material deposit leaves unique equipment and food portions untouched.")

	storage_changed_count = 0
	var inventory_before_consumption: Dictionary = Inventory.items.duplicate(true)
	_expect(storage.consume_materials({"stone": 2, "wood_log": 1}) and storage.items.is_empty(),
		"Deposited materials can be consumed through the counted-material API.")
	_expect(Inventory.items == inventory_before_consumption and storage_changed_count == 1,
		"Consuming deposited materials changes City Storage only and notifies once.")


func _reset(next_items: Dictionary) -> void:
	storage.items = next_items.duplicate(true)
	storage.units = {
		"test_hammer": {
			"tool_id": "stone_hammer",
			"name": "Test Hammer",
			"worker_id": "test_worker"
		}
	}
	storage.food_portions = {"barley_bread": 2}
	storage._transfer_in_progress = false
	storage_changed_count = 0
	attempt_reentrant_changes = false


func _on_storage_changed() -> void:
	storage_changed_count += 1
	if attempt_reentrant_changes:
		reentrant_can_consume_result = storage.can_consume_materials({"stone": 1})
		reentrant_consume_result = storage.consume_materials({"stone": 1})
		reentrant_refund_result = storage.refund_materials({"stone": 1})


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
